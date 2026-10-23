# ARMFORGE architecture

## Principles

* **The server is authoritative.** Clients request actions (punch, use skill, press in a training game, UI requests) and
  render feedback. Damage, rewards, durability, cooldowns, ownership, equipment, purchases, boosters, skills, levels,
  rebirth, island access, training grades and saves are decided on the server from validated input.
* **Pure logic is separate from Roblox glue.** Everything with rules lives in `src/shared/Logic` and `Config` as pure
  Luau, unit tested under Lune with the exact same source files (a tiny Instance/Datatype emulation, see
  `tests/support/Loader.luau`). Services and controllers are thin glue over that logic.
* **Data-driven content.** Arms, rocks, islands, skills, boosters, training, animations and cosmetics are tables in
  `Config/`. Adding content is editing data (see ADDING_CONTENT.md).
* **Strict typing, both Luau solvers** (`--!strict` in every file; `scripts/typecheck.ps1` runs luau-lsp with the old and
  new solvers).

## Layout

```
src/shared  (ReplicatedStorage.Armforge)
  Config/    Game, Arms, Cosmetics, Rocks, Islands, Skills, Boosters, Training, Progression, Animations, Assets
  Logic/     Formulas, Combat, RockGeometry, RockSim, Equipment, Boosters, Skills, Islands, Progression,
             TrainingLogic, DataSchema, Persistence, PoseMath, RateLimiter      <- pure, tested
  Runtime/   ArmBuilder, ArmDesigns                                            <- builds arm visuals (server + UI previews)
  Net.luau   remote definitions;  Types.luau;  Util/ (Rng, Signal, Validate, Format)
src/server  (ServerScriptService.Armforge)
  Main.server.luau        bootstrap (world first, then services, then players)
  Services/  DataService, Sessions, Sync, PlayerService, ArmService, RockService, CombatService, ProgressService,
             TrainingService, ProgressionServices (islands, rebirth, boosters, skills), Requests
  World/     WorldBuilder, IslandTerrain, Build (+ AI mesh loading), RockBuilder, Islands/{Forgeheart,Crystalfall,Emberfang,Voidreach}
  Dev/       DevTools (Studio only)
src/client  (StarterPlayerScripts.Armforge)
  Main.client.luau, Store.luau
  Controllers/  Input, Combat, ArmAnimator, Effects, Camera, Target, Atmosphere, DevCam (Studio only)
  UI/           UI (manager), Theme, Widgets, Hud, Notifications, Splash, Messages + 7 panels (Arms, Skills, Boosters,
                Islands, Rebirth, Settings, Training)
```

## Networking

| Remote | Direction | Purpose | Server protections |
|---|---|---|---|
| `Punch(rockId, seq)` | C->S | request a strike (rockId 0 = whiff) | token bucket (9/s, burst 6), cooldown check with 90ms tolerance, reach + island checks |
| `Skill(skillId, rockId)` | C->S | cast a skill | rate limit, learned + cooldown + target checks |
| `Training(action, ...)` | C->S | start / press / tap / hit / stop | rate limit, server clock, per-game validation |
| `Request(action, args)` (RemoteFunction) | C->S | every UI action | arg validation (`Util/Validate`), rate limit, pcall wrapper |
| `Sync(snapshot)` | S->C | the owner's state (coalesced, <= 10/s) | n/a |
| `Fx(kind, payload)` | S->C | Swing, Hit, Break, Spawn, Skill, Wave, Travel, Rebirth | sent only to players within 120 studs |
| `Notify(kind, payload)` | S->C | Reward, LevelUp, Toast, Island, Rebirth | n/a |
| `TrainingS(kind, payload)` | S->C | mini-game state | n/a |

`tests/wiring.spec.luau` fails the build if a remote, effect kind, notification kind, request action, panel or sound key is
used on one side without existing on the other.

## Strike resolution (CombatService)

1. Client input -> `CombatController` picks a target (`TargetController`), faces it, **plays the swing immediately** and
   sends `Punch`.
2. Server validates (rate, session, character alive, cooldown, rock exists/alive, island unlocked, reach + 6 studs of
   latency slack), advances the combo, picks the move from the arm's attack style, and broadcasts `Swing`
   (move name, animation speed, the cooldown it applied).
3. The server applies damage at **`PoseMath.contactDelay(move, cooldown)`**, the animation's contact frame, after
   re-checking the rock generation, aliveness and reach. Visible hit and mechanical hit are the same instant.
   Measured in Studio: input -> impact effect 0.25-0.27s against a 0.20s contact frame (about 3 frames of remote + task
   scheduling overhead).
4. `Combat.resolveHit` (pure) computes damage: trait, skill multiplier, crit, resistance and armor pierce.
5. `RockService.damage` -> `RockSim.apply` mutates authoritative state, strips chunks, updates replicated attributes
   (`Hp`, `Stage`), fires `Hit`/`Break`, and on death pays out exactly once.

