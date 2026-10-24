<img width="2948" height="497" alt="rsg_framework" src="https://github.com/user-attachments/assets/638791d8-296d-4817-a596-785325c1b83a" />

# 🚔 rsg-prison
**Prison system for RedM servers using RSG Core.**

![Platform](https://img.shields.io/badge/platform-RedM-darkred)
![License](https://img.shields.io/badge/license-GPL--3.0-green)

---

## 🛠️ Dependencies
- [rsg-core](https://github.com/Rexshack-RedM/rsg-core)
- [rsg-inventory](https://github.com/Rexshack-RedM/rsg-inventory)
- [ox_lib](https://github.com/Rexshack-RedM/ox_lib)
- [ox_target](https://github.com/Rexshack-RedM/ox_target)
- [oxmysql](https://github.com/overextended/oxmysql)
- [rsg-telegram](https://github.com/Rexshack-RedM/rsg-telegram) *(prison post office)*

---

## ✨ Features
- Sends players to **Sisika Prison** at a random spawn, in prison clothes, with weapons removed.
- **Server-authoritative sentence**: the server counts down every minute, saves it to the `injail` metadata and releases the player. The client can't shorten its sentence.
- Sentence resumes after a disconnect or resource restart.
- Inventory is **seized on entry** and **returned on release**. Prison rations are cleared at the same time.
- Optional job removal (`Config.RemoveJob`).
- Outlaw status is reset on release.
- Prisoners who leave the prison zone are **returned automatically** (ox_lib poly zone).
- **Prison guard** (ox_target) menu:
  - **Request Water / Request Bread**: one at a time, up to `Config.GuardRations.max` (default 5) of each held, with a cooldown and a distance check on the server.
  - **Post Office**: read and send telegrams.
- Map blip, configurable locations, and JSON locales.

---

## 🔗 Integration
Jail a player (from your lawman script, server side):
```lua
Player.Functions.SetMetaData('injail', minutes)
TriggerClientEvent('rsg-prison:client:Enter', src, minutes)
```
Release a player early:
```lua
Player.Functions.SetMetaData('injail', 0)
TriggerClientEvent('rsg-prison:client:freedom', src)
```
Even if only the metadata is set to `0`, the server picks it up within a minute, returns the player's items and releases them.

---

## ⚙️ Configuration
All options are in `config.lua`:
- `Config.RemoveJob`, `Config.JailAllowance`, `Config.ReturnOnEscape`
- `Config.GuardRations`: max held, cooldown, distance and item names (`water`, `bread`)
- `Config.Locations`: release point, escape return point and spawn points
- `Config.MenuLocations`: guard NPCs
- `Config.PrisonZone`: prison boundary

---

## 📂 Installation
1. Place `rsg-prison` in `resources/[rsg]`.
2. Make sure the dependencies start first.
3. Add `ensure rsg-prison` to `server.cfg`.
4. If you used the old prison shop, remove the `prison` shop from your `rsg-shops` config.

---

## 🌍 Locales
`en`, `de`, `el`, `es`, `fr`, `it`, `ja`, `nl`, `pl`, `pt-br`, `ro` (via `lib.locale()`; set `setr ox:locale de` etc. in server.cfg). All player-facing text, including the blip name, lives in `locales/*.json`.

---

## 💎 Credits
- RSG / Rexshack-RedM and contributors
- License: GPL-3.0

Support: https://buymeacoffee.com/rexshack
