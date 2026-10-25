# Verification report

What is actually verified, where, and what is not. "Studio" below means a single-client playtest of the Rojo-built place in
Roblox Studio driven through the Studio MCP server (execute_luau on Server/Client, real mouse and keyboard input, screenshots,
console output). Nothing is claimed that was not observed.

## Automated (Lune, `lune run tests/run`): 379 tests, 0 failing

The first block is pure logic; the second block runs the REAL server services (`src/server/Services`) against a fake Roblox server
(`tests/support/ServerWorld.luau`: virtual clock and scheduler, Instance tree, Players/DataStore/CollectionService fakes with latency
and failure injection; only the mesh builders are stubbed). It verifies glue, state transitions and interleavings; it is not a
substitute for Studio or the live DataStore.

| Spec | Tests | Covers |
|---|---|---|
| `config.spec` | 11 | roster (>= 6 distinct arms with distinct traits/styles/cooldowns), rock and island integrity, skills/boosters/training references, animation contact frames and keyframe ordering |
| `rocks.spec` | 17 | geometry determinism and layers; the first hit strips material; INTACT -> SURFACE -> CHIPPED -> FRACTURED -> COLLAPSE; monotonic chunk removal; localised chipping; mid layer only after its cover; kill exactly once; invalid/NaN damage; overkill cap; payout once, shares, shards; respawn; two-player contention |
| `combat.spec` | 25 | stats derivation, training/rebirth/booster bonuses, speed and crit caps, combos, traits (Finisher, QuarryMaster, Singularity, Resonance, Meltdown, Overclock), resistance/pierce, skills (learn, cooldown, Overdrive then Overheat), pose math and contact timing for every arm |
| `economy.spec` | 25 | one-equipped-arm invariant, buying gates and exact charges, upgrade pricing, cosmetics vs stats, schema defaults/reconcile of hostile data, migrations, training grading and caps, persistence (session lock, stale lock, lost lock, retries, corrupt data), rate limiter, 1,000-punch spam |
| `progression.spec` | 20 | XP curve, multi-level gains, max level, rebirth eligibility, **exact reset/preserve rules** and data-driven toggles, island prerequisites (never coins alone), booster durations/extension/caps/non-multiplication, tutorial order |
| `balance.spec` | 5 | greedy-player simulation: first upgrade <= 40s, Stonebreaker 2-15 min, Alloy <= 50 min, level 12 8-75 min, rebirth level not trivial, no dead arms, each arm tier faster than the last |
| `wiring.spec` | 13 | every remote/effect kind/notification/request action/panel/sound key used in code exists on the other side; mesh ids are real; every arm has a design with pieces at every upgrade tier; all files `--!strict`; dev tooling gated to Studio and untouched elsewhere |
| `util.spec` | 6 | untrusted-argument validation, formatting, signals |
| `persistence.spec` | 12 | corrupt / newer-schema records refused and left untouched, fenced saves (a server that lost the lock cannot write even after the new owner released it), lock-only release, reconcile keeps valid progress and owned arms, drops unknown ids, is idempotent, migrations |
| `respawn.spec` | 5 | RespawnGuard footprint test: clearance ring, vertical window, multiple players |
| `spatial.spec` | 4 | SpatialGrid answers identically to a brute-force scan (random points/queries, borders, remove/re-insert) |
| `server_persistence.spec` | 17 | PlayerService + DataService + Persistence: new profile, leave/rejoin, failed load kicks and never writes defaults, locked profile untouched, leave during load (incl. PlayerRemoving before the player detaches) releases the lock, autosave racing a leave, late autosave refused, save failure reporting, stale-lock takeover cannot be overwritten by the old server, BindToClose waits for in-flight leave-saves, no production traffic at boot, Studio uses a separate store with a read-only probe, Studio memory fallback only in Studio, Studio-only failure injection |
| `server_combat.spec` | 12 | CombatService + RockService + Requests: landed hits build combo/Overclock, whiffs (no target, out of reach, locked island, rock dies or player moves before contact) build nothing, malformed arguments, 1,000-punch spam, unloaded sessions, swing effects only to nearby players, equipment replacement |
| `server_rocks.spec` | 18 | rock lifecycle and single payout, respawn, rewards to contributors who stayed, safe respawn (held back while a player stands in the footprint, no movement/damage/rebuild, ghost fallback, watcher cleanup, one respawn per death), `near()` equals brute force over 150 rocks, burn lifecycle, effect radius |
| `server_requests.spec` | 13 | Request validation and rate limit, SetSetting cannot write arbitrary data, purchases charge once, one arm set after equip/upgrade/respawn, snapshot only to the requester and coalesced, Skyport/altar gating, not_ready after leaving |
| `creatures.spec` | 28 | CreatureSim: emerge invulnerability, aggro and leash, telegraph-before-damage, locked areas dodgeable, circle/cone/line geometry, recovery, kiting, dash bounds, armor and breaker skills, core under armor, interrupts, defeat is final and pays once, contribution split, boss phases, healing and retreat; EncounterSM legal transitions |
| `guardians.spec` | 23 | the two-part gate (rebirth alone, victory alone, both), per-island completion, repeat victories, the four UI states, schema v2 defaults, v1 migration keeps arms/cosmetics/currency/islands, round trip, tampered guardians dropped; content rules: seals/guardians/sizes/mechanics, fair telegraphs, learnable skills (no softlock), boss phases |
| `encounter_balance.spec` | 8 | fight simulation of all 13 creatures against matching loadouts (win rate, fight length bands, punching-only is not a shortcut for armored elites/guardians, a stationary player cannot brute-force an elite) |
| `server_encounters.spec` | 24 | the real services on the fake server: partial damage never spawns, one creature per final hit, no rock respawn during an encounter, mining share + single creature reward, second life, real Punch/Skill remotes against creatures, locked islands, telegraph before damage, armor/Charged Smash, unlearned skills rejected, simultaneous final hits, abandoned and dead-player recovery, seal resists ineligible players, guardian victory recorded for eligible contributors only, repeat reward, end-to-end next-island gate through Requests, no client path to fake a victory, persistence across rejoin, interrupted boss fight |
| `server_training.spec` | 10 | station/level/range gating, server-clock grading, rep and tap caps, bad arguments, target index checks, left/died/leave cleanup |