## Rock destruction

* `RockGeometry.generate(def, seed)` (pure, deterministic) lays out N chunks in three layers: **shell** chunks on an
  ellipsoid/slab/spire/geode envelope, **mid** chunks beneath them (each knows the shell chunk `cover` that hides it) and
  **core** chunks near the centre. Four silhouettes: Boulder, Slab, Spire, Geode (open crown of crystals).
* `RockSim` is the state machine: `apply(state, userId, damage, hitDir, minChunks)` removes
  `ceil((1 - hp/maxHp) * removable) - removedCount` chunks (at least `minChunks`), choosing the chunks **nearest the
  impact direction** among those that are exposed (shell first, then mid chunks whose cover is gone). It always leaves
  one removable chunk until the killing blow. On death it returns the remaining chunks for the collapse; `payout` runs
  once (`paid` flag), `respawn` bumps a `generation` counter so delayed hits for a previous life are discarded.
* `RockBuilder` turns the layout into anchored, non-colliding parts: AI-generated low-poly meshes (`RockA/B/C`,
  `CrystalShard`) for shell/mid chunks (colour and material from the rock def), a per-rock AI "heart" mesh for the core,
  with primitive Part/Wedge fallbacks. One invisible cylinder provides collision.
* The **server strips chunks by destroying parts** (so every client and late joiner agrees on the geometry) and tells nearby
  clients what broke; **clients simulate debris, sparks and dust themselves** (capped pool, hand-rolled ballistics, no
  physics) so destruction costs the server nothing.
* After the collapse a rubble model stays for `aftermath` seconds, then the rock respawns with a fresh layout and a pop-in.

## Procedural animation

No animation assets are uploaded. `Config/Animations` holds keyframed poses (Euler degrees per joint plus root offsets) per
move; `Logic/PoseMath` samples and mirrors them; `Controllers/ArmAnimator` applies them to every visible character by
writing joint `Transform`s after Roblox's Animator (restored in `PreAnimation`), supporting both AnimationConstraint and
Motor6D rigs. Moves have anticipation -> acceleration -> contact -> follow-through -> recovery, torso rotation, weight
transfer, hit-stop on the attacker, trails and a camera shake proportional to the move's `shake`. If a cooldown is shorter
than a move the animation is sped up so strikes never overlap. (R15 avatars are required.)

## Equipment

`PlayerData.arms.equipped` is a single string, so only one set can ever be active. `ArmService.refresh` calls
`ArmBuilder.attach`, which **destroys any existing `ArmforgeArms` model first**, hides the real limbs and welds the new
pieces. `ArmDesigns` lists each arm's pieces (AI gauntlet mesh + primitives, gated by upgrade tier). Cosmetics are resolved
by `Equipment.visualRecipe` and never touch stats.

## Save data (`Logic/DataSchema`, schema version 2)

```
version, coins, shards, level, xp, skillPoints, rebirths, firstJoin, lastSave
arms        { owned = {id=true}, equipped = id, levels = {id=n} }
cosmetics   { owned = {"kind:id"=true}, equipped = {armId = {palette, finish, trail, glow}} }
training    { power|haste|precision|endurance = { level, points } }
skills      { ranks = {skillId=n} }
boosters    { inventory = {id=n}, active = {id=secondsLeft} }
islands     { unlocked = {id=true}, current = id, completed = {id=true} }
guardians   { defeated = {islandId=true} }   (v2: set only by Guardians.recordDefeat; completed mirrors it)
tutorial    { step, flags = {flag=true} }
settings    { sfx, music, shake, uiScale, reduceFx, damageNumbers }
stats       { rocksDestroyed, totalDamage, strikes, playSeconds, trainingSessions, creaturesDefeated, guardianVictories }
```

`DataSchema.reconcile` clamps every number, drops unknown ids and re-fills defaults, so corrupt or tampered data cannot
break a session; `Migrations[v]` upgrades older versions. Bump `Game.Data.schemaVersion` whenever content or fields are added
that an older server could not round-trip: records from a newer schema are refused by older servers rather than downgraded.

`Logic/Persistence` implements session-locked load/save over any store with `UpdateAsync`:

* **Load** takes the lock `{jobId, time}`. A fresh lock held by another job blocks the load ("locked"); stale locks (10 minutes)
  can be taken over. A record that is not a table, or comes from a newer schema, is refused ("corrupt" / "newer_schema") and
  nothing is written. Failed loads therefore never turn into defaults that get saved.
* **Save is fenced**: it commits only while the record still carries this job's lock, otherwise it fails with "lost_lock". A
  server that lost its session (stale, taken over, even if the new owner already released) cannot overwrite newer progress;
  `DataService` then stops writing for that session and removes the player.
