# ARMFORGE: game design and rules

All numbers below live in `src/shared/Config/*`; nothing is duplicated in code. Pacing is checked by
`tests/balance.spec.luau` (a greedy-player simulation) and `tests/progression.spec.luau`.

## Pillars

1. **Arms are the game.** Equipment, combat identity, collection and progression are all arms.
2. **Destruction you can see.** A rock never "just loses a health bar": material is physically stripped, the mineral
   heart is exposed, and the final hit collapses what remains.
3. **Readable power.** Every upgrade, arm and skill changes something the player can see and feel.
4. **Free progression first.** No random paid rewards; boosters and cosmetics are designed to be earned.

## Core loop

Punch rock -> chunks fly, rock changes stage -> collapse pays coins / XP (/ shards) once -> upgrade or buy arms ->
train and learn skills -> level up -> unlock islands -> rebirth for permanent bonuses -> repeat on harder rocks.

## Arm roster

| Arm | Rarity | Power | Strike | Reach | Crit | Pierce | Identity (trait) | Style | Acquire |
|---|---|---|---|---|---|---|---|---|---|
| Starter Fists | Common | 10 | 0.55s | 8 | 5% x1.6 | 0% | Every 3rd punch +45% (Finisher) | Jab, Jab, Cross | Free |
| Stonebreaker | Uncommon | 40 | 0.95s | 9 | 5% x1.8 | 15% | +35% vs stone, tears extra chunks | Overhead slam / side swing | 900 coins, Lv 3 |
| Alloy | Rare | 105 | 0.38s | 9 | 8% x1.7 | 10% | Overclock: hits within 1.3s stack +5% attack speed (x5) | Piston punches | 9,000 coins, Lv 8 |
| Crystal | Epic | 330 | 0.62s | 10 | 28% x2.7 | 10% | Crits send a pulse: 30% damage to 2 nearby rocks | Fencing lunge | 28,000 coins + 6 shards, Lv 14, Crystalfall |
| Magma | Epic | 1,100 | 0.80s | 10 | 10% x2.0 | 20% | Meltdown: hits ignite rocks (12%/s for 3s), +5% coins | Volcano slam | 240,000 coins + 30 shards, Lv 26, Rebirth 1, Emberfang |
| Void | Legendary | 4,000 | 0.70s | 11 | 12% x2.2 | 35% | Singularity: every 4th strike x3 and +60% pierce, +15% coins | Crossed rend | 1.8M coins + 90 shards, Lv 30, Rebirth 2 |

Power at upgrade level L = `basePower * growth^L` (growth 1.14-1.15, max level 15-20). Upgrade cost =
`upgradeBaseCost * upgradeGrowth^L`. Visual tiers (extra plating / glow) appear at upgrade levels 3, 7 and 12.
Each arm also has **skill affinities** (e.g. Stonebreaker +25% Charged Smash, Alloy +30% Overdrive duration).

## Damage

`damage = power * (skill mult) * (trait mult) * (crit mult) * (1 - rockResistance * (1 - pierce))`, minimum 1.
Power = `armPower * (1 + training + rebirth + booster + overdrive bonuses)` (additive inside the bracket).
Haste (attack speed) is capped at +100%; crit chance at 85%.

## Rocks

Three layers of chunks: **shell** (stripped around each hit), **mid** (the exposed mineral layer, only removable once
the shell chunk above it is gone) and **core** (kept until the collapse). Stages by remaining health:
`INTACT -> SURFACE (<100%) -> CHIPPED (<60%) -> FRACTURED (<30%) -> COLLAPSE`, then a short rubble aftermath and a
respawn with a freshly generated layout.