Balance milestones printed by the simulation (optimal play): first upgrade 18s, level 2 32s, level 5 2.8min, Stonebreaker 5.5min,
level 12 24min, Alloy 30min, level 25 48min, level 30 58min. A real player will be slower.

**Typecheck:** `scripts/typecheck.ps1` (luau-lsp, `--!strict`, Roblox definitions): 0 errors, 0 warnings with the old solver and
with `LuauSolverV2=true` (re-run after the hardening sprint). **Build:** `rojo build default.project.json` succeeds; the built place contains every script and opens and
runs in Studio (see below).

## Studio playtest results (single client)

| # | Check | Result | Evidence |
|---|---|---|---|
| 1 | Project builds and opens in Studio | VERIFIED | clean `rojo build` opened in a fresh Studio; boots with only the expected DataStore notice; world built in ~8s, 72 rocks |
| 2 | Player spawns correctly | VERIFIED | character on the Forgeheart plaza, HUD + splash, spawn on the island's pad |
| 3 | Starter arms attached correctly | VERIFIED | exactly one `ArmforgeArms` model on the character, real limbs hidden, screenshots |
| 4 | Punch animations play and align with impacts | VERIFIED (with a measured offset) | key poses captured for every attack style; server applies damage at the move's contact frame; measured input -> impact effect 0.25-0.27s vs 0.20s contact (about 3 frames of remote/scheduling overhead) |
| 5 | A rock visibly chips over multiple hits | VERIFIED | Granite 60 hp: 50, 40, 25, 15, 5, 0 with SURFACE/CHIPPED/FRACTURED then collapse; Prism geode screenshots show the shell stripped to expose the crystal heart |
| 6 | Damage states distinguishable | VERIFIED | HUD stage label + geometry (screenshots of intact, mid, exposed heart) |
| 7 | Final destruction removes material + debris | VERIFIED | chunk count 16 -> 0, rubble model, collapse FX (debris/dust/shockwave) |
| 8 | Rewards granted correctly and only once | VERIFIED | 13 coins / 8 XP exactly once, `rocksDestroyed = 1`; two simulated contributors -> one payout, second kill rejected; 400 same-frame punches -> exactly 1 accepted |
| 9 | Rock respawns | VERIFIED | generation 1 -> 2, 16 fresh chunks, INTACT, ~8.6s after collapse |
| 10 | An upgrade changes actual gameplay | VERIFIED | real mouse click on UPGRADE: coins 100 -> 82, power 10 -> 11.4; three upgrades cost 18/24/33 and gave power 14.8 |
| 11 | Equipping replaces the previous set | VERIFIED | 7 consecutive equips through the server: always exactly 1 arms model, same part count, correct ArmId |
| 12 | Leveling up | VERIFIED | level-up banner with rewards, skill points, booster rewards, tutorial advance |
| 13 | Training produces progression | VERIFIED | all four stations driven through the real remotes: Power 80 pts -> level 2; Speed Bag 80 pts; Target Range 80 pts; Endurance 120 pts -> level 3; XP and tutorial flag awarded |
| 14 | Skills and boosters | VERIFIED | Charged Smash dealt exactly 28 (3.0x power, 8% resist) and refused a second cast on cooldown; Overdrive -> +35% haste, then Overheat -20%, then normal; PowerSurge x1.25; booster extension, none-left, unknown id rejected |
| 15 | Island access restrictions | VERIFIED | travel away from a Skyport, locked island, unmet requirements, coming-soon island all refused; unlock + travel at the Skyport succeeds; the rock hit check also rejects locked islands |
| 16 | Rebirth follows the documented rules | VERIFIED | refused away from the altar; at the altar resets level/XP/coins/skills/upgrades/training, keeps arms/equipped/islands/boosters, adds bonus booster, second immediate rebirth refused |
| 17 | UI usable in gameplay | VERIFIED | all panels screenshotted; real mouse click on a panel button; iPhone 17 Pro landscape emulation: HUD fits, PUNCH button shown, panels scale to fit |
| 18 | Output checked | VERIFIED | no errors/warnings in any run except the expected DataStore-unavailable notice |
| 19 | Visual defects, collisions, accessibility of interactions | PARTIALLY | pathfinding reached the Starter Field, Armory, Training Yard, Reforge Core, Skyport and Deep Quarry; island tours inspected by eye; known cosmetic issues listed in NEXT.md |