* **Release** (`Persistence.release`) clears only the lock, used when a player leaves before their session went live.

`DataService` retries with backoff, serialises saves per session (a release waits for an in-flight autosave; a leaving session
only saves with release), autosaves every 75s, saves on leave, and in `BindToClose` saves everyone and also waits for leave-saves
already in flight. It uses a **separate store name in Studio** (`..._Studio`), probes with a read in Studio only (a live server
does no DataStore traffic at boot) and falls back to an in-memory store (loudly) only in Studio. Players are kicked, not
defaulted, if their data cannot be loaded safely. Studio-only failure injection (`ArmforgeFailStore` workspace attribute,
`failStore` dev command) drives the failure paths against the real store; see PERSISTENCE_TEST.md.

## Creatures and encounters

* `Config/Creatures` (data) -> `Logic/CreatureSim` (the pure combat state machine) -> `server/Services/EncounterService` (glue) ->
  `server/World/CreatureBuilder` (model) -> `client/Controllers/CreatureController` (animation, telegraphs, readouts).
* `Logic/EncounterSM` owns the rock-to-creature lifecycle (SEALED, REVEAL, COMBAT, DEFEATED, RECOVERY, RESPAWNING); `RockService`
  hands over at the final hit through `setEncounterHandler` and the encounter asks for the rock's respawn when the creature is gone.
* Creatures share the rocks' id space (a punch at the rock id hits the creature once it is in COMBAT), so `Punch` / `Skill` / the
  targeting client needed no new remotes. Damage, armor / core / interrupt rules, rewards and guardian completion are server-only.
* `Logic/CreatureStats` derives health from a reference arm and fight length; `Logic/Guardians` and `Logic/Islands.requirements` implement the
  two-part island gate; `Logic/EncounterInfo` is what a sealed rock tells the player.
* Details, rules and numbers: [CREATURES.md](CREATURES.md).

## Rocks: respawn safety and queries

* A destroyed rock respawns after `aftermath + def.respawn`, but never solid on top of a player: `Logic/RespawnGuard` checks the
  new layout's footprint (plus `Game.Rocks.respawnClearance`) against every character root every `respawnRetry` seconds and holds
  the respawn back without moving or touching anyone. After `respawnMaxDefer` the rock returns as a non-solid "ghost"
  (`Ghost` attribute, collider off) and turns solid as soon as the footprint is clear, so an idle player cannot stall it.
* Combo and Overclock stacks are recorded only when a strike lands (`Combat.registerStrike` at contact); the swing animation
  uses `Combat.peekStrike`. Equipping resets the chain.
* `RockService.near` uses `Logic/SpatialGrid` (rocks never move horizontally); burning rocks live in their own set.

## Testing the server services

`tests/support/ServerWorld.luau` is a deterministic fake Roblox server (virtual clock and scheduler, Instance tree, Players,
CollectionService, DataStore with latency/failure injection). It loads the REAL `src/server/Services` through
`tests/support/Loader.luau` (`Loader.new{ server = true, env = ..., replace = ... }`), replacing only the mesh builders, so
interleavings such as "autosave racing a leave" or "player stands where a rock respawns" are reproducible. See
`tests/server_*.spec.luau`. It does not replace Studio playtests or the live DataStore checklist.

## World

Everything is generated at server start: lighting, sea, island terrain (voxel height fields with noise, flattening
features and slope-based materials via `Terrain:WriteVoxels`), landmarks, stations, prompts, spawns and finally rocks
(seeded Poisson-style placement on raycast ground, slope-checked). The place has StreamingEnabled; rock models use
`Atomic` streaming and clients discover rocks through the `ArmRock` CollectionService tag.

## Performance budgets (Config/Game.Budgets)

Client debris <= 56 parts, <= 3 impact lights, <= 10 simultaneous sounds, <= 8 damage numbers, pooled emitters/rings/balls.
Server: 160 rocks max (72 placed), ~2,800 parts total, 43 lights, 26 emitters; clients stream roughly 1,100 of them.
Measured (Studio, dev PC): idle 60 fps; a 240-hit burst across 8 rocks in 3 seconds held 60 fps (worst frame 22ms) with at
most 142 effect instances alive. Reduce-effects in the menu cuts particle counts to 40%.

## Studio tooling (never ships in a live experience)

`DevTools` and `DevCamController` are gated by `RunService:IsStudio()`; `tests/wiring.spec.luau` asserts the gating and that
nothing outside `Dev/` touches the bridge. `scripts/` drive Studio over the Studio MCP server (`studio_sync.py` hot-syncs
scripts, `dev.py` calls the dev bridge, `tour.py` captures a visual tour, `gen_assets.py` runs the AI mesh generation).
