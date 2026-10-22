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

## Save data (`Logic/DataSchema`, schema version 1)

```
version, coins, shards, level, xp, skillPoints, rebirths, firstJoin, lastSave
arms        { owned = {id=true}, equipped = id, levels = {id=n} }
cosmetics   { owned = {"kind:id"=true}, equipped = {armId = {palette, finish, trail, glow}} }
training    { power|haste|precision|endurance = { level, points } }
skills      { ranks = {skillId=n} }
boosters    { inventory = {id=n}, active = {id=secondsLeft} }
islands     { unlocked = {id=true}, current = id }
tutorial    { step, flags = {flag=true} }
settings    { sfx, music, shake, uiScale, reduceFx, damageNumbers }
stats       { rocksDestroyed, totalDamage, strikes, playSeconds, trainingSessions }
```

`DataSchema.reconcile` clamps every number, drops unknown ids and re-fills defaults, so corrupt or tampered data cannot
break a session; `Migrations[v]` upgrades older versions. `Logic/Persistence` implements session-locked load/save over any
store with `UpdateAsync` (a second server cannot load a live session; stale locks expire after 10 minutes; a server that
lost its lock cannot overwrite). `DataService` retries with backoff, autosaves every 75s, saves on leave and in
`BindToClose`, uses a **separate store name in Studio**, and falls back to an in-memory store (loudly) only in Studio.
Players are kicked, not defaulted, if their data cannot be loaded safely.

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
