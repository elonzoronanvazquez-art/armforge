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

## Creature / guardian system: known issues

* **Animation is procedural.** The creatures move as one rigid body plus Motor6D limbs; the two whole-body AI meshes (Quarry Colossus, Grom)
  cannot raise arms, so their attacks read from the ground telegraph, the body rearing up and the status text. Authored animations (or a
  rigged mesh) are the biggest visual upgrade for the fights.
* AI meshes exist for the first five creatures only; the Crystalfall and Emberfang creatures use recoloured procedural bodies.
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
