# Developer mode

An in-game test kit so you can reach any part of ARMFORGE without grinding: coins, XP, levels, rebirths, every island, every arm,
skills, boosters, teleports, god mode, more damage, more speed, Summit Momentum and a profile reset.

## Who can use it

| Where | Who |
|---|---|
| Roblox Studio (Play / Play Solo / local server) | every player in the session |
| A live server | the UserIds in `Config/Game.Dev.allowedUserIds`, plus the place's creator (a user-owned place) or owner (rank 255 of a group-owned place) while `Config/Game.Dev.allowCreatorInLive` is `true` |
| Anyone else | nobody: the server refuses every command, never shows the DEV button, and the snapshot never says developer mode exists |

To give a tester access in a published place, add their UserId:

```lua
Game.Dev = {
	allowedUserIds = { 123456789 },
	allowCreatorInLive = true, -- set to false before a public launch if even the owner should not have it
	...
}
```

The check lives in `Logic/DevAccess` (pure, tested) and is applied by `Services/DevAccess`; `Services/DevMode` re-checks it on **every**
command, so a modified client cannot use it.

## How to use it

* Press the backtick key (`` ` ``) or click the red **DEV** button (top right) to open the **Developer Mode** window.
* Type a command in the box and press Enter / **RUN**, or press a button. The buttons are just commands: the box and the buttons do
  exactly the same thing. `help` lists every command. The window shows what the server answered (green OK, red NO).
* The commands change your **real profile**. In Studio that profile is in memory (the DataStore is unavailable), so nothing persists; in a
  live server it is saved like any other progress, so use `reset confirm` to start over.

## Commands

Numbers accept `1000`, `1e6`, `-500`. Anything out of range is refused with a usage message and changes nothing.

| Command | What it does |
|---|---|
| `coins <n>` / `setcoins <n>` | add (negative removes) / set coins (capped at 9e15) |
| `shards <n>` | add Forge Shards |
| `xp <n>` | add XP through the real level-up rules (skill points, level coins, milestone boosters) |
| `level <1-40>` | set the level exactly (up uses the real rules, down just lowers it) |
| `rebirths <0-25>` | set the rebirth count |
| `unlockislands` | open every playable island (never a coming-soon one) |
| `completeguardians` | mark every island guardian defeated |
| `unlockarms` / `maxarms` | own every arm / own and fully upgrade every arm |
| `equip <arm>` | wear an owned arm (`equip void`) |
| `skills` | every skill at max rank |
| `boosters [n]` | n of every booster (default 3) |
| `unlockall` | islands + arms |
| `kit` | level 40, 1B coins, 500 shards, 6 rebirths, every island, every arm maxed and the strongest worn, every skill, boosters |
| `goto <island or zone>` | teleport to an island's arrival point and open it (`goto Dustwake`), or to a zone (`goto AtlanticSea`, `goto CanopyGrove`); any capitalisation |
| `home` | leave a zone: back to the jungle from the grove, to your current island from the Atlantic Sea |
| `seal [island]` | teleport next to an island's guardian seal (default: the current island) |
| `god [on/off]` | creatures cannot hurt you |
| `power <n>` | multiply the damage you deal to rocks and creatures (1 = normal) |
| `speed <n>` | walk speed 8 to 250 (`speed 0` = normal) |
| `heal` | restore health |
| `resetcd` | clear every skill and signature cooldown |
| `momentum` | grant Frostpeak's Summit Momentum without climbing |
| `reset confirm` | wipe your progress to a brand new player (needs the word `confirm`; the panel asks for two clicks) |

## Typical test sessions

* **Late content**: `kit`, then `goto Dustwake` (or press the island buttons), `power 1000000` to break rocks instantly, `god` to survive.
* **A specific guardian**: `rebirths N` for its gate, `unlockislands`, `seal <island>`, punch the seal.
* **The ladder from scratch**: `reset confirm`, then `level 12`, `rebirths 1`, `completeguardians` one step at a time, or use the real gates.
* **Mountain mechanics**: `goto Crystalfall` then climb or ride the tram, or `momentum` to see the boost.

## What it does not change

It never touches other players, the world, the DataStore directly, or the rules the game enforces for everyone else: `power`, `god` and `speed`
are per-player flags on the server session and disappear when you leave. The older Studio-only bridge (`server/Dev/DevTools`, used by the
scripts in `scripts/`) is separate and still only exists in Studio.

## Tests

`tests/devmode.spec` covers the access rule for every case, command parsing, each data command and its refusals (bad numbers, caps, no change
on failure), the kit producing a profile that survives a save and reload, an unauthorized player getting nothing however the request is
phrased, hostile payloads, the Studio and listed-UserId paths, `goto`, `power`, `god`, `equip`, `reset` and `momentum` on the fake server.