Additional checks: all 36 sound slots and 4 ambience beds load (IsLoaded, TimeLength > 0); remotes reject malformed
payloads (strings, NaN, huge ids, tables, wrong arity) and out-of-range actions without errors; cosmetics purchase/equip changed arm
colour and finish and did not change power, and charged exactly the price.

Performance (Studio on a development PC, not a phone): server holds ~2,800 parts (1,758 in rocks, 1,472 MeshParts), 43 lights,
26 emitters; a client streams ~1,100 parts; idle 60 fps; a burst of 240 rock hits in 3 seconds across 8 rocks held 60 fps (worst
frame 22 ms) with at most 142 effect instances alive.

## Biome sprint (jungle, desert ruins, ladder rebuild, per-biome boosts)

Automated (305 tests, strict typecheck clean under both solvers): the new ladder order and biome sequence, gate shifts (rebirths 1 to 5),
the guardian chain skipping the then coming-soon Cogspire (since built; the skip rule is still tested with a simulated unbuilt island), the v1 migration crediting
guardians before any unlocked island, the Volcano-only +50% boost (and its absence everywhere else), the server paying a rock by the boost of
the island it stands on (not where the player is registered), and fight simulations for the 8 new creatures (all 8/8 wins, bands respected,
punching alone is no shortcut). The creature, rock and island content rules in `guardians.spec` / `config.spec` cover the new ids.