| Rock | Island | Family | HP | Resist | Coins | XP | Notes |
|---|---|---|---|---|---|---|---|
| Granite Boulder | Forgeheart | stone | 60 | 0% | 12 | 8 | the first rock; glowing copper heart |
| Ironvein Outcrop | Forgeheart | ore | 280 | 8% | 60 | 32 | dense slab, rusty mid layer |
| Prism Geode (rare) | Forgeheart | crystal | 900 | 15% | 260 | 110 | 1-2 Forge Shards; AI crystal heart |
| Mossy Boulder | Mossveil | stone | 1,300 | 5% | 150 | 70 | moss-furred boulder, green heart |
| Rootbound Stone | Mossveil | stone | 4,800 | 10% | 480 | 210 | stone strangled by roots |
| Jadeheart Geode (rare) | Mossveil | crystal | 16,000 | 20% | 2,000 | 800 | 2-4 shards |
| Quartz Spire | Crystalfall | crystal | 2,600 | 10% | 520 | 230 | tall spire |
| Snow-capped Amethyst Cluster | Crystalfall | crystal | 9,500 | 15% | 1,900 | 760 | |
| Glacier Heartstone Geode (rare) | Crystalfall | crystal | 34,000 | 25% | 7,200 | 2,600 | 3-6 shards |
| Basalt Slab | Emberfang | stone | 62,000 | 20% | 11,000 | 4,200 | |
| Magma Core | Emberfang | magma | 230,000 | 25% | 40,000 | 14,000 | |
| Obsidian Heart (rare) | Emberfang | magma | 780,000 | 35% | 135,000 | 48,000 | 8-16 shards |
| Ruin Sandblock | Dustwake | stone | 260,000 | 25% | 46,000 | 17,000 | fallen temple block |
| Buried Relic | Dustwake | ore | 950,000 | 30% | 170,000 | 60,000 | gold-banded, cyan glyphs |
| Sunstone Geode (rare) | Dustwake | crystal | 3,200,000 | 40% | 580,000 | 200,000 | 14-26 shards |
| Forgestone Monolith (rare) | Forgeheart | stone | 2,200 | 5% | 420 | 180 | large rock: releases the Quarry Colossus |
| Anvil / Root / Choir / Caldera / Sunken Seal | each island | ore / stone / crystal / magma / ore | 3,600 / 14,000 / 52,000 / 1.15M / 4M | 5% | small | small | guardian seals (rebirth-gated); mining pays only 10% |

Mining pays only a share of these coins / XP once a rock holds a creature (50% small and medium, 40% large); the creature pays the rest.

**Shared kills:** every player who dealt at least 10% of a rock's health gets the FULL reward; smaller contributors get
a proportional share; the killing blow adds +10%. The payout is computed once.

## Creatures and guardians

Every rock holds a creature; breaking the rock releases it and the player fights it with the same arm and skills. Rock size sets the
challenge (small: basic enemy, medium: armored, large: elite) and each island ends with a guardian sealed in a huge rock that only opens
for a player who has rebirthed enough times. Defeating the guardian completes the island; the next island needs that victory **and** the
rebirths, so neither a rebirth nor a victory alone opens it. Full rules, numbers and the fight simulation: [CREATURES.md](CREATURES.md).

## Progression

* **XP to next level** = `floor(25 + 15 * L^1.95)`; max level 40. Each level: +1 skill point, `20 * level` coins and
  milestone rewards (boosters, unlock notes) from `Config/Progression.LevelRewards`.
* **Skills** (learned with skill points once the level requirement is met, ranks 1-5):
  Charged Smash (Lv 3), Critical Focus (Lv 5), Overdrive (Lv 7, with an Overheat penalty afterwards),
  Shatter Wave (Lv 12, bounded to 4 rocks). Cooldowns shrink with Endurance training.
* **Training** (permanent stats, capped by player level): Power Press (Lv 2) trains damage, Speed Bag (Lv 4) attack
  speed, Target Range (Lv 7) crit chance, Endurance Rig (Lv 10) skill cooldowns. Training never exceeds +60% to any
  stat, so rock destruction stays the main source of progress.
* **Boosters** are additive within a stat (capped: coins/XP/training +150%, power +75%, crit +25%); re-activating one
  extends its timer up to its maximum; timers run only while you play.
* **Rebirth** needs level 30 and coins (`250,000 * 3^rebirths`) and standing at the Reforge Core.
  RESETS: coins, level, XP, skill points and ranks, arm upgrade levels, training stats.
  KEEPS: arm ownership and the equipped arm, cosmetics, Forge Shards, unlocked islands, boosters, rebirth count,
  settings and tutorial progress. GAINS (permanent, per rebirth): +25% coins, +20% XP, +10% damage, +15% training,
  plus a Knowledge Surge and a Coin Surge. The rules are data (`Config/Progression.Rebirth.resets`) and tested.
