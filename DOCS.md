# rsg-prison – Developer Docs (3.5.0)

Technical reference for server owners and developers. For a player-facing overview see `README.md`.

## Contents
1. [Overview](#overview)
2. [Files](#files)
3. [Dependencies](#dependencies)
4. [How a sentence works](#how-a-sentence-works)
5. [Player metadata](#player-metadata)
6. [Configuration](#configuration)
7. [Events](#events)
8. [Callbacks](#callbacks)
9. [Commands](#commands)
10. [Exports](#exports)
11. [Integration examples](#integration-examples)
12. [Discord logging](#discord-logging)
13. [NUI (countdown HUD)](#nui-countdown-hud)
14. [Security model](#security-model)
15. [Persistence and database](#persistence-and-database)
16. [Server owner how-tos](#server-owner-how-tos)
17. [Troubleshooting](#troubleshooting)

---

## Overview
rsg-prison runs the Sisika prison for the RSG Framework. A player is jailed by setting their `injail` metadata (minutes) on the server. From then on the **server** owns the sentence: it seizes belongings, removes jobs, counts the time down, keeps the prisoner inside the walls and releases them. The client only teleports, dresses the player, shows the HUD and plays animations.

Guard services: water and bread rations, bail, collecting leftover property. Prisoners can shorten their sentence with prison labour. Lawmen can search prisoners for contraband.

## Files
| File | Side | Purpose |
|---|---|---|
| `fxmanifest.lua` | – | Resource manifest (version, load order, dependencies) |
| `config.lua` | shared | All gameplay options |
| `shared/zone.lua` | shared | `PrisonZoneContains(pos)` point-in-polygon test used by the client and the server |
| `server/server.lua` | server | Sentence tick, seizure and return of belongings, jobs, rations, bail, labour, contraband, escape enforcement |
| `server/discord.lua` | server | Discord webhook queue, `PrisonLog` and the `DiscordLog` export |
| `server/config_discord.lua` | server | Webhooks, colours and identifiers shown in logs (never sent to clients) |
| `server/versionchecker.lua` | server | GitHub version check on start |
| `client/client.lua` | client | Enter / release flow, prison clothing, HUD, zone watcher, weapon unequip / re-equip |
| `client/npcs.lua` | client | Guard NPC streaming and its rsg-target options |
| `client/labour.lua` | client | Work site targets and the work animation |
| `html/` | NUI | Countdown HUD (`index.html`, `style.css`, `script.js`) |
| `locales/*.json` | shared | `en`, `de`, `el`, `es`, `fr`, `it`, `ja`, `nl`, `pl`, `pt-br`, `ro`, `ru` |

Load order matters: `config.lua` then `shared/zone.lua`; `client/client.lua` defines the global `PrisonIsPrisoner()` used by `npcs.lua` and `labour.lua`.

## Dependencies
`rsg-core`, `rsg-inventory`, `rsg-character`, `rsg-target`, `oxmysql`. Optional: `rsg-weapons` (weapon re-equip), `rsg-medic` (outfit re-applied after a revive), `rsg-telegram` (prison post office). No `ox_lib`.

## How a sentence works
```
injail > 0 set on the server (rsg-lawman, rsg-mdt, rsg-bountyhunter, admin, your script)
   │
   ├─ client: rsg-prison:client:Enter  ──► rsg-prison:server:startSentence
   └─ server tick (every 10 s) picks up any player with injail > 0 it isn't tracking yet
        │
        ▼
 startSentence (idempotent)
   ├─ fresh sentence: snapshot equipped weapons, seize every item (jailitems), jailseized = true,
   │   disarm client, remove all jobs (Config.RemoveJob), pay Config.JailAllowance
   └─ resume (reconnect / resource restart): jailseized already true, re-remove jobs, restore labour progress
        │
        ▼
 every 10 s: remaining = ceil(secondsLeft / 60) saved to injail when the minute changes,
             HUD synced, server zone check (Config.ReturnOnEscape)
        │
        ▼  secondsLeft <= 0, injail set to 0 elsewhere (/unjail), or bail paid
 release: injail = 0, ClearInventory, belongings returned (original slot first), leftovers → jailowed,
          outlaw status reset, weapons re-equipped, client: rsg-prison:client:freedom
```
Notes:
- The saved `injail` value is rounded **up** so it can never reach `0` before the server releases the player.
- If another script changes `injail` while the player is serving (extended, reduced), the server adopts the new value on the next tick.
- Belongings that do not fit on release are kept in `jailowed` and handed back by the guard ("Collect Property") or on the next login. This retry never clears the inventory.

## Player metadata
Stored in the player's rsg-core metadata (saved with the character). Only the server can write these keys.

| Key | Type | Meaning |
|---|---|---|
| `injail` | number | Minutes left. `> 0` jails, `0` releases. Set it server-side. |
| `jailseized` | boolean | `true` while belongings are held (an empty inventory still counts) |
| `jailitems` | table | Seized belongings: `{ { name, amount, info, slot }, ... }` |
| `jailowed` | table | Belongings that did not fit on release, same format as `jailitems` |
| `jailequipped` | table | `{ weapons = { serial... }, knives = { name... } }` equipped on entry, re-equipped on release |
| `jailtotal` | number | Original sentence length in seconds (labour cap and HUD bar; grows with contraband time) |
| `jailreduced` | number | Seconds already removed by prison labour |

Sentences started before 3.4.0 are recognised by a non-empty `jailitems`.

## Configuration
Everything is in `config.lua` unless noted.

### General
| Option | Default | Description |
|---|---|---|
| `Config.RemoveJob` | `true` | Remove **all** jobs (rsg-core multi-job) on jailing; the player must be re-hired |
| `Config.JailAllowance` | `0` | Cash given on entry (`0` = none). Wiped with the rest of the inventory on release |
| `Config.DistanceSpawn` | `20.0` | Distance at which the guard NPC streams in |
| `Config.FadeIn` | `true` | Fade the guard in / out |
| `Config.ReturnOnEscape` | `true` | Return prisoners who leave the zone (client check + server-side backstop) |
| `Config.CollectProperty` | `true` | The guard hands back belongings that did not fit on release |

### Guard rations
```lua
Config.GuardRations = {
    max      = 5,    -- max of each item a prisoner can hold
    cooldown = 10,   -- seconds between requests
    distance = 5.0,  -- max server-side distance from the guard (also used by bail and collect)
    items = { water = 'water', bread = 'bread' }, -- request name -> inventory item
}
```
The item names must exist in `RSGCore.Shared.Items`; a missing item is reported in the console at start.

### Bail
```lua
Config.Bail = {
    enabled        = true,
    account        = 'bank', -- cash is seized on entry, so bank is the useful account
    pricePerMinute = 2,
    minimum        = 5,
    confirmSeconds = 15,     -- ask the guard again within this time to pay the quoted price
}
```
Price = `max(minimum, ceil(minutesLeft) * pricePerMinute)`. If the sentence grows between the quote and the payment, a new quote is given.

### Prison labour
```lua
Config.Labour = {
    enabled = true, duration = 30000, cooldown = 60, minutesOff = 1, maxReduction = 50, distance = 2.5,
    scenario = 'WORLD_HUMAN_FARMER_WEEDING',
    sites = { { coords = vector3(3349.62, -650.41, 45.38), radius = 1.5 } },
}
```
| Option | Description |
|---|---|
| `duration` | Milliseconds per work cycle (the progress bar) |
| `cooldown` | Seconds before the next cycle can start |
| `minutesOff` | Minutes removed per finished cycle |
| `maxReduction` | Percentage of the original sentence (`jailtotal`) labour may remove in total |
| `distance` | Extra server-side distance allowed around a site's `radius` |
| `scenario` | Animation scenario played while working |
| `sites` | Work spots (rsg-target sphere zones); keep them inside `Config.PrisonZone` |

### Contraband
```lua
Config.Contraband = {
    enabled = true, distance = 3.0, allowed = { 'dollar', 'cent' },
    minutesPerItem = 2, maxExtraMinutes = 15, cooldown = 60,
}
```
`allowed` is added to the guard ration items. Cash is items on this server, so keep `dollar` / `cent` allowed if you use `JailAllowance`.

### Locations, blip, zone, clothing
| Option | Description |
|---|---|
| `Config.Locations.outside` | `vector4` release point |
| `Config.Locations.escape` | `vector4` where escapees are returned |
| `Config.Locations.spawns` | List of `vector4` cell spawn points (one chosen at random) |
| `Config.MenuLocations` | List of guards: `npcmodel`, `npccoords` (`vector4`), `showblip`. `npccoords` is also used for the blip and every distance check |
| `Config.Blip` | `blipSprite` (name), `blipScale` |
| `Config.PrisonZone` | `points` (list of `vec3`, polygon) and `thickness` (total height band centred on the first point's z) |
| `Config.Clothing` | `remove` (shop category hashes stripped on entry), `male` / `female` (outfit items applied) |

### Discord (`server/config_discord.lua`)
See [Discord logging](#discord-logging).

## Events
Server events can be fired by any client, so every handler re-validates the player, arguments, position and cooldown on the server.

### Server events (from clients)
| Event | Arguments | Notes |
|---|---|---|
| `rsg-prison:server:startSentence` | – | Idempotent. Reads `injail` from metadata; the client cannot choose the time |
| `rsg-prison:server:checkRelease` | – | Ignored while `injail > 0`. Returns belongings after an offline / early release and retries `jailowed` |
| `rsg-prison:server:escapeAttempt` | – | Only logs (30 s cooldown per player); the zone is also checked by the server |
| `rsg-prison:server:requestRation` | `kind` (`'water'` or `'bread'`) | Jailed, near the guard, cooldown, max held, inventory space |
| `rsg-prison:server:requestBail` | – | First call quotes, second call within `confirmSeconds` pays and releases |
| `rsg-prison:server:collectProperty` | – | Not jailed, near the guard, only when `jailowed` is not empty |
| `rsg-prison:server:labourFinish` | – | Needs a ticket from the `labourStart` callback; checks elapsed time, distance, cooldown and the cap |

### Server-side hooks (local events, not triggerable by clients)
| Event | Arguments | Fired |
|---|---|---|
| `rsg-prison:server:sentenceStarted` | `src, minutes` | When belongings are seized for a new sentence |
| `rsg-prison:server:sentenceEnded` | `src, reason` (`'served'` or `'early'`) | When a prisoner is released |

### Client events (from the server or other client scripts)
| Event | Arguments | Notes |
|---|---|---|
| `rsg-prison:client:Enter` | `minutes, resume` | Sends the player to jail. `resume = true` skips the teleport when already inside `Config.PrisonZone` |
| `rsg-prison:client:freedom` | – | Releases the player (fade, teleport to `outside`, skin restored) |
| `rsg-prison:client:return` | – | The server found the prisoner outside the zone |
| `rsg-prison:client:updateTime` | `secs, total` | HUD sync (seconds left, original length) |
| `rsg-prison:client:disarm` | – | Unequips and removes weapons |
| `rsg-prison:client:reequip` | `weapons, knives` | Re-equips through rsg-weapons after release |

## Callbacks
| Callback | Side | Arguments | Returns |
|---|---|---|---|
| `rsg-prison:server:labourStart` | server | `siteIndex` | `true` when the prisoner may start working at `Config.Labour.sites[siteIndex]` |

```lua
local ok = RSGCore.Functions.AwaitCallback('rsg-prison:server:labourStart', 5000, siteIndex)
```

## Commands
| Command | Who | Description |
|---|---|---|
| `/searchprisoner` | On-duty `leo` job | Searches the nearest tracked prisoner within `Config.Contraband.distance` (server-side). Every stack not in `allowed` or the ration items is removed and adds `minutesPerItem` (max `maxExtraMinutes`). A prisoner can't be searched again within `cooldown` |

## Exports
### Server
| Export | Arguments | Returns |
|---|---|---|
| `DiscordLog` | `category, title, src, fields, description` | – |

`fields` is a list of `{ label, value, inline? }` (inline defaults to `true`). `src` may be `0` for the console. The categories are listed below; an unknown category falls back to `Default`.

```lua
exports['rsg-prison']:DiscordLog('jail', 'Prisoner transferred', src, {
    { 'From', 'Sisika' },
    { 'To', 'County jail' },
})
```

## Integration examples
### Jail a player
```lua
-- server
local Player = RSGCore.Functions.GetPlayer(target)
Player.Functions.SetMetaData('injail', 30) -- minutes
TriggerClientEvent('rsg-prison:client:Enter', target, 30) -- optional, the server tick also picks it up within 10 s
```

### Release a player early
```lua
Player.Functions.SetMetaData('injail', 0)
TriggerClientEvent('rsg-prison:client:freedom', target) -- optional, the server tick releases within 10 s
```

### Extend a sentence
```lua
local mins = Player.PlayerData.metadata.injail
Player.Functions.SetMetaData('injail', mins + 10) -- adopted on the next tick (HUD and logs update)
```

### Check if a player is jailed
```lua
-- server
local jailed = (Player.PlayerData.metadata.injail or 0) > 0
-- client (UI only; never trust it for rewards)
local pd = RSGCore.Functions.GetPlayerData()
local jailed = pd.metadata and (pd.metadata.injail or 0) > 0
```

### React to a sentence from another resource
```lua
-- server
AddEventHandler('rsg-prison:server:sentenceStarted', function(src, minutes)
    exports['rsg-voice']:SetPlayerMuted(src, true)
end)

AddEventHandler('rsg-prison:server:sentenceEnded', function(src, reason)
    exports['rsg-voice']:SetPlayerMuted(src, false)
end)
```
Always re-check `metadata.injail` on the server in your own events, as rsg-drugs and rsg-wardrobe do.

### Keep a prisoner out of your feature
```lua
if (Player.PlayerData.metadata.injail or 0) > 0 then return end
```

### Add a guard
```lua
-- config.lua
Config.MenuLocations[#Config.MenuLocations + 1] = {
    npcmodel  = `s_m_m_skpguard_01`,
    npccoords = vector4(3352.11, -690.77, 44.25, 31.30),
    showblip  = false,
}
```

## Discord logging
`server/config_discord.lua` is server-only so webhook URLs never reach clients.
| Category | Logged |
|---|---|
| `jail` | Sentence started, resumed, changed / extended |
| `release` | Served, released early (lawman / `injail = 0`), released while offline |
| `items` | Belongings seized, returned, kept (no room), weapons re-equipped, contraband summaries |
| `jobs` | Jobs removed on jailing |
| `escape` | Prisoner outside the zone (30 s cooldown per player) |
| `rations` | Water / bread given (`LogRations = false` skips) |
| `security` | Invalid, out-of-range or not-jailed ration requests (one log per player every 10 s) |
| `bail` | Bail paid |
| `labour` | Time taken off by labour |
| `contraband` | Lawman searches that seized items |

Per category: a URL, `''` to use `Default`, or `false` to disable. Embeds are queued, sent in batches of 10 and retried on HTTP 429 (the queue is capped at 100 per webhook). `ShowLicense`, `ShowDiscord`, `ShowCoords` control the identifiers shown.

## NUI (countdown HUD)
The HUD never takes focus. Messages sent with `SendNUIMessage`:
```lua
SendNUIMessage({ action = 'jail:hud', left = 540, total = 1800, title = 'Sentence remaining', sub = 'Stay within the prison walls.', ready = 'Getting ready for release!' })
SendNUIMessage({ action = 'jail:hide' })
```
`left` and `total` are seconds. The page counts down locally and resyncs on each server update (every 10 s).

## Security model
- **Server-authoritative sentence**: `injail` can only be written on the server. Starting, seizing, serving and releasing do not depend on any client event; the tick picks up untracked prisoners.
- **Zone enforcement**: the client returns escapees with a fade; the server checks the position every tick (after a 20 s grace) and moves the ped itself if the client ignores the return.
- **Rations / bail / collect**: validated on the server for jailed state, distance to a guard, cooldown, held amount and inventory space. Prices and rewards come from config.
- **Labour**: the server issues a start ticket through the callback, requires the full work time (minus 1.5 s latency) before the finish, re-checks distance, applies a cooldown and caps the total reduction. The cap survives reconnects (`jailtotal`, `jailreduced`).
- **Contraband**: lawman job and duty are checked on the server; the target and distance are found server-side; a per-prisoner cooldown applies.
- **Belongings**: seized and cleared in the same server tick; the record is wiped before items are handed back so nothing is returned twice. Leftovers are stored separately and never trigger an inventory wipe.
- **Logging**: suspicious requests are logged at most once per player every 10 seconds so a hostile client cannot flood the webhook.
- What other scripts must check: `metadata.injail` on the server before rewarding, trading or placing anything for a player.

## Persistence and database
rsg-prison creates **no database tables**. All state is player metadata (see above), saved by rsg-core with the character. The server also resets `players.outlawstatus` to `0` on release. The in-memory sentence table is rebuilt from metadata after a restart or reconnect.

## Server owner how-tos
- **Change the prison position**: update `Config.Locations`, `Config.MenuLocations` and `Config.PrisonZone` (the polygon points and their height band) together.
- **Prison post office**: add Sisika to `Config.PostOffices` in `rsg-telegram/shared/config.lua`.
- **Disable a feature**: `Config.Bail.enabled = false`, `Config.CollectProperty = false`, `Config.Labour.enabled = false`, `Config.Contraband.enabled = false`, `Config.ReturnOnEscape = false`.
- **Add a work site**: add `{ coords = vector3(x, y, z), radius = 1.5 }` to `Config.Labour.sites`.
- **Different ration items**: edit `Config.GuardRations.items`; the names must exist in the shared items.
- **Language**: `setr rsg:locale de` in `server.cfg`. Add a language by copying `locales/en.json` with all keys.
- **Discord**: set `Default` (one channel) or one webhook per category in `server/config_discord.lua`.

## Troubleshooting
| Problem | Check |
|---|---|
| Player jailed by metadata but nothing happens | The server tick picks them up within 10 s; check the console for errors and that `rsg-inventory` is started |
| Prisoner keeps being returned inside the walls | The zone polygon / height band doesn't cover the cells; adjust `Config.PrisonZone` |
| Guard options don't show | Rations and bail only show for prisoners; Collect Property only for released players with leftover items |
| Bail says "can't afford" | Bail is charged to `Config.Bail.account` (`bank`); cash is seized on entry |
| Items missing after release | Check the Discord `items` log; leftovers are in `jailowed` and returned at the guard or next login |
| Labour does nothing | You must be within the site radius, off cooldown and below the reduction cap; the sites must exist in `Config.Labour.sites` |
| `/searchprisoner` says nobody is near | The prisoner must be tracked by the server and within `Config.Contraband.distance`; the lawman must be on duty |
| Console: ration item does not exist | Fix the item name in `Config.GuardRations.items` |
| No Discord logs | `ConfigDiscord.Enabled`, a webhook or `Default` URL, and the category not set to `false` |

Support: https://rexshack.tebex.store