Studio (single client, Rojo-built place, screenshots read back): the world builds in ~9 s with 112 rocks (about 9,000 world instances plus
the rock chunks). Seen: the fishing dock with rods, lantern and rowboat; trees and palms on Forgeheart; the Mossveil gate, torch path,
lake with lily pads and reeds, waterfall, giant tree on the horizon, Fern Hollow rocks, the Rootmother's glade; the Dustwake gate,
half-buried temple with the glowing sealed door, seal ring, colossus head in the dune, pyramid top, obelisks, arches, cacti, ribcage in
the distance; the Cogspire teaser; all eight new creatures via the dev showcase; the HUD island line with "+50% coins & XP" on Emberfang;
the Islands panel with seven scrolling cards (boost line, requirements, guardian states). Live runs: the guardian flow itself was played for both new guardians through the dev bridge (rebirths set, seal broken, boss fought, defeat recorded in
`guardians.defeated`: Ymira 68,896 HP, Oszarak 2,858,375 HP).

Not verified: fights against the new creatures by a human (only the scripted bot); a second client; the real DataStore with the migrated
ladder; the HUD boost line after a real `Travel` (the dev `island` command set it); the jungle ambience (placeholder loop); performance on a
phone with roughly 4,000 added world instances. Studio's MCP connection also flaps occasionally ("Place is not open"); retrying works.

## Developer mode

Automated (`tests/devmode.spec`, 18 tests, 340 total passing, strict typecheck clean): the access rule for every case, the pure command kit and
its refusals, a hostile or unauthorized client getting nothing and never being told developer mode exists, and the server path (Studio, a listed
UserId, `goto`, `power`, `god`, `equip`, `reset confirm`, `momentum`). Studio (real play): backtick opened the window, the DEV button showed, and
the `Dev` request called from the client's real remote ran `help`, `kit` (HUD became level 40, 1B coins, 500 shards, Rebirth 6), `goto Dustwake`
(teleported and switched the HUD island), and refused `coins abc` and a bare `reset`.

Not verified: clicking the panel's buttons with a synthetic mouse (the click did not land on the target, so the buttons were exercised through the
same request, not by hand); the live-server paths (listed UserId, creator, group owner) beyond the pure rule and the fake server; the group-owner lookup.

## Mountain mechanics (climbing, tramway, mini bosses, Summit Momentum)

Automated (322 passing, strict typecheck clean): `mountain.spec` covers Momentum (grant, expiry, refresh, island scoping, never saved), Climb
(honest climb completes, teleports and too-fast climbs never pay, falling off resets, spacing of the routes), the tram schedule (both cabins dock
together, monotonic smooth travel, periodic, boarding rules), the mini boss config and eligibility, and on the fake server: rock rewards on
Frostpeak boosted by momentum only while active and only there, a mini boss opening only for eligible players, paying the same twice and
completing nothing, and momentum multiplying mini boss rewards. The fight simulation passes for the three mini bosses (8/8, 51 / 92 / 67 s).

Studio (real play): the character walked straight up the cone to Base Camp and stopped at the crown wall (the slope limit works); it climbed the
Frostline truss to the rim by holding W and `ClimbService` granted momentum (262 s left a few seconds later); the tram boarded through
`TramService.board` while docked, carried the rider to the summit station and set them down there with momentum granted and the HUD chip
"SUMMIT MOMENTUM +50% XP, +7% coins 4:34" showing; a mini boss was fought through the dev bridge (Hoarfang: seal, fight, no guardian completion).
All 135 rocks and the four Frostpeak seals placed at their configured positions. The 110-slab road has median slope 2.1 degrees and a 9.5 degree maximum;
the cable clears the terrain by at least 7.6 studs.

