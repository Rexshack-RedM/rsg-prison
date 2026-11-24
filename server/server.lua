local RSGCore = exports['rsg-core']:GetCoreObject()

---------------------------------
-- server-side sentence tracking (client never decides time)
---------------------------------
local Jailed = {}         -- [src] = { start, mins = sentence at start, last = last value written, total = for the HUD bar, since, out }
local RationCooldown = {}
local EscapeCooldown = {}
local SecurityCooldown = {}

local TICK_MS = 10000     -- sentence tick
local ZONE_GRACE = 20     -- seconds after a sentence starts before the server zone check applies (teleport + fade)

-- "3x bread, 1x weapon_revolver_cattleman" style list for the Discord logs
local function itemList(items)
    local lines, max = {}, (ConfigDiscord and ConfigDiscord.MaxItemLines) or 25
    for i, v in ipairs(items or {}) do
        if i > max then lines[#lines + 1] = locale('dc_more', #items - max) break end
        local serial = type(v.info) == 'table' and v.info.serie and (' (' .. v.info.serie .. ')') or ''
        lines[#lines + 1] = ('%sx %s%s'):format(v.amount, v.name, serial)
    end
    return #lines > 0 and table.concat(lines, '\n') or locale('dc_nothing')
end

local function notify(src, desc, ntype, title)
    TriggerClientEvent('RSGCore:Client:Notify', src, { title = title or locale('sv_ration_title'), description = desc, type = ntype })
end

-- is the player within `maxDist` of any guard? (server-side position)
local function nearGuard(src, maxDist)
    local pcoords = GetEntityCoords(GetPlayerPed(src))
    for _, v in ipairs(Config.MenuLocations) do
        if #(pcoords - v.npccoords.xyz) <= maxDist then return true end
    end
    return false
end

local function countOf(t)
    local n = 0
    for _ in pairs(type(t) == 'table' and t or {}) do n = n + 1 end
    return n
end

-- suspicious-request logs are rate limited per player so a hostile client can't flood the webhook
local function securityLog(src, title, fields)
    local now = os.time()
    if SecurityCooldown[src] and now - SecurityCooldown[src] < 10 then return end
    SecurityCooldown[src] = now
    PrisonLog('security', title, src, fields)
end

---------------------------------
-- seizure state
-- jailitems = belongings held while serving; jailseized = true while they are held (an empty inventory still counts)
-- jailowed  = belongings that did not fit on release, handed back on a later login (never wipes the inventory)
---------------------------------
local function isSeized(Player)
    local meta = Player.PlayerData.metadata
    if meta.jailseized then return true end
    return type(meta.jailitems) == 'table' and next(meta.jailitems) ~= nil -- sentences started before 3.4.0
end

---------------------------------
-- weapons (rsg-weapons): remember what was equipped on entry, re-equip on release
---------------------------------
local function snapshotEquipped(Player)
    local weapons, knives = {}, {}
    for serial in pairs(Player.PlayerData.metadata.equippedweapons or {}) do weapons[#weapons + 1] = tostring(serial) end
    for name in pairs(Player.PlayerData.metadata.equippedknives or {}) do knives[#knives + 1] = name end
    Player.Functions.SetMetaData('jailequipped', { weapons = weapons, knives = knives })
end

local function reequip(src, Player)
    local saved = Player.PlayerData.metadata.jailequipped
    Player.Functions.SetMetaData('jailequipped', nil)
    if type(saved) ~= 'table' then return end
    local want = {}
    for _, s in ipairs(saved.weapons or {}) do want[s] = true end
    local Fresh = RSGCore.Functions.GetPlayer(src) or Player -- items were just re-added
    local list = {}
    for _, it in pairs(Fresh.PlayerData.items or {}) do
        if it and type(it.info) == 'table' and it.info.serie and want[tostring(it.info.serie)] then list[#list + 1] = it end
    end
    local knives = {}
    for _, name in ipairs(saved.knives or {}) do
        if exports['rsg-inventory']:HasItem(src, name, 1) then knives[#knives + 1] = name end
    end
    if #list > 0 or #knives > 0 then
        TriggerClientEvent('rsg-prison:client:reequip', src, list, knives)
        PrisonLog('items', locale('dc_t_reequipped'), src, { { locale('dc_f_guns'), #list }, { locale('dc_f_knives'), #knives } })
    end
end

---------------------------------
-- jobs: strip every job (rsg-core multi-job) so the player has to be re-hired
---------------------------------
local function removeAllJobs(src, Player)
    local removed = {}
    for _, j in ipairs(exports['rsg-core']:GetPlayerJobs(src) or {}) do
        if j.job and j.job ~= 'unemployed' and exports['rsg-core']:RemovePlayerJob(src, j.job) then -- drops the active job to unemployed too
            removed[#removed + 1] = ('%s (%s)'):format(j.jobLabel or j.job, j.gradeLabel or j.grade or '-')
        end
    end
    local active = Player.PlayerData.job.name
    if active ~= 'unemployed' then
        Player.Functions.SetJob('unemployed', 0)
        if #removed == 0 then removed[1] = active end
    end
    if #removed > 0 then
        PrisonLog('jobs', locale('dc_t_jobs_removed'), src, { { locale('dc_f_jobs'), table.concat(removed, '\n'), false } })
    end
end

---------------------------------
-- belongings
---------------------------------
-- adds the list back (original slot first, then any free slot); returns what did not fit
local function giveBack(src, list)
    local left = {}
    for _, v in pairs(list) do
        local amount = tonumber(v.amount)
        if v.name and RSGCore.Shared.Items[v.name] and amount and amount > 0 then
            if not exports['rsg-inventory']:AddItem(src, v.name, amount, v.info, v.slot, 'rsg-prison-return-items')
                and not exports['rsg-inventory']:AddItem(src, v.name, amount, v.info, nil, 'rsg-prison-return-items') then
                left[#left + 1] = v
            end
        end
    end
    return left
end

-- returns true when something was released/returned
local function returnItems(src, Player)
    local meta = Player.PlayerData.metadata
    local seized = isSeized(Player)
    local owed = type(meta.jailowed) == 'table' and meta.jailowed or {}
    if not seized and not next(owed) then return false end

    local list = {}
    if seized then
        for _, v in pairs(type(meta.jailitems) == 'table' and meta.jailitems or {}) do list[#list + 1] = v end
        -- wipe the record first so nothing can be handed out twice
        Player.Functions.SetMetaData('jailitems', {})
        Player.Functions.SetMetaData('jailseized', false)
        Player.Functions.SetMetaData('jailtotal', 0)
        Player.Functions.SetMetaData('jailreduced', 0)
        Player.Functions.ClearInventory() -- remove prison rations (and any jail allowance). Only done when belongings were seized, never on a leftover retry
    end
    for _, v in pairs(owed) do list[#list + 1] = v end

    local left = giveBack(src, list)
    Player.Functions.SetMetaData('jailowed', left)

    if #list > 0 then
        PrisonLog('items', locale('dc_t_items_returned'), src, {
            { locale('dc_f_stacks_returned'), #list - #left }, { locale('dc_f_kept'), #left },
            { locale('dc_f_items'), itemList(list), false },
        })
    end
    if #left > 0 and (seized or #left < #list) then -- keep what didn't fit; handed back on next login (no repeat notice when nothing new fit)
        TriggerClientEvent('RSGCore:Client:Notify', src, { title = locale('cl_property_returned'), description = locale('sv_items_partial'), type = 'warning', duration = 10000 })
    end
    if seized then
        MySQL.update('UPDATE players SET outlawstatus = ? WHERE citizenid = ?', { 0, Player.PlayerData.citizenid })
        reequip(src, Player)
    end
    return true
end

local function release(src, Player, tellClient, reason)
    local j = Jailed[src]
    PrisonLog('release', locale('dc_t_released'), src, {
        { locale('dc_f_reason'), reason or locale('dc_r_served') },
        { locale('dc_f_time_served'), j and locale('dc_minutes', math.floor((os.time() - j.start) / 60)) or '-' },
    })
    Jailed[src] = nil
    Player.Functions.SetMetaData('injail', 0)
    returnItems(src, Player)
    TriggerEvent('rsg-prison:server:sentenceEnded', src, reason and 'early' or 'served') -- server-side hook for other resources
    if tellClient then TriggerClientEvent('rsg-prison:client:freedom', src) end
end

---------------------------------
-- start / resume sentence. Called by the client (jailing, reconnect) AND by the tick below,
-- so a client that never fires the event can't dodge the seizure or the countdown
---------------------------------
local function startSentence(src, Player)
    local injail = tonumber(Player.PlayerData.metadata.injail) or 0
    if injail <= 0 then return end
    local now = os.time()

    local j = Jailed[src]
    if j then
        if injail == j.last then return end -- nothing changed (repeat call), stay silent
        -- re-jailed / extended / reduced while serving: adopt the new sentence
        PrisonLog('jail', locale('dc_t_changed'), src, { { locale('dc_f_from'), locale('dc_minutes', j.last) }, { locale('dc_f_to'), locale('dc_minutes', injail) } })
        Jailed[src] = { start = now, mins = injail, last = injail, total = injail * 60, since = j.since, reduced = j.reduced }
        TriggerClientEvent('rsg-prison:client:updateTime', src, injail * 60, injail * 60)
        return
    end

    Jailed[src] = { start = now, mins = injail, last = injail, total = injail * 60, since = now }
    TriggerClientEvent('rsg-prison:client:updateTime', src, injail * 60, injail * 60)

    if isSeized(Player) then -- already holding belongings for this sentence (reconnect / resource restart)
        local meta = Player.PlayerData.metadata
        Jailed[src].reduced = tonumber(meta.jailreduced) or 0
        Jailed[src].total = tonumber(meta.jailtotal) or Jailed[src].total -- HUD bar keeps the original sentence length
        TriggerClientEvent('rsg-prison:client:updateTime', src, injail * 60, Jailed[src].total)
        PrisonLog('jail', locale('dc_t_resumed'), src, { { locale('dc_f_remaining'), locale('dc_minutes', injail) } })
        if Config.RemoveJob then removeAllJobs(src, Player) end
        return
    end

    -- snapshot and clear in the same tick so nothing can be moved out first
    snapshotEquipped(Player) -- before the clear, rsg-weapons drops guns that leave the inventory
    local items = {}
    for slot, v in pairs(Player.PlayerData.items or {}) do
        if v and v.name and v.amount and v.amount > 0 then
            items[#items + 1] = { name = v.name, amount = v.amount, info = v.info, slot = v.slot or slot }
        end
    end
    Player.Functions.ClearInventory()
    Player.Functions.SetMetaData('jailitems', items)
    Player.Functions.SetMetaData('jailseized', true)
    Player.Functions.SetMetaData('jailtotal', injail * 60) -- original length, the labour cap is a share of this
    Player.Functions.SetMetaData('jailreduced', 0)
    TriggerClientEvent('rsg-prison:client:disarm', src)
    PrisonLog('jail', locale('dc_t_jailed'), src, { { locale('dc_f_sentence'), locale('dc_minutes', injail) }, { locale('dc_f_job_before'), Player.PlayerData.job.label or Player.PlayerData.job.name } })
    PrisonLog('items', locale('dc_t_items_seized'), src, { { locale('dc_f_stacks'), #items }, { locale('dc_f_items'), itemList(items), false } })
    TriggerEvent('rsg-prison:server:sentenceStarted', src, injail) -- server-side hook for other resources

    -- after the snapshot: rsg-core multi-job awaits the database, and nothing may yield before the clear
    if Config.RemoveJob then removeAllJobs(src, Player) end

    if Config.JailAllowance > 0 then
        Player.Functions.AddMoney('cash', Config.JailAllowance, 'rsg-prison-jail-allowance')
    end
end

---------------------------------
-- escapes: logged, rate limited, and enforced by the server as a backstop to the client zone check
---------------------------------
local function logEscape(src, Player)
    local now = os.time()
    if EscapeCooldown[src] and now - EscapeCooldown[src] < 30 then return end
    EscapeCooldown[src] = now
    PrisonLog('escape', locale('dc_t_escape'), src, { { locale('dc_f_remaining'), locale('dc_minutes', Player.PlayerData.metadata.injail) } })
end

local function enforceZone(src, Player, j, now)
    if not Config.ReturnOnEscape or now - (j.since or now) < ZONE_GRACE then return end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    if PrisonZoneContains(GetEntityCoords(ped)) then j.out = 0 return end

    j.out = (j.out or 0) + 1
    logEscape(src, Player)
    if j.out == 1 then
        TriggerClientEvent('rsg-prison:client:return', src) -- normal path: the client fades and returns the player
    else
        local e = Config.Locations.escape -- the client ignored it (modified client): move the ped from the server
        SetEntityCoords(ped, e.x, e.y, e.z)
        SetEntityHeading(ped, e.w)
        j.out = 0
    end
end

---------------------------------
-- sentence tick (every 10s; metadata only written when the minute changes)
---------------------------------
CreateThread(function()
    while true do
        Wait(TICK_MS)
        local now = os.time()

        -- 1) players with a sentence the server isn't tracking yet (jailed by metadata only, or a client that skipped the event)
        local pending = {}
        for src, Player in pairs(RSGCore.Functions.GetRSGPlayers()) do
            if not Jailed[src] and (tonumber(Player.PlayerData.metadata.injail) or 0) > 0 then pending[#pending + 1] = src end
        end
        for _, src in ipairs(pending) do
            local Player = RSGCore.Functions.GetPlayer(src)
            if Player and not Jailed[src] then
                startSentence(src, Player)
                if Jailed[src] then TriggerClientEvent('rsg-prison:client:Enter', src, Jailed[src].mins, true) end
            end
        end

        -- 2) tracked prisoners
        for src, j in pairs(Jailed) do
            local Player = RSGCore.Functions.GetPlayer(src)
            if not Player then
                Jailed[src] = nil
            elseif (tonumber(Player.PlayerData.metadata.injail) or 0) <= 0 then
                release(src, Player, true, locale('dc_r_early')) -- e.g. lawman
            else
                if Player.PlayerData.metadata.injail ~= j.last then -- sentence changed externally (e.g. extended), rebase on it
                    startSentence(src, Player)
                    j = Jailed[src] or j
                end
                local secsLeft = j.mins * 60 - (now - j.start)
                if secsLeft <= 0 then
                    release(src, Player, true)
                else
                    -- saved in whole minutes. Rounded up so the stored value can't hit 0 before the release below
                    local remaining = math.ceil(secsLeft / 60)
                    if remaining ~= j.last then
                        j.last = remaining
                        Player.Functions.SetMetaData('injail', remaining)
                    end
                    TriggerClientEvent('rsg-prison:client:updateTime', src, secsLeft, j.total)
                    enforceZone(src, Player, j, now)
                end
            end
        end
    end
end)

---------------------------------
-- client asks to start / resume (jailing, reconnect); the server validates against the metadata
---------------------------------
RegisterNetEvent('rsg-prison:server:startSentence', function()
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end
    startSentence(src, Player)
end)

---------------------------------
-- client reports release (lawman unjail / offline release); server re-checks
---------------------------------
RegisterNetEvent('rsg-prison:server:checkRelease', function()
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end
    if (tonumber(Player.PlayerData.metadata.injail) or 0) > 0 then return end
    local wasJailed = Jailed[src]
    local seizedBefore = isSeized(Player)
    Jailed[src] = nil
    if wasJailed then -- released early before the tick noticed (e.g. lawman /unjail)
        PrisonLog('release', locale('dc_t_released'), src, {
            { locale('dc_f_reason'), locale('dc_r_early') },
            { locale('dc_f_time_served'), locale('dc_minutes', math.floor((os.time() - wasJailed.start) / 60)) },
        })
    elseif seizedBefore then -- released while offline
        PrisonLog('release', locale('dc_t_released'), src, { { locale('dc_f_reason'), locale('dc_r_offline') } })
    end
    returnItems(src, Player) -- also retries belongings that didn't fit on an earlier release (never wipes the inventory)
    if wasJailed or seizedBefore then TriggerEvent('rsg-prison:server:sentenceEnded', src, 'early') end
end)

---------------------------------
-- escape attempts (client reports leaving the zone; the server tick checks it independently)
---------------------------------
RegisterNetEvent('rsg-prison:server:escapeAttempt', function()
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player or (tonumber(Player.PlayerData.metadata.injail) or 0) <= 0 then return end
    logEscape(src, Player)
end)

---------------------------------
-- guard rations (water / bread)
---------------------------------
RegisterNetEvent('rsg-prison:server:requestRation', function(kind)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    local item = type(kind) == 'string' and Config.GuardRations.items[kind]
    if not item or not RSGCore.Shared.Items[item] then
        return securityLog(src, locale('dc_t_invalid_ration'), { { locale('dc_f_sent'), tostring(kind):sub(1, 64) } })
    end

    if (tonumber(Player.PlayerData.metadata.injail) or 0) <= 0 then
        securityLog(src, locale('dc_t_ration_not_jailed'), { { locale('dc_f_item'), item } })
        return notify(src, locale('sv_ration_not_jailed'), 'error')
    end

    if not nearGuard(src, Config.GuardRations.distance) then
        return securityLog(src, locale('dc_t_ration_range'), { { locale('dc_f_item'), item }, { locale('dc_f_max_distance'), Config.GuardRations.distance } })
    end

    local now = os.time()
    if RationCooldown[src] and now - RationCooldown[src] < Config.GuardRations.cooldown then
        return notify(src, locale('sv_ration_wait'), 'error')
    end

    if (exports['rsg-inventory']:GetItemCount(src, item) or 0) >= Config.GuardRations.max then
        return notify(src, locale('sv_ration_max', Config.GuardRations.max), 'error')
    end

    if not exports['rsg-inventory']:CanAddItem(src, item, 1) then
        return notify(src, locale('sv_ration_full'), 'error')
    end

    if exports['rsg-inventory']:AddItem(src, item, 1, nil, nil, 'rsg-prison-guard-ration') then -- AddItem already shows the item box
        RationCooldown[src] = now
        notify(src, locale('sv_ration_given'), 'success')
        if ConfigDiscord.LogRations then PrisonLog('rations', locale('dc_t_ration_given'), src, { { locale('dc_f_item'), item } }) end
    end
end)

---------------------------------
-- guard: bail (pay for early release) and collecting leftover property
---------------------------------
local PendingBail = {}
local CollectCooldown = {}

local function bailPrice(j)
    local secsLeft = math.max(0, j.mins * 60 - (os.time() - j.start))
    return math.max(Config.Bail.minimum, math.ceil(secsLeft / 60) * Config.Bail.pricePerMinute)
end

-- first request quotes the price, a second one within confirmSeconds pays it
RegisterNetEvent('rsg-prison:server:requestBail', function()
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player or not Config.Bail.enabled then return end
    local title = locale('sv_bail_title')

    local j = Jailed[src]
    if not j or (tonumber(Player.PlayerData.metadata.injail) or 0) <= 0 then
        return notify(src, locale('sv_ration_not_jailed'), 'error', title)
    end
    if not nearGuard(src, Config.GuardRations.distance) then return end

    local now = os.time()
    local price = bailPrice(j)
    local pending = PendingBail[src]
    if not pending or pending.expires < now or price > pending.price then -- no quote, expired, or the sentence grew
        PendingBail[src] = { price = price, expires = now + Config.Bail.confirmSeconds }
        return notify(src, locale('sv_bail_quote', price, Config.Bail.confirmSeconds), 'inform', title)
    end
    PendingBail[src] = nil

    if not Player.Functions.RemoveMoney(Config.Bail.account, price, 'rsg-prison-bail') then
        return notify(src, locale('sv_bail_poor', price), 'error', title)
    end
    notify(src, locale('sv_bail_paid', price), 'success', title)
    PrisonLog('bail', locale('dc_t_bail'), src, {
        { locale('dc_f_price'), '$' .. price },
        { locale('dc_f_remaining'), locale('dc_minutes', math.ceil(math.max(0, j.mins * 60 - (now - j.start)) / 60)) },
    })
    release(src, Player, true, locale('dc_r_bail'))
end)

-- belongings that did not fit on release: ask the guard instead of relogging
RegisterNetEvent('rsg-prison:server:collectProperty', function()
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player or not Config.CollectProperty then return end
    if (tonumber(Player.PlayerData.metadata.injail) or 0) > 0 then return end
    if not nearGuard(src, Config.GuardRations.distance) then return end

    local now = os.time()
    if CollectCooldown[src] and now - CollectCooldown[src] < 3 then return end
    CollectCooldown[src] = now

    local title = locale('cl_property_returned')
    local before = countOf(Player.PlayerData.metadata.jailowed)
    if before == 0 then return notify(src, locale('sv_collect_nothing'), 'inform', title) end

    returnItems(src, Player) -- never wipes the inventory on this path
    local after = countOf(Player.PlayerData.metadata.jailowed)
    if after == 0 then
        notify(src, locale('cl_property_has_been'), 'success', title)
    elseif after == before then
        notify(src, locale('sv_items_partial'), 'warning', title)
    end
end)

---------------------------------
-- prison labour: break rocks to take time off the sentence
-- the server issues the start, times the work and applies the reduction; the client only plays the animation
---------------------------------
local Labour = {}         -- [src] = { site, at }
local LabourCooldown = {} -- [src] = os.time() the next cycle may start

-- seconds of labour reduction allowed for this sentence (a share of the original length, which survives reconnects)
local function labourCap(Player, j)
    return math.floor((tonumber(Player.PlayerData.metadata.jailtotal) or j.total) * Config.Labour.maxReduction / 100)
end

local function labourNear(src, site)
    return #(GetEntityCoords(GetPlayerPed(src)) - site.coords) <= site.radius + Config.Labour.distance
end

RSGCore.Functions.CreateCallback('rsg-prison:server:labourStart', function(source, cb, siteIndex)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    local j = Jailed[src]
    local idx = math.tointeger(tonumber(siteIndex))
    local site = idx and Config.Labour.sites[idx]
    if not Player or not Config.Labour.enabled or not j or not site or not labourNear(src, site) then return cb(false) end

    local title = locale('sv_labour_title')
    if LabourCooldown[src] and os.time() < LabourCooldown[src] then
        notify(src, locale('sv_labour_wait'), 'error', title)
        return cb(false)
    end
    if (j.reduced or 0) >= labourCap(Player, j) then
        notify(src, locale('sv_labour_limit'), 'error', title)
        return cb(false)
    end

    Labour[src] = { site = site, at = GetGameTimer() }
    cb(true)
end)

RegisterNetEvent('rsg-prison:server:labourFinish', function()
    local src = source
    local l = Labour[src]
    Labour[src] = nil
    local Player = RSGCore.Functions.GetPlayer(src)
    local j = Jailed[src]
    if not l or not Player or not j or not Config.Labour.enabled then return end
    if GetGameTimer() - l.at < Config.Labour.duration - 1500 then return end -- finished too fast, the client skipped the work
    if not labourNear(src, l.site) then return end

    local cap = labourCap(Player, j)
    local give = math.min(Config.Labour.minutesOff * 60, cap - (j.reduced or 0))
    local title = locale('sv_labour_title')
    if give <= 0 then return notify(src, locale('sv_labour_limit'), 'error', title) end

    j.reduced = (j.reduced or 0) + give
    Player.Functions.SetMetaData('jailreduced', j.reduced)
    j.start = j.start - give -- the tick works the remaining time out from this
    LabourCooldown[src] = os.time() + Config.Labour.cooldown

    local secsLeft = math.max(0, j.mins * 60 - (os.time() - j.start))
    TriggerClientEvent('rsg-prison:client:updateTime', src, secsLeft, j.total)
    notify(src, locale('sv_labour_done', locale('dc_minutes', ('%g'):format(give / 60))), 'success', title)
    PrisonLog('labour', locale('dc_t_labour'), src, {
        { locale('dc_f_reduced'), locale('dc_minutes', ('%g'):format(give / 60)) },
        { locale('dc_f_remaining'), locale('dc_minutes', math.ceil(secsLeft / 60)) },
    })
end)

---------------------------------
-- contraband: on-duty lawmen search the nearest prisoner; anything not allowed is seized and adds time
---------------------------------
local SearchedAt = {}

RSGCore.Commands.Add('searchprisoner', locale('sv_search_cmd'), {}, false, function(source)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player or not Config.Contraband.enabled then return end
    local title = locale('sv_search_title')

    local job = Player.PlayerData.job
    if job.type ~= 'leo' or not job.onduty then return notify(src, locale('sv_search_not_leo'), 'error', title) end

    local pos = GetEntityCoords(GetPlayerPed(src))
    local target, best
    for tsrc in pairs(Jailed) do
        if tsrc ~= src then
            local d = #(pos - GetEntityCoords(GetPlayerPed(tsrc)))
            if d <= Config.Contraband.distance and (not best or d < best) then target, best = tsrc, d end
        end
    end
    local TPlayer = target and RSGCore.Functions.GetPlayer(target)
    if not TPlayer then return notify(src, locale('sv_search_none_near'), 'error', title) end

    local now = os.time()
    if SearchedAt[target] and now - SearchedAt[target] < Config.Contraband.cooldown then
        return notify(src, locale('sv_search_recent'), 'inform', title)
    end
    SearchedAt[target] = now

    local allowed = {}
    for _, name in ipairs(Config.Contraband.allowed) do allowed[name] = true end
    for _, name in pairs(Config.GuardRations.items) do allowed[name] = true end

    local found = {}
    for slot, v in pairs(TPlayer.PlayerData.items or {}) do
        if v and v.name and not allowed[v.name] and (tonumber(v.amount) or 0) > 0 then
            found[#found + 1] = { name = v.name, amount = v.amount, info = v.info, slot = v.slot or slot }
        end
    end

    local seized = {}
    for _, it in ipairs(found) do
        if exports['rsg-inventory']:RemoveItem(target, it.name, it.amount, it.slot, 'rsg-prison-contraband') then seized[#seized + 1] = it end
    end

    if #seized == 0 then
        notify(src, locale('sv_search_clean'), 'inform', title)
        return notify(target, locale('sv_search_target_clean'), 'inform', title)
    end

    local extra = math.min(Config.Contraband.maxExtraMinutes, #seized * Config.Contraband.minutesPerItem)
    TPlayer.Functions.SetMetaData('injail', (tonumber(TPlayer.PlayerData.metadata.injail) or 0) + extra)
    TPlayer.Functions.SetMetaData('jailtotal', (tonumber(TPlayer.PlayerData.metadata.jailtotal) or Jailed[target].total) + extra * 60)
    startSentence(target, TPlayer) -- adopt the longer sentence straight away (HUD + log)

    local added = locale('dc_minutes', extra)
    notify(src, locale('sv_search_found', #seized, added), 'success', title)
    notify(target, locale('sv_search_target_found', added), 'warning', title)
    PrisonLog('contraband', locale('dc_t_contraband'), target, {
        { locale('dc_f_stacks'), #seized }, { locale('dc_f_added'), added },
        { locale('dc_f_items'), itemList(seized), false },
    })
end)

---------------------------------
-- config sanity check
---------------------------------
CreateThread(function()
    Wait(2000)
    for kind, item in pairs(Config.GuardRations.items) do
        if not RSGCore.Shared.Items[item] then
            print(('^1[rsg-prison] Config.GuardRations.items.%s uses the item "%s" which does not exist in the shared items.^7'):format(kind, item))
        end
    end
end)

---------------------------------
-- cleanup
---------------------------------
AddEventHandler('playerDropped', function()
    local src = source
    Jailed[src] = nil
    RationCooldown[src] = nil
    EscapeCooldown[src] = nil
    SecurityCooldown[src] = nil
    PendingBail[src] = nil
    CollectCooldown[src] = nil
    Labour[src] = nil
    LabourCooldown[src] = nil
    SearchedAt[src] = nil
end)
