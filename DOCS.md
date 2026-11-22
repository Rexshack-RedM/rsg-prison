# rsg-prison – Developer Docs

## Dependencies
rsg-core, rsg-inventory, rsg-character, rsg-target, oxmysql. **No ox_lib** (removed in 3.3.0).

## ox_lib migration (3.3.0)
| Was (ox_lib) | Now |
|---|---|
| `@ox_lib/init.lua` + `lib.locale()` | `@rsg-core/shared/locale.lua`, `locale()` directly (convar `rsg:locale`) |
| `lib.notify` / `ox_lib:notify` | `RSGCore.Functions.Notify` / `RSGCore:Client:Notify` |
| `lib.requestModel` | `RSGCore.Functions.RequestModel` |
| `lib.points.new` | `points.new` via `@rsg-core/client/points.lua` |
| `lib.zones.poly` | local point-in-polygon check (500 ms, only while jailed) using `Config.PrisonZone` |
| `lib.registerContext` guard menu | two rsg-target options on the guard ped (water / bread) |
| `lib.onCache('ped')` | 1 s thread watching `PlayerPedId()` changes |
| `cache.ped` | `PlayerPedId()` |
| `exports.ox_target` | `exports['rsg-target']` |

## Events
- `rsg-prison:client:Enter (minutes)` – send player to jail
- `rsg-prison:client:freedom` – release
- `rsg-prison:client:requestRation ('water'|'bread')` – client; forwards to server only while jailed (replaces old `rsg-prison:client:menu`)
- `rsg-prison:server:requestRation (kind)` – server validates jailed state, distance, cooldown and max
- `rsg-prison:server:escapeAttempt` – logged, rate-limited server-side

## Config
`Config.PrisonZone.points` (vec3 list) and `thickness` (total height band centred on the first point's z).

<!-- BEGIN AUTO-REFERENCE (generated from the code; re-run the generator instead of editing by hand) -->

## Technical reference

Generated from the source of **rsg-prison 3.3.1**. Names, arguments and defaults below are read straight from the code.

### Dependencies

`rsg-core`, `rsg-inventory`, `rsg-character`, `rsg-target`, `oxmysql`

### Configuration

| Option | Default | Notes |
|---|---|---|
| `Config.RemoveJob` | `true` | player loses ALL their jobs (rsg-core multi-job) when jailed and must be re-hired |
| `Config.JailAllowance` | `0` | cash given when jailed (0 = none) |
| `Config.DistanceSpawn` | `20.0` | distance the guard npc spawns at |
| `Config.FadeIn` | `true` | fade the guard npc in / out |
| `Config.ReturnOnEscape` | `true` | teleport prisoners back if they leave the prison zone |
| `Config.GuardRations` | `table` |  |
| `Config.Blip` | `table` |  |
| `Config.Locations` | `table` |  |
| `Config.MenuLocations` | `table` | prison guard (menu) locations |
| `Config.PrisonZone` | `table` | prison boundary (poly zone; thickness = height around points' z) |

### Exports

**Server**

| Export | Arguments | File |
|---|---|---|
| `DiscordLog` | `category, title, src, fields, description` | `server/discord.lua` |

```lua
-- example
local result = exports['rsg-prison']:DiscordLog(category, title, src, fields, description)
```

### Events

Server events can be fired by any client, so every handler re-validates the player, the arguments and any permission, distance or cooldown on the server. Never add a reward to a handler without those checks.

| Event | Side | Arguments | File |
|---|---|---|---|
| `rsg-prison:client:updateTime` | client | `secs, total` | `client/client.lua` |
| `rsg-prison:client:disarm` | client | `` | `client/client.lua` |
| `rsg-prison:client:reequip` | client | `weapons, knives` | `client/client.lua` |
| `rsg-prison:client:requestRation` | client | `kind` | `client/client.lua` |
| `rsg-prison:client:Enter` | client | `time` | `client/client.lua` |
| `rsg-prison:client:freedom` | client | `` | `client/client.lua` |
| `RSGCore:Client:OnPlayerLoaded` | client | `` | `client/client.lua` |
| `RSGCore:Client:OnPlayerUnload` | client | `` | `client/client.lua` |
| `rsg-prison:server:startSentence` | server | `` | `server/server.lua` |
| `rsg-prison:server:checkRelease` | server | `` | `server/server.lua` |
| `rsg-prison:server:escapeAttempt` | server | `` | `server/server.lua` |
| `rsg-prison:server:requestRation` | server | `kind` | `server/server.lua` |

```lua
-- from a client script
TriggerServerEvent('rsg-prison:server:startSentence')
-- from a server script
TriggerClientEvent('rsg-prison:client:updateTime', source, secs, total)
```

### Locales

Language files in `locales/`: `de`, `el`, `en`, `es`, `fr`, `it`, `ja`, `nl`, `pl`, `pt-br`, `ro`, `ru`. Set the language with `setr rsg:locale "en"`.

<!-- END AUTO-REFERENCE -->