Not verified: two players sharing a cabin or a climb; ProximityPrompt boarding by a real key press (the dev bridge calls the same server function);
the other two routes by climbing (only Frostline was climbed); the steppy look of the ride on a high-latency client; phone performance.

## Steampunk build (Cogspire Foundry)

Automated: 306 passing (a new chain test covers Forgeheart to Dustwake with the real rebirth gates, and a simulated unbuilt island checks the
skip rule), strict typecheck clean. The fight simulation passes for the four new creatures (8/8, bands respected, punching alone is no shortcut)
and for the Dustwake creatures after their gate moved to rebirths 5 and 6. Studio (screenshots read back): the island from the sea with
airships and the clock tower, the gear gate with turning gears, streets and lamps, the Great Clock and sealed engine room, the seal arena with its
piston ring, pipes and steam; all 134 rocks place with no warnings; the Cogheart fight was played through the dev bridge (seal at the clock's foot,
1,336,980 HP creature, defeat recorded). About 14,300 world instances in total now. Not verified: that the gears and clock hands actually turn in
a second client (the Spin tag is handled in AtmosphereController and was seen only indirectly); mobile performance of the added emitters and parts.

## Volcano rebuild (Emberfang)

Automated: 305 passing, strict typecheck clean. Studio (screenshots read back): the cone from the sea with its smoke plume and four lava rivers,
the fang gate and ember-road trailhead, the crater from above (lava lake, glowing floor, ring of fangs), the HUD line "+50% coins & XP". All
112 rocks placed with no warnings; the Cinderjaw fight was played through the dev bridge (seal on the crater floor, 370,352 HP creature,
defeat recorded). Not verified: walking the ember road and the crater wall, performance with the plume, ash and ember emitters on a phone.

## Mountain rebuild (Frostpeak, ex Crystalfall Atoll)

Automated: unchanged at 305 passing (the island id, rock ids, creatures and gates are the same); strict typecheck clean under both solvers.
Studio (screenshots read back): the mountain from the sea and from above, the singing arch and trailhead, snowy pines and snow-capped rocks
on the lower slopes, Snowdrift Meadow, the quarry-bench Crystal Ledge, the summit with its crystal pylons, light beams and station, and
snowfall. Numerics: all 112 rocks placed with no warnings; the guardian seal stands on the summit (y ~ 101); the tramway cable clears the
terrain by at least 4 studs along its whole length; the 120-slab road has median slope 6.4 degrees and p90 10.7 degrees, with two
cliff-edge segments (37 and 62 degrees) where it crosses the Crystal Ledge bench. The Lyrae fight was played through the dev bridge
(seal broken, 103,897 HP creature, defeat recorded as `guardians.defeated.Crystalfall`).

Not verified: a person walking the summit road (the humanoid slope limit is 89 degrees, but the steep segments have not been walked),
the tramway (scenery only), performance on a phone with the added snow, pines and snowfall emitter.

## Creature / guardian sprint

Implemented, tested and (where stated) verified in a single-client Studio playtest. See [CREATURES.md](CREATURES.md) for the design.

