# Persistence test procedure (real DataStore, private test experience)

Status: **not yet run against the real Roblox DataStore.** Everything in the "Simulated" column below is automated and passing;
everything in the "Real" column needs a person with a Roblox account to run this checklist once. Do not treat the game as
persistence-verified until the checklist at the bottom is filled in.

## What is simulated vs what needs the real service

| Behaviour | Simulated (Lune, `tests/server_persistence.spec`, `tests/persistence.spec`) | Real DataStore (this document) |
|---|---|---|
| Load, save, release lock, rejoin gets the same progression | yes (fake store with latency) | step 6 |
| Failed load kicks the player and never writes defaults | yes (`failAll`) | step 7 (via `failStore`) |
| Profile locked by another live server blocks the load and is not modified | yes | step 8 |
| Stale lock is taken over; the old server cannot overwrite | yes (two worlds sharing one store) | step 8 (edit the record's `lock` by hand) |
| Leave during load, autosave racing a leave, shutdown with a leave-save in flight | yes (virtual clock, exact interleavings) | steps 6 and 9 (timing only, cannot be forced) |
| Save retries and failure reporting | yes | step 7 |
| Corrupt record / record from a newer schema is refused | yes | not needed (hand-edit if curious) |
| Real `UpdateAsync` semantics, request budgets/throttling, latency, `BindToClose` grace period, Studio vs live servers | **no** | steps 1 to 9 |

The fake store follows the `UpdateAsync` contract (transform runs atomically at commit time, returning `nil` cancels). It cannot
prove that Roblox behaves that way under load, which is what this checklist is for.

## Safety rules (read first)

* **Use a separate, PRIVATE test experience.** DataStores are scoped to an experience (universe). A copy of the place published as a
  new private experience has its own, empty DataStores, so nothing here can touch production data. Never run this against the
  production experience, and never publish a test build over it.
* Studio playtests write to `ARMFORGE_PlayerData_Studio` (scope `v1`); a live server of the same experience writes to
  `ARMFORGE_PlayerData`. The two names never overlap, so a Studio session cannot modify live player data even inside the same
  experience. `DataService.init` logs the store name it opened.
* Production servers never write at boot. The only startup call in Studio is a **read** of the key `__probe`.
* Failure injection (`failStore` and the `ArmforgeFailStore` workspace attribute) is Studio-only: it does nothing when
  `RunService:IsStudio()` is false (covered by tests).
* Use throw-away accounts or accept that your own test profile is overwritten; delete the test keys when you are done.
* Nothing in this procedure requires making the experience public. Do not toggle it public.

## Prerequisites

1. A clean `rojo build default.project.json --output build/ARMFORGE.rbxlx`, or `rojo serve` with the Rojo Studio plugin. Open it in
   Roblox Studio.
2. **File > Publish to Roblox As...** and create a **new** experience (name it e.g. "ARMFORGE persistence test"). Leave it
   **Private** (Creator Hub > the experience > Settings > Privacy). Studio cannot reach DataStores until the place is published.
3. **Home > Game Settings > Security > Enable Studio Access to API Services** (only for this test experience).
4. Start a playtest. In the Output window you must see `[ARMFORGE] DataStore ready (ARMFORGE_PlayerData_Studio/v1)`. If you see
   `Using IN-MEMORY storage` instead, API access is still off or the place is not published; fix that before continuing, because
   nothing below would be testing the real store.
5. To read a stored record: Creator Hub > the test experience > **Data Stores** (Data Stores Manager) > store
   `ARMFORGE_PlayerData_Studio` (or `ARMFORGE_PlayerData` for live servers) > key `Player_<your UserId>`. A record looks like
   `{ data = {...}, lock = { jobId, time }, savedAt, schema }`. `lock` is absent when the profile was released cleanly.

The dev bridge works from the Studio command bar or `scripts/dev.py` (server context):

```lua
local D = game.ServerStorage.ArmforgeDev
D:Invoke("state")             -- JSON of the live profile
D:Invoke("coins", 500)        -- grant, see scripts/dev.py for the full list
D:Invoke("failStore", 1000)   -- the next 1000 DataStore operations fail (0 to clear); for load drills use the attribute, step 7
```

## Checklist

Record the result of each step in the table at the end. A step passes only if the Output window shows no `[ARMFORGE] save failed`
or script errors that the step did not intentionally cause.

1. **Real store in use.** Prerequisite 4 above. Expected: `DataStore ready`, store name ends with `_Studio`.
2. **Load a new profile.** Play with an account that has no key yet. `state` shows default data (Starter arm, level 1). In the Data
   Stores Manager the key `Player_<id>` now exists with `lock.jobId = "studio"`.
3. **Earn currency and XP.** Destroy a rock with real punches (or `coins`/`xp`). `state` shows the new coins and XP.
4. **Equip and upgrade an arm.** `giveArm Alloy`, equip it through the Armory UI, upgrade it once through the UI. Note the arm level
   and the coin balance.
5. **Unlock progression.** Reach level 12 (`level 12`), `rebirths 1`, defeat the Forgeheart guardian (break the Anvil Seal; for a
   shortcut `D:Invoke("hitCreature", <seal id>, 1e9)` after it emerges), unlock Crystalfall at the Skyport, train a stat at a
   station, learn a skill. Note level, unlocked islands, **guardian victories and island completion** (`D:Invoke("guardians")`),
   training levels, skill ranks.
6. **Save, leave, rejoin, same progression.**
   1. Wait for the autosave (75 s) and watch `lastSave` change in the record, or just leave.
   2. Stop the playtest (this exercises `BindToClose`). The record's `data` must hold everything from steps 3 to 5 and `lock` must be
      gone.
   3. Start a new playtest. `state` must show identical coins, level, owned arms and arm levels, equipped arm, unlocked islands,
      `guardians.defeated` and `islands.completed`, training and skill ranks. Repeat leaving through the in-game menu / Leave button instead of stopping the server.
7. **Failed load never overwrites a valid profile.**
   1. Stop play and copy the stored record's JSON (including `savedAt`).
   2. In Edit mode run `workspace:SetAttribute("ArmforgeFailStore", 1000)` in the command bar (Studio only; live servers ignore it),
      then press Play. The next 1000 DataStore operations fail.
   3. Expected: after about 30 s of retries you are kicked with "ARMFORGE could not load your save data safely", Output shows
      `could not load data`, and the stored record is byte-for-byte what you copied (same `savedAt`).
   4. Stop play, run `workspace:SetAttribute("ArmforgeFailStore", nil)`, press Play: your progression is intact. (The attribute is
      saved with the place if you save it, so clear it.) During a session, `D:Invoke("failStore", n)` makes later operations such as
      the autosave fail: Output shows `save failed ... error: injected DataStore failure` and the next autosave after `failStore 0`
      succeeds.
8. **Session lock.**
   1. Stop play. In the Data Stores Manager edit the record: add `"lock": { "jobId": "someone-else", "time": <current unix time> }`.
   2. Play: expected `could not load data ... locked` after about 5 attempts, you are kicked, and the record is unchanged.
   3. Edit `lock.time` to an hour ago (stale). Play: the load succeeds (takes over), and the record now shows `jobId = "studio"`.
   4. Optional, needs two machines or two Studio sessions on different jobs: while one session is playing, edit the record's lock
      to another jobId and watch the playing session kick you at the next autosave ("Your save session moved to another server")
      without writing.
9. **Shutdown and leave saves, concurrency.**
   1. Join, earn coins, and leave through the menu while an autosave is due (within a few seconds of the 75 s tick). Expected: no
      lock left in the record, latest coins saved.
   2. Stop the playtest while a second client is also leaving (Studio Test > Clients and Servers, 2 players, then close one client
      and stop the server). Expected: both records released with the latest data.
   3. Optional: on the live (non-Studio) path, play the test experience from the Roblox client (Creator Hub > Play), earn coins, then
      use the experience's **Servers** tab to shut the server down. Store `ARMFORGE_PlayerData`, key `Player_<id>`: data saved, lock
      cleared.

Throttling check (optional): with 8 or more test accounts joining within a minute, confirm no `save failed` warnings; the
autosave interval and retry backoff are in `Game.Data`.

## Results

| Step | Date | Result | Notes |
|---|---|---|---|
| 1 Real store in use | | not run | |
| 2 New profile | | not run | |
| 3 Currency / XP | | not run | |
| 4 Equip + upgrade | | not run | |
| 5 Progression | | not run | |
| 6 Save / leave / rejoin | | not run | |
| 7 Failed load | | not run | |
| 8 Session lock | | not run | |
| 9 Shutdown / leave concurrency | | not run | |

## Cleanup

Delete the test keys in the Data Stores Manager (or leave them; they are in the private experience only). If the test experience
is no longer needed, archive it from Creator Hub. Turn **Studio Access to API Services** back off if you only enabled it for this
test place.
