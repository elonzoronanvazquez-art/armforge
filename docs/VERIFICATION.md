# Verification report

What is actually verified, where, and what is not. "Studio" below means a single-client playtest of the Rojo-built place in
Roblox Studio driven through the Studio MCP server (execute_luau on Server/Client, real mouse and keyboard input, screenshots,
console output). Nothing is claimed that was not observed.

## Automated (Lune, `lune run tests/run`): 119 tests, 0 failing

| Spec | Tests | Covers |
|---|---|---|
| `config.spec` | 11 | roster (>= 6 distinct arms with distinct traits/styles/cooldowns), rock and island integrity, skills/boosters/training references, animation contact frames and keyframe ordering |
| `rocks.spec` | 17 | geometry determinism and layers; the first hit strips material; INTACT -> SURFACE -> CHIPPED -> FRACTURED -> COLLAPSE; monotonic chunk removal; localised chipping; mid layer only after its cover; kill exactly once; invalid/NaN damage; overkill cap; payout once, shares, shards; respawn; two-player contention |
| `combat.spec` | 22 | stats derivation, training/rebirth/booster bonuses, speed and crit caps, combos, traits (Finisher, QuarryMaster, Singularity, Resonance, Meltdown, Overclock), resistance/pierce, skills (learn, cooldown, Overdrive then Overheat), pose math and contact timing for every arm |
| `economy.spec` | 25 | one-equipped-arm invariant, buying gates and exact charges, upgrade pricing, cosmetics vs stats, schema defaults/reconcile of hostile data, migrations, training grading and caps, persistence (session lock, stale lock, lost lock, retries, corrupt data), rate limiter, 1,000-punch spam |
| `progression.spec` | 20 | XP curve, multi-level gains, max level, rebirth eligibility, **exact reset/preserve rules** and data-driven toggles, island prerequisites (never coins alone), booster durations/extension/caps/non-multiplication, tutorial order |
| `balance.spec` | 5 | greedy-player simulation: first upgrade <= 40s, Stonebreaker 2-15 min, Alloy <= 50 min, level 12 8-75 min, rebirth level not trivial, no dead arms, each arm tier faster than the last |
| `wiring.spec` | 13 | every remote/effect kind/notification/request action/panel/sound key used in code exists on the other side; mesh ids are real; every arm has a design with pieces at every upgrade tier; all files `--!strict`; dev tooling gated to Studio and untouched elsewhere |
| `util.spec` | 6 | untrusted-argument validation, formatting, signals |

Balance milestones printed by the simulation (optimal play): first upgrade 18s, level 2 32s, level 5 2.8min, Stonebreaker 5.5min,
level 12 24min, Alloy 30min, level 25 48min, level 30 58min. A real player will be slower.

**Typecheck:** `scripts/typecheck.ps1` (luau-lsp, `--!strict`, Roblox definitions): 0 errors, 0 warnings with the old solver and
with `LuauSolverV2=true`. **Build:** `rojo build default.project.json` succeeds; the built place contains every script and opens and
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

## NOT verified / blocked

* **Real persistence.** Studio reports "You must publish this place to the web to access DataStore", so `DataService` ran on its
  in-memory fallback. The load/save/lock/retry/migration/reconcile logic is unit tested against a fake store, but the live
  DataStore path (`UpdateAsync` against Roblox) has not been exercised. Verify after publishing to a TEST place with API access on.
* **Multiplayer.** No second client could be launched through the available tooling. Contention is verified server-side
  (simulated contributors) and in unit tests; replication of arm sets, swings, debris and rock state to other real clients,
  latency effects on the strike timeline, and the booster/rate-limit behaviour under real network jitter are unverified.
* **Real devices.** Only Studio's device emulator was used. Phone frame rate, memory and touch ergonomics are unmeasured; gamepad
  navigation of the custom UI is untested.
* **Avatars.** R15 only (the arm system needs the R15 joints). R6 players would keep their own arms and skip the animation layer.
* Teleport-style exploits move the character client-side, so the proximity checks for travel/rebirth/training (HRP distance) are
  weaker than the data checks; they cannot grant anything the data rules forbid, but a hardening pass is listed in NEXT.md.