| Check | Result | Evidence |
|---|---|---|
| Rock releases exactly one creature, only after the final hit | VERIFIED (Lune + Studio) | partial punches left the Granite alive with no creature; the final punch produced `Creature_6` (Cairn Crawler, 206 hp) in REVEAL then COMBAT; the punches that kept landing never spawned a second |
| Reveal sequence | PARTIALLY | screenshots show the rubble, the creature beside the player and its name / health readout; the dust, ring and camera shake effects were not captured in stills |
| Fight with real input (Punch / Skill remotes) | VERIFIED | client bot in Studio: dodged 7 telegraphs (minHp 37), punched 26 times, cast Charged Smash twice, defeated the Slag Brute in 23 s; reward paid once (creaturesDefeated 1, coins/xp up) |
| Armor and the Charged Smash remote | VERIFIED | a Slag Brute was `armored` until one real Charged Smash (Skill remote): `armorOpen` for 7.0 s (the 7 s break window), 563 damage on that strike (2316 to 1753 hp), then armored again; a guardian punched 40 times without skills never opened its armor (0 of 53 samples) |
| Small / medium / large | VERIFIED | Cairn Crawler, Slag Brute (armor, 2316 hp), Quarry Colossus (elite, 26,626 hp, phase 2 reached; the client bot survived 45 s then fell, as designed) |
| Rewards once, no double pay | VERIFIED | one `Reward` (mining share) + one `CreatureReward` per kill; recovery then a fresh SEALED rock at generation 2 |
| Guardian before the rebirth requirement | VERIFIED | 10 punches on the Anvil Seal left it at 3600 / 3600 hp |
| Guardian after Rebirth 1 | VERIFIED | seal broke, Grom (50,165 hp, armored) emerged and fought; armor opened only through Charged Smash; finished with the dev bridge |
| Completion recorded, next island | VERIFIED | `guardians.defeated.Forgeheart`, `islands.completed.Forgeheart`, stats updated; at the Skyport Emberfang was refused (`requirements`), Crystalfall unlocked and travel worked |
| Output log | VERIFIED | no errors or warnings in the whole session (besides the expected DataStore notice) |
| Performance | VERIFIED (Studio, dev PC) | during a guardian fight with telegraphs: 60 fps, average frame 16.7 ms, p99 18.5 ms, max 19.1 ms; 6 effect instances, 3 telegraph parts |
| Persistence across rejoin | SIMULATED only | the Studio DataStore is unavailable (in-memory); rejoin preservation is covered by the fake-DataStore tests (`server_encounters`, `guardians.spec`) |
| Multiplayer | NOT VERIFIED live | shared rocks, contribution split, bystander/ineligible handling and per-player completion are covered by tests; no second client could be launched |
| Real-person difficulty | NOT VERIFIED | the Studio client bot is not a good player (it spent most of its time dodging and dealt about 350 damage to the guardian in 45 s); the simulation bot with the same rules wins 8/8 in about 130 s |

**Visual polish pass (rigged creatures).** All ten new segmented AI rigs generated and were exported to `Config/CreatureRigs.luau` (ids checked against the
generation record by `tests/wiring.spec`; now 300 tests). In Studio: the builder produced all ten as rigged models without warnings; a rigged Slag Brute
was fought and defeated by the client bot (minHp 63, 7 Charged Smashes, 16 telegraphs) with no errors in the output log; Grom's joints were measured per state
(windup fists to 16.1 studs and body rearing back, strike swings forward and down, stagger leans back, defeat slumps) and the hound's parts confirmed
head-forward, tail-behind. Not verified: screenshots of the final poses (the capture tool stopped responding), so colour and silhouette of the later rigs
were only seen laid out in Edit mode.

Fight simulation and economy numbers are in CREATURES.md. One unexplained observation: in the very first guardian run the boss lost
~25k health in a few seconds with its armor flagged open although no skill had been sent; three later runs (one with trace logging)
behaved correctly and the armor rules are covered by the creature unit and integration tests, so it is recorded as a known issue rather than a fixed bug.

## Hardening sprint: findings and how each was verified