* **Islands** (unlock requires level AND the previous guarded island's guardian victory AND that guardian's rebirths, at a Skyport;
  the server re-checks on every rock hit). The ladder follows the biome sketch, see "Biomes" below.

## Biomes

The world is a ladder of themed islands (`Config/Islands`, ids are internal; names are what players see):

| # | Island (id) | Biome | Unlock | Guardian (rebirths to fight it) | Boost | Status |
|---|---|---|---|---|---|---|
| 1 | Forgeheart Isle (Forgeheart) | starter: forge, plaza, training, armory, **fishing dock**, trees and palms | open | Grom, the Anvil-King (1) | none | built |
| 2 | Mossveil Jungle (Mossveil) | jungle: big lake, waterfall off a rock cliff, giant and small trees, bushes, ferns, mossy rocks, vines, Rootmother's glade | Lv 5 | Ymira, the Rootmother (2) | none | built |
| 3 | Frostpeak Mountain (Crystalfall) | mountain: a 95-stud flat-topped snow mountain, snowy pines, snow-capped crystal rocks, a spiral summit road, scenery tramway, summit guardian | Lv 12 | Lyrae, the Frozen Chorus (3), on the summit | none yet | built (climbing and tramway rides pending) |
| 4 | Emberfang Volcano (Emberfang) | volcano: a 65-stud cone with a crater lava lake and the seal on its floor, lava rivers and pools, molten rocks, scorched trees, ember road | Lv 25 | Cinderjaw Sovereign (4), in the crater | **+50% coins and XP** | built |
| 5 | Cogspire Foundry (Cogspire) | steampunk | Lv 28 | none yet | none yet | teaser platform, coming soon |
| 6 | Dustwake Ruins (Dustwake) | forgotten desert: dunes, semi-exposed and buried temple, colossus, pyramid, obelisks | Lv 28 | Oszarak, the Buried Sovereign (5) | none | built |
| 7 | Voidreach | void | Lv 34 | none yet | none yet | teaser, coming soon |

* **The gate skips unbuilt islands.** An island needs the nearest *earlier island that has a guardian* beaten, so Dustwake is gated by
  Emberfang's guardian while Cogspire is still coming soon (`Logic/Islands.previousGuarded`). When Cogspire gets a guardian it slots in
  between automatically (and Dustwake then needs Cogspire's).
* **Per-biome boosts** (`IslandDef.boost`, `Logic/Islands.rewardBoost`) multiply the coins and XP of everything *earned on that island*
  (rock mining and creature fights), chosen by the island the rock stands on, never by where the player says they are. Shards are not
  boosted. The HUD status card and the Islands panel show the boost. Today only Emberfang has one (sketch: "50% increase in everything").
* Existing saves keep every unlock. Players who already own Crystalfall or Emberfang can still travel there; Mossveil is a new, optional step
  for them. A v1 save is migrated so that any guardian *before* an unlocked island counts as beaten.

### Sketch features not built yet

Fishing rewards (10% chance to sail to "The Atlantic Sea", +25% XP and coins) and the dock's Atlantic zone, the jungle vine teleport (2%),
the mountain's climbing mechanic, working aerial tramway, three mini bosses and the 50% / 7% climbing boosts, and the
steampunk build. They are listed in [NEXT.md](NEXT.md).

## Economy targets (from the balance simulation)

First upgrade and first level within ~30 seconds; Stonebreaker around minute 5; Alloy around minute 30; level 12
around minute 24; level 25 near 50 minutes; level 30 (rebirth) around an hour for an optimal player, which means
considerably longer for a real one. Run `lune run tests/run balance` to print the milestone table.

## Onboarding

A guide path of glowing dashes leads from spawn to the Starter Field, the nearest rock carries a bobbing PUNCH ME
marker until the first one is broken, and a five-step tutorial card (punch, destroy, upgrade, train, explore) advances
from authoritative server flags.
