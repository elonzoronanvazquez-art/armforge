# Known issues and next priorities

## Known issues / limitations

* **Persistence and multiplayer are unverified live** (see VERIFICATION.md). The persistence logic is hardened and tested against
  a fake DataStore; run `docs/PERSISTENCE_TEST.md` in a PRIVATE test experience and a two-client session before shipping.
* A rock whose footprint a player keeps occupying comes back as a non-solid ghost after 20 s (it can be mined, and turns solid
  once the player moves). Tune `Game.Rocks.respawnClearance/respawnRetry/respawnMaxDefer` with real play.
* If a final leave-save fails after all retries the lock stays until it expires (10 minutes) or the same server loads the
  player again; the failure is logged (`save failed`) but there is no durable retry queue.
* The combo animation for a swing is chosen when it starts, but stacks are recorded when it lands, so two swings started before
  the first lands (only possible at extreme haste) can show the same combo move.
* Arm visuals: the AI gauntlets look good, but the shoulder/upper-arm pieces are still simple primitives (boxy pauldron
  slabs on Stonebreaker, rope-wrapped sleeve on the Starter fabric). Left arms are mirrored right-hand meshes.
* Rock silhouettes read as chunked formations rather than single smooth boulders; some shell slabs show a lilac cast under
  certain lighting (Basalt). Hearts are static meshes (no animation).
* The first level takes ~30s and the first upgrade two rocks: intentional, but tune with real player data.
* Terrain uses stock materials: the Pavement plaza shows a strong herringbone pattern; ground textures repeat.
* Audio: free library effects only, some reused at other pitches (coins, level-up); no music; ambience beds are quiet loops.
* Strike impact effects arrive ~3 frames after the animation's contact frame (remote + scheduling). The local attacker could
  predict the first sparks at contact and reconcile with the server's `Hit`.
* Proximity checks (Skyport, Reforge Core, training stations) use the client-owned character position; harden with server
  movement validation if exploiting becomes a problem.
* Gamepad: punch (R2) and skills (D-pad) work; the custom panels have not been set up for gamepad selection.
* There is no on-screen button for panel opening on very small screens other than the menu column; tablets and phones were
  only checked in the emulator.

## Biome sketch: built and deferred

Built (see GAME_DESIGN.md "Biomes"): the island ladder, per-biome reward boosts (Emberfang +50% coins and XP, HUD and Islands panel), the
fishing dock and more trees on the starter island, the Mossveil jungle and the Dustwake desert ruins end to end (terrain, props, rocks,
creatures, guardians, balance simulation, live guardian runs in Studio). Not built:

* **Mountain** is built as Frostpeak Mountain, including the climbing mechanic, a working tramway, three mini bosses and the Summit Momentum
  boost. Caveats: the climb is judged from client-reported positions (plausibility checks only, like every other proximity check here); the
  tram carries riders by anchoring their characters and moving them each frame, which looks steppy at network rate; the cabins are simple
  boxes; the mini bosses use the generic procedural bodies; the sketch's boost wording ("climb/tram boost 50% exp and ~7% dollars") was
  interpreted as a timed island boost earned by finishing a climb or riding up.
* **Volcano** is built as Emberfang Volcano (cone, crater lake, lava rivers and pools, molten rocks, scorched trees) with its +50% boost.
  Lava is decorative: it does not hurt, and the rivers are glowing strips, not terrain water.
* **Steampunk** is built as Cogspire Foundry (gear gate, Great Clock and engine room, spinning gears, pipes, airships, four rocks and creatures,
  Cogheart as the guardian). Its gears turn client-side through the `Spin` tag; the airships and clock hands are decorative. The sketch gave no
  steampunk mechanics, so it has no boost.
* **Fishing, The Atlantic Sea and the vine teleport are built** (see GAME_DESIGN.md, "Zones"). The sketch's vine text was cut off, so the
  vine's destination (a floating Canopy Grove with a gift chest) and its rewards are an interpretation; the 2% is from the sketch. Fishing
  has no rod or fish models, no bobber animation and no sounds (the bite is a toast, a bar and a flash); the Atlantic Sea has no water
  below the atoll beyond Roblox's own terrain water, and Atlantic and Grove ambience beds reuse existing loops.
