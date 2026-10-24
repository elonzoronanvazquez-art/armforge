# Creatures, rock encounters and island guardians

Every rock is a sealed prison. Breaking it releases the creature inside; beating the creature pays out; each island ends with a
guardian that gates the next island together with a rebirth.

```
approach rock -> punch (rock wears: INTACT, SURFACE, CHIPPED, FRACTURED) -> final hit -> mining payout (a share)
   -> REVEAL (creature emerges, invulnerable) -> COMBAT (telegraphed attacks, armor, core, skills)
   -> DEFEATED -> single creature reward -> RECOVERY (corpse removed) -> RESPAWNING -> rock rebuilt, SEALED again
```

Everything below is server-authoritative. Clients send the same three things they always did (Punch, Skill, Request); there is no
creature remote, so a client cannot report enemy damage, a defeat or a reward.

## 1. The encounter state machine

`Logic/EncounterSM` is the only authority on "may a creature exist now". States and the legal moves between them:

| State | Meaning | Next |
|---|---|---|
| SEALED | the rock is whole or being worn (`EncounterSM.sealedLabel` maps RockSim's INTACT, SURFACE/CHIPPED, FRACTURED to SEALED, DAMAGED, FRACTURING; the final hit is SHATTERED) | REVEAL |
| REVEAL | the creature has been released and is emerging (invulnerable) | COMBAT, RECOVERY |
| COMBAT | the creature fights (`Logic/CreatureSim` runs its own states, section 3) | DEFEATED, RECOVERY |
| DEFEATED | health reached zero; payout computed exactly once | RECOVERY |
| RECOVERY | corpse (or retreating creature) removed | RESPAWNING |
| RESPAWNING | the rock is being rebuilt (held back while a player stands in its footprint) | SEALED |

Every transition goes through `EncounterSM.to`, which refuses illegal moves, counts `spawns` (one per life) and changes a
`token` whenever a new life starts, so a stale timer from a previous life can never act on the current one. That is what prevents
duplicate spawns, duplicate rewards and "revived" corpses (all covered by `tests/creatures.spec` and `tests/server_encounters.spec`).

How a rock releases its creature (`RockService.collapse` -> `EncounterService.begin`):

1. The final hit lands on the rock (`RockSim`), the rock collapses and pays its **mining share** (`rock.miningShare`, 50% for
   small/medium rocks, 40% for large, 10% for seals) through the normal reward handler.
2. Only then is the encounter handler asked to `begin`. It moves SEALED to REVEAL (a second final hit finds the rock dead and
   the encounter no longer SEALED, so it is refused), builds the creature at the rock's base and announces `Reveal` to nearby clients.
   The rock does **not** respawn by itself any more: the encounter asks for the respawn once the creature is gone.
3. When the emerge time passes the encounter moves to COMBAT. If nobody fights it, the creature heals, and after
   `idleDespawn` (90 s) it retreats: RECOVERY, RESPAWNING, rock rebuilt, **no reward**.
4. Defeat: DEFEATED, `CreatureSim.payout` (once), corpse removed after `recovery` seconds, the rock respawns after its own
   respawn time (a guardian seal after `guardianRespawn`, 240 s).

Interrupted encounters recover on their own: players leaving or dying (the creature disengages and heals, then retreats), a rock
whose respawn is blocked by a player standing in it (see RespawnGuard in ARCHITECTURE.md), server shutdown (encounters are
transient; nothing about them is saved).

## 2. Rock sizes and encounter tiers

Size changes geometry, fracture detail, the creature's scale and the kind of challenge, not just a health number.

| Island | Small (basic enemy) | Medium (needs a learned skill) | Large (elite) | Guardian seal |
|---|---|---|---|---|
| Forgeheart | Granite -> **Cairn Crawler** (lunge) ; Prism (rare) -> **Prism Wisp** (kites, beam) | Ironvein -> **Slag Brute** (armor, slam, sweep) | Forgestone Monolith -> **Quarry Colossus** | Anvil Seal -> **Grom, the Anvil-King** |
| Mossveil | MossStone -> **Mossback Crawler** (pounce) | Rootstone -> **Rootborn Brute** (armor, root slam, thorn sweep) | Jadeheart -> **Canopy Elder** | Root Seal -> **Ymira, the Rootmother** |
| Crystalfall | Quartz -> **Shardling** (fast skewer) | Amethyst -> **Amethyst Warden** (shell, resonance pulse) | Heartstone -> **Choir Behemoth** | Choir Seal -> **Lyrae, the Frozen Chorus** |
| Emberfang | Basalt -> **Ash Hound** (long dash) | MagmaCore -> **Magma Golem** (crust, slam, lava line) | Obsidian -> **Obsidian Executioner** | Caldera Seal -> **Cinderjaw Sovereign** |
| Dustwake | Sandblock -> **Dune Skitterer** (burrow dash) | Relic -> **Husk Sentinel** (gilded crust, spear drop, sand sweep) | Sunstone -> **Tomb Colossus** | Sunken Seal -> **Oszarak, the Buried Sovereign** |

Rock footprints grow from small (radius ~4) to large (7.0-7.4, 40-42 chunks) to seals (radius 10, 46 chunks). Players see what is
inside before breaking it: the targeted rock shows `Contains: <creature>`, a danger rating (1-5), its tier and the recommended
preparation (`Logic/EncounterInfo`, published as rock attributes).

## 3. Creature combat (`Logic/CreatureSim`)

States: EMERGING, IDLE, ENGAGED, WINDUP, ATTACKING, RECOVERING, STAGGERED, TRANSITION (boss phase change), DEFEATED.
The sim is pure and stepped 20 times a second by `EncounterService` with the positions of nearby players.

Fairness rules (enforced by `tests/guardians.spec` content checks):

* every attack has a visible **windup** of at least 0.5 s (guardians: at least 1.0 s) and a **recovery** of at least 0.8 s (1.4 s);
* the area (circle, cone or line) is **locked when the windup starts**, so leaving it works; the client draws it on the ground;
* damage is bounded (< 60 of a player's 100 health); ranged creatures back off before firing; dashes never leave the leash;
* a creature only fights players who can: dead players, players on locked islands and (for guardians) players without the
  rebirths are neither targeted nor hurt, and cannot hurt it.

Skills are the tools (`CreatureConfig.armor`, `core`, `interrupters`):

| Mechanic | Rule | Skill that matters |
|---|---|---|
| **Armor** | basic strikes deal only `armor.mult` (0.12-0.45) until a *breaker* skill lands; then it is open for `breakDuration` seconds | Charged Smash breaks Forgeheart/Emberfang armor; Shatter Wave breaks Crystalfall armor (Amethyst Warden and Emberfang creatures accept either) |
| **Exposed core** | after an `exposesCore` attack (and after a stagger) the core is open for the recovery time; strikes deal `core.mult` (1.6-1.8) | any strike, **but only once the armor is open** (the core sits under the armor); Critical Focus and Overdrive pay off here |
| **Interrupt** | an `interruptible` windup (the big quakes, slams, novas) is cancelled, the creature staggers and its core opens | Charged Smash or Shatter Wave |
| **Phases** (bosses) | below set health fractions the creature pauses (invulnerable for 1.8 s), speeds up and unlocks new attacks | all |

Meltdown (Magma arm) has nothing to ignite on a creature and adds its burn damage to the strike instead; Crystal's resonance splash
only affects rocks.

Preparation scales with tier: a basic enemy needs nothing; a medium creature is 2-6 times slower without its skill; an elite or
guardian is out of reach without it (the simulation below: 0 wins in 8 with punching only).

### Fight simulation (`tests/encounter_balance.spec`)

A scripted player (reacts to telegraphs after 0.35 s, closes to melee, punches, uses Charged Smash on armor and to interrupt)
fights the real `CreatureSim` with the real combat maths. Health comes from `Logic/CreatureStats`: each creature declares the
reference arm (and upgrade level) a player brings and the seconds of full-uptime punching the fight is worth. Results with the
matching loadout (8 seeds each, bot reaction 0.35 s):

| Creature | Tier | Reference loadout | Win rate | Average fight |
|---|---|---|---|---|
| Cairn Crawler | normal | Starter | 8/8 | 12 s |
| Prism Wisp | normal (rare) | Stonebreaker L2 | 8/8 | 26 s |
| Slag Brute | normal (armored) | Stonebreaker L2, Charged Smash | 8/8 | 24 s (105 s punching only) |
| Quarry Colossus | elite | Alloy L3, Charged Smash 2 | 8/8 | 58 s (0/8 punching only) |
| Grom, the Anvil-King | guardian | Alloy L2 after one rebirth | 8/8 | 132 s (0/8 punching only) |
| Mossback Crawler | normal | Alloy L2 after one rebirth | 8/8 | 13 s |
| Rootborn Brute | normal (armored) | Alloy L3, Charged Smash | 8/8 | 33 s |
| Canopy Elder | elite | Alloy L5, Charged Smash 3 | 8/8 | 55 s (0/8 punching only) |
| Ymira, the Rootmother | guardian | Alloy L4 after two rebirths | 8/8 | 118 s (0/8 punching only) |
| Shardling | normal | Alloy L3 | 8/8 | 12 s |
| Amethyst Warden | normal (shell) | Crystal L0, Shatter Wave | 8/8 | 28 s |
| Choir Behemoth | elite | Crystal L4, Shatter Wave 3 | 8/8 | 75 s (0/8 punching only) |
| Lyrae, the Frozen Chorus | guardian | Crystal L2 after three rebirths | 8/8 | 113 s (0/8 punching only) |
| Ash Hound | normal | Magma L1 | 8/8 | 14 s |
| Magma Golem | normal (crust) | Magma L3 | 8/8 | 19 s |
| Obsidian Executioner | elite | Magma L6 | 8/8 | 38 s (4/8 in 410 s punching only) |
| Cinderjaw Sovereign | guardian | Magma L4 after four rebirths | 8/8 | 90 s (0/8 punching only) |
| Dune Skitterer | normal | Void L1 after four rebirths | 8/8 | 10 s |
| Husk Sentinel | normal (crust) | Void L3, Shatter Wave | 8/8 | 24 s |
| Tomb Colossus | elite | Void L5, Shatter Wave 3 | 8/8 | 48 s (3/8 in 472 s punching only) |
| Oszarak, the Buried Sovereign | guardian | Void L4 after five rebirths | 8/8 | 108 s (0/8 punching only) |

Void arms pierce armor (every 4th strike ignores 60% extra), so the Dustwake creatures declare longer reference fights (60 / 120 / 250 s)
than their Emberfang equivalents to land in the same bands; the Tomb Colossus is the one creature where punching alone is merely
slow (3/8 in 472 s) rather than impossible.

The same bot standing still beats the first creature (new players can win by punching) but loses every elite and guardian.
The bot dodges perfectly once it reacts; a person will take more hits, which is what the 100 health points are for.

## 4. Guardians and the island gate

Each playable island has a guardian sealed in a large rock (`Rocks.Seals`, placed by `RockService.populate` at the island's
`guardian.position`, snapped to flat ground). The seal only yields to a player who has reached `guardian.rebirths`
(Forgeheart 1, Mossveil 2, Crystalfall 3, Emberfang 4, Dustwake 5). An ineligible player can walk up to it, read the requirement on the rock, punch it
(nothing happens, they are told what is missing) and watch a fight, but cannot hurt the seal, the released guardian, or be hurt by it.

**The rule** (`Logic/Islands`, `Logic/Guardians`; each part is checked on its own, never inferred from another):

* the NEXT island needs the previous island's guardian **defeated** (`data.guardians.defeated[island]`) **and** that guardian's
  rebirth count (`data.rebirths`), plus the island's own level requirement;
* rebirthing never defeats a guardian and never removes a victory; a victory never grants rebirths;
* `Guardians.recordDefeat` re-validates eligibility itself (rebirths + access to the island), so no caller can complete an island
  the player was not allowed to fight; there is no client remote for any of it.

Chosen interpretation of the rebirth sequence: rebirth N is required to **defeat** the Nth guarded island's guardian (1 to 5); the
unlock of the next island then needs that victory plus rebirth N plus its own level. The ladder gained Mossveil between Forgeheart and
Crystalfall, so Crystalfall's, Emberfang's gates moved from 2 / 3 to 3 / 4 rebirths and Dustwake (after Emberfang, skipping the unbuilt
Cogspire) asks for 5. Existing per-island `requires.rebirths` entries were folded into this. Rebirth resets level, skills, coins and arm upgrades
as before, so a reborn player re-learns the breaker skill on the way back up; every guardian's recommended skill unlocks at level 3
(Charged Smash) or 12 (Shatter Wave) and costs 1-2 skill points, which `tests/guardians.spec` checks against the points available
at the guardian's recommended level.

Progression states the Islands panel distinguishes: *rebirth requirement not met* (sealed, needs Rebirth N, you have M),
*requirement met, guardian undefeated*, *guardian defeated, other prerequisites missing* (it lists them), *all met, next island
can be unlocked*. The unlock is shown only after the server confirms it.

Repeat victories pay `repeatMult` (15%) of the reward and are not completion events. A guardian's seal re-forms 240 s after it falls.

Players who unlocked an island under the old rules keep it: the schema v1 -> v2 migration marks an island's guardian defeated when
the island behind it is already unlocked. Nothing else changes (arms, cosmetics, currency, levels, skills, training).

## 5. Rewards and the economy

* Mining pays `miningShare` of the rock's coins / xp (shards are paid by the rock as before).
* The creature pays through one path (`ProgressService.creatureReward`), once, split by contribution
  (`Creatures.Config.fullPayoutShare` = 10% of the damage earns a full share; the killing blow earns +10%). Rewards are multiples of
  the reference rock's coins / xp (`reward.coinsMult`, `xpMult`) so they follow each island's economy.
* The guardian pays 25x its reference rock on the first victory, shards 25-40, and `repeatMult` afterwards.
* `tests/balance.spec` now includes the creature fight (time and reward) in its greedy-player simulation. Pacing with fights
  included: first upgrade 22 s, level 5 at 2.5 min, Stonebreaker 5.8 min, level 12 at 19 min, Alloy at 37 min, level 30 (the first
  rebirth) at about 100 min. It was 58 min before, but then the player left the first island at level 12 for free; the first rebirth
  and the first guardian are now the gate.

## 6. Multiplayer model

Rocks and creatures are shared. Any eligible player in reach can hurt a creature; rewards are split by contribution
(`CreatureSim.payout`), so a player who only chipped in earns a proportional share and a bystander earns nothing. Guardians are
shared too: only players who meet the rebirth requirement can damage the seal or the guardian, so only they can appear in its
contributor list; each of them who is still in the server when it falls gets `Guardians.recordDefeat` for themselves alone
(`tests/server_encounters.spec`: a bystander and an ineligible player nearby receive neither the reward nor the completion).
Players who leave before the kill get nothing (there are no offline rewards). If everyone leaves or dies the guardian heals, retreats
after 90 s and its seal re-forms, with no change to anyone's permanent progress.

## 7. Persistence (schema v2)

New permanent data (`Logic/DataSchema`): `guardians.defeated[islandId] = true`, `islands.completed[islandId] = true` (mirrored from
the victory record and rebuilt from it on load, never trusted alone), `stats.creaturesDefeated`, `stats.guardianVictories`.
Temporary creature health, state and positions are never saved. Rebirth preserves all of it. Loads of a newer schema are refused by
older servers (see PERSISTENCE_TEST.md); a failed load never writes defaults.

## 8. Assets and animation

See ASSETS.md for the full inventory (real ids, what was inspected in Studio, what is a fallback). Summary:

* twelve creatures are **segmented AI rigs** (separate torso, head, arm and leg meshes generated by Studio's `generate_mesh`, reassembled by
  `server/World/CreatureBuilder` and joined with Motor6Ds so the limbs animate); the Cairn Crawler is a one-piece AI turtle with procedural
  legs and the two shard creatures reuse the rock crystal meshes;
* four procedural body templates (crawler, brute, shard, titan: Parts joined by Motor6D) are the fallback if a mesh fails to load;
* **animation is procedural**: the client drives `Motor6D.Transform` from the creature's replicated state (idle bob, walk cycle,
  windup raise, strike, recovery slump, stagger, roar, collapse) in `client/Controllers/CreatureController`. No animation asset
  was authored or uploaded.

## 9. Adding a creature or an island

1. Add a def to `Config/Creatures` (archetype, `fight`, attacks, mechanics, reward, recommended skills, palette).
2. Point a rock's `encounter` (`Config/Rocks`) at it; add the rock to an island field. For a guardian add a seal rock and the
   island's `guardian = { creature, seal, position, rebirths }`.
3. `lune run tests/run` checks the content rules (fair telegraphs, learnable skills, boss mechanics, health, rewards) and the fight
   simulation tells you whether it is a sensible length. No service code changes.
