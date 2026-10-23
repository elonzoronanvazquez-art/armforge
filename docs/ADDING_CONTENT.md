# Adding content to ARMFORGE

Run `lune run tests/run` after every change: `config.spec`, `wiring.spec` and the balance simulation catch most mistakes
(unknown ids, missing sounds, arms without designs, islands without rocks, remotes without handlers).

## A new arm set

1. **`Config/Arms.luau`**: add a def (stats, cost, requirements, `trait`, `attackStyle`, palette, material, skill
   affinities) and append its id to `Arms.Order`. Rarity must exist in `Arms.Rarities`.
2. **`Logic/Combat.luau`**: if it has a new `trait`, implement it in `resolveHit` (or `stats` for speed/crit traits) and
   add a test in `tests/combat.spec.luau`. Reuse `"Finisher"`, `"Overclock"` etc. only if the behaviour is identical.
3. **`Config/Animations.luau`**: add moves and a `Styles` entry named by `attackStyle` (use `MirrorOf` for the left-hand
   version). Every move needs a key at its `contact` time, neutral first and last keys (`config.spec` enforces it).
4. **`Runtime/ArmDesigns.luau`**: add a `Designs[armId]` piece list (>= 4 base pieces and pieces at tiers 1, 2 and 3) and an
   `Effects` entry. For an AI gauntlet, generate it (`scripts/gen_assets.py`), register it in `Config/Assets.Meshes`, and
   add a `Mesh` piece plus `fallback = true` primitives (`wiring.spec` checks mesh keys).
5. Balance: power should rise ~3x per tier; check `tests/balance.spec.luau` milestones.

## A new rock family

1. **`Config/Rocks.luau`**: add a def (`island`, `shape.kind` Boulder | Slab | Spire | Geode, `chunks`, `core`, colours,
   materials, `sound` = Stone | Metal | Crystal | Magma | Obsidian, rewards, `respawn`, `weight`).
2. List it under a field in **`Config/Islands.luau`** (`config.spec` requires every rock to be placed somewhere).
3. Optional: a heart mesh in `RockBuilder`'s `CORE_KEYS` (falls back to a neon core).
4. A new `sound` key needs `Hit<Key>` and `Break<Key>` in `Config/Assets.Sounds` (`wiring.spec` enforces it).

## A new creature (or a rock that holds a different one)

Add a def to `Config/Creatures` (archetype crawler / brute / shard / titan, `fight = { arm, level, seconds }` for its health,
attacks with windup / recovery / area, optional armor, core and interrupters, reward multiples, recommended skills, palette), then
point a rock's `encounter` (`Config/Rocks`) at it. `tests/guardians.spec` checks fair telegraphs, learnable skills and boss mechanics;
`tests/encounter_balance.spec` (add a line to its PLAN table) tells you the fight length and whether punching alone is a shortcut.
An AI body mesh is optional: register it in `Config/Assets.Meshes` and set `visual.mesh` (and `meshYaw` to face -Z, `meshLimbs` for a
whole-body mesh). See [CREATURES.md](CREATURES.md).

## A new island

1. `Config/Islands.luau`: def with `requires`, `center`, `arrival`, `fields`, theme colours (and `comingSoon = true`
   until it is built; those cannot be unlocked or entered).
2. `server/World/Islands/<Name>.luau`: `features()` (terrain shaping) and `build(folder, ctx)` (spawn registered with
   `ctx.spawn(id, spawn)`, a return Skyport via `Forgeheart.skyport`, landmarks). Add it to `WorldBuilder.terrainSpec` and
   `build`.
3. `AtmosphereController.THEMES` for its lighting; unique terrain materials give it a unique palette.

For a guardian: add a seal rock (`size = "seal"`) and the island's `guardian = { creature, seal, position, rebirths }`; the next island's
requirements pick up the guardian gate automatically (`Logic/Islands.requirements`).

## A new skill / booster / training station

* Skill: `Config/Skills` (def + `Effects`), animation in `Config/Animations.SkillMoves`, effect numbers in
  `Logic/Skills.effect`, behaviour in `CombatService.onSkill` (instant buffs go through `Combat.startSkill`).
* Booster: `Config/Boosters` (def, and a `StatCap` entry for a new stat). Apply the stat in `Formulas`.
* Training station: `Config/Training` (station + stat), a `TrainingLogic` grader and a driver in `TrainingService` for a new
  mini-game kind, a builder in `Forgeheart.buildTraining`, and a renderer in `UI/TrainingPanel`.

## Economy knobs

All in `Config/`: `Progression` (XP curve, rewards, rebirth rules), `Arms` (power/cost growth), `Training`, `Boosters`,
`Rocks` (hp, rewards), `Game` (budgets, rate limits, combat caps). `Game.Dev.progressionMultiplier` multiplies rewards **only in
Studio** (`ProgressService` checks `RunService:IsStudio()`).