| Finding | Fix | Regression tests | Studio (single client, observed) |
|---|---|---|---|
| Whiffed punches built combo / Overclock stacks | the swing only previews the chain (`Combat.peekStrike`); `registerStrike` runs when the strike lands (valid target, alive, in reach, same arm); equipping resets the whole chain | `combat.spec` (3), `server_combat.spec` (5 failed before the fix) | five punches at nothing with Alloy: combo 0, overclock 0; three real punches at a rock: combo 3, overclock 3 |
| A respawning rock could land on a player | `RespawnGuard`: the respawn is held back (re-checked every second) while a character stands in the new footprint or within 3 studs of it; after 20 s it returns as a non-solid ghost and turns solid once clear; nobody is moved or damaged | `respawn.spec`, `server_rocks.spec` (6 failed before the fix) | stood in the footprint of a killed Granite: no model for 12 s, ghost (collider off) at 32 s, horizontal drift 0.000 studs, health unchanged; after walking away the collider turned solid within 2 s |
| `RockService` scanned every rock / player per call | `SpatialGrid` over rock bases for `near()`; the burn loop visits only burning rocks; `fxNear` kept as one allocation-free pass | `spatial.spec`, `server_rocks.spec` (equivalence with brute force) | `ArmforgeDev bench`, 160 rocks, 1 player: `near` 9.5 us -> 1.4 us per call; the player scan (0.5 us) was already negligible and is unchanged |
| Server glue untested | `tests/support/ServerWorld.luau` harness + 5 specs (above) | 70 tests | n/a |

Persistence audit results (all with tests; first five failed before the fix):

* a save now only commits while the record still carries this server's lock (fencing): a stale server whose lock was taken over can
  no longer overwrite the new owner's data even after the new owner released the lock; it stops writing and removes the player;
* a record that is not a table, or was written by a NEWER schema, is refused ("corrupt" / "newer_schema") and left untouched instead of
  being reconciled to defaults and saved back;
* a player who left while the load was in flight (including the window where PlayerRemoving already ran but the player is still
  parented) now releases the lock without rewriting their data (`Persistence.release`, retried);
* a leaving session can only save with release; a late autosave can no longer re-take a released lock;
* `BindToClose` also waits for leave-saves that were already running when shutdown began;
* the Studio startup probe is a read (`GetAsync`), not a write; live servers do no DataStore traffic at boot;
* Studio-only failure injection lets the failure paths be exercised against the real store (see `PERSISTENCE_TEST.md`).

Studio checks repeated after the changes (same session as above): five consecutive equips (Magma, Crystal, Starter, Alloy) left exactly
one `ArmforgeArms` set with the right `ArmId`; one Granite kill paid 13 coins and counted one destroyed rock; a Granite killed with the
player standing 6 studs away (inside the 7.2-stud clearance ring) was still only rubble 10 s later, i.e. the respawn was held back;
the Output log contained no errors or warnings other than the expected "DataStore unavailable in Studio" notice.

## NOT verified / blocked

* **Real persistence.** Studio reports "You must publish this place to the web to access DataStore", so `DataService` ran on its
  in-memory fallback. The load/save/lock/retry/migration/reconcile logic is tested against a fake store (including latency, outages and
  racing saves), but the live DataStore path (`UpdateAsync` against Roblox) has not been exercised. Publishing needs the owner's
  account and was not done (nothing was published). Run `docs/PERSISTENCE_TEST.md` against a PRIVATE test experience.
* **Multiplayer.** The Studio MCP server only offers single-client start/stop (no "Clients and Servers" launcher), so a real
  second client could still not be launched. Contention, concurrent contributors, per-player effect delivery and snapshot isolation are
  verified server-side against the fake server and with simulated contributors in Studio; replication of arm sets, swings, debris and rock state to other real clients,
  latency effects on the strike timeline, and the booster/rate-limit behaviour under real network jitter are unverified.
* **Real devices.** Only Studio's device emulator was used. Phone frame rate, memory and touch ergonomics are unmeasured; gamepad
  navigation of the custom UI is untested.
* **Avatars.** R15 only (the arm system needs the R15 joints). R6 players would keep their own arms and skip the animation layer.
* Teleport-style exploits move the character client-side, so the proximity checks for travel/rebirth/training (HRP distance) are
  weaker than the data checks; they cannot grant anything the data rules forbid, but a hardening pass is listed in NEXT.md.

