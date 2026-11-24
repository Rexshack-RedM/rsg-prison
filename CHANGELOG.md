# Changelog

All notable changes to rsg-prison. Newest first.

## 3.5.0

### Features
- **Bail**: prisoners can pay for early release at the guard (`Config.Bail`, price per remaining minute, two-step confirm, charged to the bank by default).
- **Collect Property**: the guard hands back belongings that didn't fit on release (`Config.CollectProperty`).
- **Prison labour**: break rocks at configurable work sites to take time off the sentence (`Config.Labour`). Server-side ticket, timing, distance, cooldown and a maximum reduction.
- **Contraband searches**: `/searchprisoner` for on-duty lawmen seizes disallowed items and adds time (`Config.Contraband`).
- New Discord log categories `bail`, `labour` and `contraband`.
- 29 new locale keys in all 12 languages.
- Server-side hooks `rsg-prison:server:sentenceStarted` / `rsg-prison:server:sentenceEnded` for other resources.
- Labour progress (`jailtotal`, `jailreduced`) is saved in metadata, so reconnecting can't reset the reduction cap.
- `DOCS.md` rewritten as a full technical reference (flow, metadata, every option, events, callbacks, commands, exports, examples, security model, troubleshooting).

## 3.4.0

### Security
- The server now starts every sentence itself. Previously belongings were only seized, jobs removed and the countdown started when the prisoner's own client fired `rsg-prison:server:startSentence`, so a client that skipped it kept everything and never served time. Any player with `injail > 0` that the server isn't tracking is picked up on the next 10 second tick (this also covers jailing by metadata only).
- Server-side zone check: a prisoner found outside `Config.PrisonZone` is told to return, and moved by the server if the client ignores it. The old check only ran in the client and only after the player had been seen inside.
- `startSentence` is idempotent: repeat calls change nothing and no longer spam the Discord `jail` log. Suspicious ration requests are logged at most once per player every 10 seconds.
- Ration requests are rejected when the configured item doesn't exist; a missing item is also reported at start.

### Fixes
- Belongings that didn't fit on release are kept in their own `jailowed` metadata. Before, they were stored as an active seizure, so the retry on the next login ran `ClearInventory` and wiped everything the player was carrying, and a new jailing before that retry skipped the seizure.
- Outlaw status is reset on every release, including prisoners who had an empty inventory.
- Rejoining or restarting the resource while jailed no longer teleports a prisoner who is already inside the walls to a random cell.
- Removed the duplicate item box on rations (rsg-inventory already shows it).

### Changes
- The guard's water / bread options only show for prisoners. The client wrapper event `rsg-prison:client:requestRation` is gone; the targets call the server event directly.
- The zone and ped-swap watchers only run while jailed (they used to run for every player all the time). The poly check moved to `shared/zone.lua`.
- Prison clothing moved to `Config.Clothing`. `Config.MenuLocations[].coords` was removed (the guard's `npccoords` is used for the blip and the distance check).
- Removed unused locale keys `cl_prison_menu`, `cl_request_water_desc`, `cl_request_bread_desc` from all languages.

## 3.3.1
- Fix: jailing now removes every job through rsg-core's built-in multi-job exports (`GetPlayerJobs` / `RemovePlayerJob`). The old `rsg-multijob` state check never matched, so only the active job was cleared.

## 3.3.0

### Documentation
- `DOCS.md`: added a generated technical reference (dependencies, database, configuration, exports, callbacks, events, commands, items, locales) with code examples, read straight from the source.