* Mossveil and Dustwake creatures use the generic procedural bodies (tinted crawler, brute and titan templates) and the guardians have no
  generated rigs yet. AI meshes and segmented rigs (`scripts/gen_rigs.py`) are the polish step; Studio's `generate_mesh` was not used this
  sprint.
* Jungle and desert ambience beds reuse existing loops (placeholders); no new audio was sourced.
* The jungle trees are stylised primitives with umbrella canopies; the desert ruins are blocks and cylinders. Authored meshes (a proper
  jungle tree, hieroglyph decals, a real colossus) would lift both.
* The sketch's text for Mountain and Jungle boosts was partly cut off; only the clearly legible numbers were recorded.

## Creature / guardian system: known issues

* **Animation is procedural.** Every rigged creature swings real limbs (arms, legs, head, tail), but the motions are generic poses driven from the
  replicated state, with rigid mesh parts and no skinning, so joints show seams. Authored animations are the next visual upgrade.
* The generated rig palettes do not always match the prompts or each creature's identity (the Choir Behemoth is a thin winged figure, the Magma Golem is
  grey, Cinderjaw is blue-stone), and the Amethyst Warden is small. Regenerate with tighter prompts, or pick a different generation, before the polish pass.
* The final posed screenshots of the rigs could not be captured (the Studio screenshot tool stopped responding late in the session); facing and poses
  were checked numerically, so a visual review of every creature is still owed.
* Creatures walk at the height of their rock's base and ignore slopes; the islands are flat enough that this is not noticeable.
* Players cannot collide with creatures (a moving anchored collider would shove or trap them), so a creature can overlap a player who
  stands still inside it.
* One early Studio run showed a guardian's armor open without a Charged Smash being sent; three later runs with tracing did not
  reproduce it and the unit / integration tests cover the armor rules. Worth a look in a real multi-client session.
* Shared encounters are verified server-side and by simulation only; a real second client has not fought one.
* The two-part island gate makes the first rebirth (about 100 minutes in the greedy simulation) the exit from Forgeheart; tune `Config/Creatures`
  rewards and `Progression.Rebirth` with real play data.

## Visual-polish priorities after this sprint

1. Authored creature animations and rigged meshes; arms for the Colossus and Grom (a rigged mesh, or split limb meshes).
2. A distinct reveal per creature (rock-specific debris, creature roar sounds) and guardian arenas (ground decals, a barrier ring).
3. Attack VFX that match each creature (rock throws, crystal beams, lava rivers) instead of the shared ground markers and rings.
4. Creature hit sounds and voice; audio for telegraphs.
5. Sealed-rock presentation: cracks that glow brighter as the rock wears, a silhouette of the creature inside.
6. Boss bar phase markers, a guardian intro sequence, and Islands-panel art for the guardian states.

## Next development priorities

1. Publish a private test place and run `docs/PERSISTENCE_TEST.md` (load, autosave, leave, BindToClose, session lock, failure
   drill), then a two-client run (shared rock kill, equipment replication, swing replication, respawn next to another player).
2. A real mobile pass: profile on a mid-range phone, tune `Game.Budgets` and the reduce-effects preset, test touch ergonomics.
3. Art: custom upper-arm/pauldron meshes per family, rock "crack" decals for the FRACTURED stage, richer terrain
   (material variants via `generate_material`), a second landmark per island, animated hearts.
4. Voidreach: terrain, rocks (`Config/Rocks` + fields) and a builder; its progression data already exists (`comingSoon`).
5. More arms (a Tempest rapid-strike set, Verdant resource set) using ADDING_CONTENT.md; arm-specific skills.
6. Events/quests/achievements feeding the existing booster inventory; an optional, ethical monetisation layer (cosmetics,
   convenience boosters, never random paid rewards or progression skips).
7. Telemetry hooks for the first ten minutes (time to first rock, first upgrade, tutorial drop-off).
