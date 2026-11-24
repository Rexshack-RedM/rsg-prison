<img width="2948" height="497" alt="rsg_framework" src="https://github.com/user-attachments/assets/638791d8-296d-4817-a596-785325c1b83a" />

# 🚔 rsg-prison
**Prison system for RedM servers using RSG Core.**

![Platform](https://img.shields.io/badge/platform-RedM-darkred)
![License](https://img.shields.io/badge/license-GPL--3.0-green)

---

## 🛠️ Dependencies
- [rsg-core](https://github.com/Rexshack-RedM/rsg-core)
- [rsg-inventory](https://github.com/Rexshack-RedM/rsg-inventory)
- [rsg-target](https://github.com/Rexshack-RedM/rsg-target)
- [oxmysql](https://github.com/overextended/oxmysql)
- [rsg-character](https://github.com/Rexshack-RedM/rsg-character) *(restores clothing on release)*
- [rsg-weapons](https://github.com/Rexshack-RedM/rsg-weapons) *(optional, re-equips weapons on release)*
- [rsg-telegram](https://github.com/Rexshack-RedM/rsg-telegram) *(optional, prison post office)*

---

## ✨ Features
- Sends players to **Sisika Prison** at a random spawn, in prison clothes. The outfit is re-applied after a respawn ([rsg-medic](https://github.com/Rexshack-RedM/rsg-medic) revive) or a skin reload.
- **Weapons are unequipped and seized** on entry, and the guns and knives that were equipped are **re-equipped on release** (via [rsg-weapons](https://github.com/Rexshack-RedM/rsg-weapons)).
- **Countdown HUD** (NUI, top left, never takes focus) showing the time left and a progress bar, in the same style as the rsg-drugs rehab HUD.
- **Server-authoritative sentence**: the server counts down (synced every 10 seconds), saves it to the `injail` metadata and releases the player. The client can't shorten its sentence, and a player whose `injail` is set is picked up by the server within 10 seconds even if their client never reports it (belongings seized, jobs removed, countdown started).
- Sentence resumes after a disconnect or resource restart. Re-jailing a prisoner (or changing `injail`) updates the running sentence.
- Inventory is **seized on entry** and **returned on release** (to the original slots where possible). Prison rations and any jail allowance are cleared at the same time. Anything that doesn't fit is kept separately and handed back on a later login without touching the rest of the inventory.
- Optional job removal (`Config.RemoveJob`): **every job** the player holds in rsg-core multi-job is removed and they're set to unemployed. They have to ask to be hired again after release.
- Outlaw status is reset on release.
- Prisoners who leave the prison zone are **returned automatically** (built-in poly zone). The client returns them with a fade; the server checks the position too and moves the player itself if a modified client ignores it.
- Rejoining or restarting the resource while jailed no longer teleports the prisoner to a random cell when they are already inside the walls.
- **Prison guard** (rsg-target) options:
  - **Request Water / Request Bread**: only shown to prisoners; one at a time, up to `Config.GuardRations.max` (default 5) of each held, with a cooldown and a distance check on the server.
- **Bail** (`Config.Bail`): a prisoner asks the guard for the price (per remaining minute, minimum price), asks again within 15 seconds to pay and is released. Charged to the bank by default, because cash is seized on entry.
- **Collect Property** (`Config.CollectProperty`): belongings that didn't fit on release can be collected from the guard once there is room, no relog needed.
- **Prison labour** (`Config.Labour`): prisoners break rocks at work sites inside the walls to take minutes off their sentence. The server issues the start, times the work, applies a per-cycle reduction with a cooldown and caps the total (default 50% of the sentence).
- **Contraband searches** (`Config.Contraband`): on-duty lawmen use `/searchprisoner` on the nearest prisoner. Anything not allowed (the guard rations and cash are) is seized and adds time to the sentence.
- Map blip, configurable locations, and JSON locales.

---

## 🎮 Commands
| Command | Who | What |
|---|---|---|
| `/searchprisoner` | On-duty `leo` job | Searches the nearest prisoner (within `Config.Contraband.distance`), seizes contraband and adds time |

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
Even if only the metadata is set to `0`, the server picks it up within 10 seconds, returns the player's items and releases them. Likewise, setting `injail` above `0` is enough to start a sentence: the server seizes the belongings and sends the player to the prison on its next tick.

---

## 📜 Discord Logs
Every important action is posted to Discord as an embed with the character name, citizen ID, server ID, license, Discord mention and coords. Settings are in `server/config_discord.lua`, which is **server-only**, so webhook URLs are never sent to clients.

| Category | Logged |
|---|---|
| `jail` | Prisoner jailed (sentence, job before), sentence resumed after reconnect, sentence changed/extended |
| `release` | Sentence served, released early (lawman / `injail` set to 0), released while offline (with time served) |
| `items` | Belongings seized and returned (full item list with weapon serials), leftovers kept, weapons re-equipped |
| `jobs` | Every job removed on jailing |
| `escape` | Prisoner left the prison zone (30s cooldown per player) |
| `rations` | Water / bread handed out (turn off with `LogRations = false`) |
| `bail` | Bail paid (price, minutes left) |
| `labour` | Time taken off a sentence by prison labour |
| `contraband` | Contraband seized by a lawman search (items, time added) |
| `security` | Rations requested while not jailed, out of range, or with an invalid item (rate limited to one log per player every 10 seconds) |

- Set one webhook per category, or just `Default` to send everything to one channel. Set a category to `false` to turn it off.
- Embeds are queued, batched (10 per message) and retried on Discord rate limits (HTTP 429).
- Other server resources can post into the same channels: `exports['rsg-prison']:DiscordLog(category, title, src, { { 'Label', value } })`

---

## ⚙️ Configuration
All options are in `config.lua` (Discord settings in `server/config_discord.lua`):
- `Config.RemoveJob`, `Config.JailAllowance`, `Config.ReturnOnEscape` (client check plus server-side backstop)
- `Config.GuardRations`: max held, cooldown, distance and item names (`water`, `bread`)
- `Config.Locations`: release point, escape return point and spawn points
- `Config.MenuLocations`: guard NPCs
- `Config.PrisonZone`: prison boundary
- `Config.Bail`, `Config.CollectProperty`: guard services
- `Config.Labour`: work sites, cycle length, cooldown, minutes off and the maximum share of the sentence labour can remove (the animation scenario is configurable)
- `Config.Contraband`: allowed items, minutes added per stack, cap and cooldown
- `Config.Clothing`: shop category hashes stripped on entry and the male / female prison outfit items

---

## 📂 Installation
1. Place `rsg-prison` in `resources/[rsg]`.
2. Make sure the dependencies start first.
3. Add `ensure rsg-prison` to `server.cfg`.
4. *(Optional)* Give prisoners a post office by adding Sisika to `Config.PostOffices` in `rsg-telegram/shared/config.lua`:
   ```lua
   { name = 'Sisika Post Office', coords = vector3(3354.0, -688.5, 44.25), showblip = false },
   ```
   Adjust the coords to a spot inside the prison walls.
5. If you used the old prison shop, remove the `prison` shop from your `rsg-shops` config.

---

## 🌍 Locales
`en`, `de`, `el`, `es`, `fr`, `it`, `ja`, `nl`, `pl`, `pt-br`, `ro`, `ru` (via rsg-core locales; set `setr rsg:locale de` etc. in server.cfg). All player-facing text, including the blip name, lives in `locales/*.json`.

---

## 💎 Credits
- RSG / Rexshack-RedM and contributors
- License: GPL-3.0

Support the Project : https://rexshack.tebex.store/
