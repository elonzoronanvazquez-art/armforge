# Known issues and next priorities

## Known issues / limitations

* **Persistence and multiplayer are unverified live** (see VERIFICATION.md). Publish a test place, enable Studio API access,
  and run two clients before shipping.
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

## Next development priorities

1. Publish a private test place, verify DataStore saves (load, autosave, leave, BindToClose, session lock) and a two-client run
   (shared rock kill, equipment replication, swing replication).
2. A real mobile pass: profile on a mid-range phone, tune `Game.Budgets` and the reduce-effects preset, test touch ergonomics.
3. Art: custom upper-arm/pauldron meshes per family, rock "crack" decals for the FRACTURED stage, richer terrain
   (material variants via `generate_material`), a second landmark per island, animated hearts.
4. Voidreach: terrain, rocks (`Config/Rocks` + fields) and a builder; its progression data already exists (`comingSoon`).
5. More arms (a Tempest rapid-strike set, Verdant resource set) using ADDING_CONTENT.md; arm-specific skills.
6. Events/quests/achievements feeding the existing booster inventory; an optional, ethical monetisation layer (cosmetics,
   convenience boosters, never random paid rewards or progression skips).
7. Telemetry hooks for the first ten minutes (time to first rock, first upgrade, tutorial drop-off).
