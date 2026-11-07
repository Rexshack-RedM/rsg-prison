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