## Fishing, The Atlantic Sea, swing vines, The Canopy Grove

Automated (`tests/fishing.spec`, 16 tests, 356 total passing, strict typecheck clean under both solvers): the pure rules (bite window bounds, early /
in-window / late reels, the weighted catch table and a 10% sail rate over 40,000 seeded rolls, a 2% vine fling over 50,000), the zone config (the
+25% boost, zones stay out of the island ladder, every zone rock and creature exists and is placed on land), the server flow on the fake
server with a stubbed roll (a catch pays, a lucky catch moves you to the atoll, a zone rock pays 1.25x the same rock elsewhere, early / missed /
cooldown / too far), vine swings (rate limit, reach, fling to the grove), the gift (only inside the grove, once per cooldown) and dev `goto` /
`home`. Fight balance (`encounter_balance.spec`): Reef Scuttler 15 s, Tide Brute 20 s, Pearl Leviathan 51 s.

Studio (real play, scripted through the dev bridge): the dock prompt part and 12 vines exist; a cast then a reel paid a catch; a lucky cast and reel
put the player on The Atlantic Sea at its arrival point with the HUD line "THE ATLANTIC SEA +25% coins & XP"; 16 zone rocks spawned; a vine swing
did nothing at a normal roll and flung the player to the grove on a lucky one; the grove gift paid and then reported its cooldown; the console
showed no errors. Screenshots looked right (atoll, lighthouse, palms, coral; the grove with its trees, chest and "Rope down" sign).

Not verified: pressing the real ProximityPrompts by hand (the dock, vine, chest, rope and lighthouse prompts were exercised through the same
service functions), the fish card and the sail banner on a real client, the swing vine's tween on a real model, a second client, fighting the
Atlantic creatures by a human, and how the atoll looks at dusk or on a phone.

## Arm signature moves, new animations and effects

Automated (`tests/signatures.spec`, 23 tests, 379 total passing, strict typecheck clean under both solvers): every arm has a signature with a real
animation, a sane cooldown and its own visual style; every strike and burst time sits on a key pose of its animation (within 0.03 of the move);
worth stays between 1.6x and 6.5x power; Endurance shortens the cooldown; every joint in every pose is one the animator drives; mirrored moves swap
hips as well as arms; combo chains keep the trait rhythms (Fists 3, Void ending on its Rend). Server flow on the fake server: each arm's signature
damages the rock it is aimed at and goes on cooldown, a target-less press spends nothing, the cooldown holds per arm (swapping never skips it),
garbage input is ignored, Quake Stomp batters the surroundings without a target, Prism Lance refracts into neighbours but not twice into its target,
Eruption ignites, Piston Storm leaves Overclock at 5, swapping arms mid-move cancels the rest, creatures take signature strikes, and the Fx payload
carries what the client needs. `resetcd` (developer mode) clears the cooldowns.

Studio (real play, scripted): Q on a rock fired the Magma signature through the real input path (cooldown counter ran on the slot, the rock broke
and released its creatures); key poses of Quake Stomp (knee lift), Uppercut, Eruption (leap, fists overhead), Rift Tear (arms torn wide) were held
with the pose tool and screenshotted; every new Fx kind (all six signatures and their bursts, the four skills, Shatter Wave, creature strike in
all three shapes, defeat, reveal and a Magma creature hit) was fired at the client with no warnings in the console; Eruption's fire pillar, Void's
rift orb and Crystal's refracted rays were seen on screen.

Not verified: the effects at full speed in a real fight (screenshots catch single frames), how they read on a phone or with reduce-effects on,
the three jab-style signatures (Barrage, Storm) and Quake's cracks by eye, the swing arcs of every move, the new combo moves in motion (only key poses
were checked), and the gamepad Y binding. The left-hand mirrors of the new moves and the leg joints were checked in data, not by eye.
