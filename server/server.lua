local RSGCore = exports['rsg-core']:GetCoreObject()
lib.locale()

---------------------------------
-- server-side sentence tracking (client never decides time)
---------------------------------
local Jailed = {}         -- [src] = { start, mins = sentence at start, last = last value written, total = for the HUD bar }
local RationCooldown = {}
local EscapeCooldown = {}

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

local function notify(src, desc, ntype)
    TriggerClientEvent('ox_lib:notify', src, { title = locale('sv_ration_title'), description = desc, type = ntype })
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
-- jobs: strip every job (rsg-multijob) so the player has to be re-hired
---------------------------------
local function removeAllJobs(src, Player)
    local removed = {}
    if GetResourceState('rsg-multijob') == 'started' then
        for _, j in ipairs(exports['rsg-multijob']:GetJobs(src) or {}) do
            if j.job and j.job ~= 'unemployed' and exports['rsg-multijob']:RemoveJob(src, j.job) then -- drops the active job to unemployed too
                removed[#removed + 1] = ('%s (%s)'):format(j.jobLabel or j.job, j.gradeLabel or j.grade or '-')
            end
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

local function returnItems(src, Player)
    local items = Player.PlayerData.metadata.jailitems
    if not items or not next(items) then return false end

    -- wipe the record first so nothing can be handed out twice
    Player.Functions.SetMetaData('jailitems', {})
    Player.Functions.ClearInventory() -- remove prison rations (and any jail allowance)
    local left = {}
    for _, v in pairs(items) do
        local amount = tonumber(v.amount)
        if v.name and RSGCore.Shared.Items[v.name] and amount and amount > 0 then
            -- try the original slot first, fall back to any free slot
            if not exports['rsg-inventory']:AddItem(src, v.name, amount, v.info, v.slot, 'rsg-prison-return-items')
                and not exports['rsg-inventory']:AddItem(src, v.name, amount, v.info, nil, 'rsg-prison-return-items') then
                left[#left + 1] = v
            end
        end
    end
    PrisonLog('items', locale('dc_t_items_returned'), src, {
        { locale('dc_f_stacks_returned'), #items - #left }, { locale('dc_f_kept'), #left },
        { locale('dc_f_items'), itemList(items), false },
    })
    if #left > 0 then -- keep what didn't fit; handed back on next login
        Player.Functions.SetMetaData('jailitems', left)
        TriggerClientEvent('ox_lib:notify', src, { title = locale('cl_property_returned'), description = locale('sv_items_partial'), type = 'warning', duration = 10000 })
    end
    MySQL.update('UPDATE players SET outlawstatus = ? WHERE citizenid = ?', { 0, Player.PlayerData.citizenid })
    reequip(src, Player)
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
    if tellClient then TriggerClientEvent('rsg-prison:client:freedom', src) end
end

---------------------------------
-- sentence tick (every 10s; metadata only written when the minute changes)
---------------------------------
CreateThread(function()
    while true do
        Wait(10000)
        local now = os.time()
        for src, j in pairs(Jailed) do
            local Player = RSGCore.Functions.GetPlayer(src)
            if not Player then
                Jailed[src] = nil
            elseif (Player.PlayerData.metadata.injail or 0) <= 0 then
                release(src, Player, true, locale('dc_r_early')) -- e.g. lawman
            else
                local meta = Player.PlayerData.metadata.injail
                if meta ~= j.last then -- sentence changed externally (e.g. extended), rebase on it
                    PrisonLog('jail', locale('dc_t_changed'), src, { { locale('dc_f_from'), locale('dc_minutes', j.last) }, { locale('dc_f_to'), locale('dc_minutes', meta) } })
                    j.start, j.mins, j.last, j.total = now, meta, meta, meta * 60
                end
                local secsLeft = j.mins * 60 - (now - j.start)
                if secsLeft <= 0 then
                    release(src, Player, true)
                else
                    local remaining = math.ceil(secsLeft / 60) -- saved in whole minutes, rounded in the prisoner's favour
                    if remaining ~= j.last then
                        j.last = remaining
                        Player.Functions.SetMetaData('injail', remaining)
                    end
                    TriggerClientEvent('rsg-prison:client:updateTime', src, secsLeft, j.total)
                end
            end
        end
    end
end)

---------------------------------
-- start / resume sentence (on jailing and on reconnect)
---------------------------------
RegisterNetEvent('rsg-prison:server:startSentence', function()
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end
    local injail = Player.PlayerData.metadata.injail or 0
    if injail <= 0 then return end
    if Jailed[src] then
        -- re-jailed while serving: adopt the new sentence
        PrisonLog('jail', locale('dc_t_changed'), src, { { locale('dc_f_from'), locale('dc_minutes', Jailed[src].last) }, { locale('dc_f_to'), locale('dc_minutes', injail) } })
        Jailed[src] = { start = os.time(), mins = injail, last = injail, total = injail * 60 }
        TriggerClientEvent('rsg-prison:client:updateTime', src, injail * 60, injail * 60)
        return
    end

    Jailed[src] = { start = os.time(), mins = injail, last = injail, total = injail * 60 }
    TriggerClientEvent('rsg-prison:client:updateTime', src, injail * 60, injail * 60)

    local saved = Player.PlayerData.metadata.jailitems
    if saved and next(saved) then -- already holding items for this sentence (reconnect)
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
    TriggerClientEvent('rsg-prison:client:disarm', src)
    PrisonLog('jail', locale('dc_t_jailed'), src, { { locale('dc_f_sentence'), locale('dc_minutes', injail) }, { locale('dc_f_job_before'), Player.PlayerData.job.label or Player.PlayerData.job.name } })
    PrisonLog('items', locale('dc_t_items_seized'), src, { { locale('dc_f_stacks'), #items }, { locale('dc_f_items'), itemList(items), false } })

    -- after the snapshot: rsg-multijob awaits the database, and nothing may yield before the clear
    if Config.RemoveJob then removeAllJobs(src, Player) end

    if Config.JailAllowance > 0 then
        Player.Functions.AddMoney('cash', Config.JailAllowance, 'rsg-prison-jail-allowance')
    end
end)

---------------------------------
-- client reports release (lawman unjail / offline release); server re-checks
---------------------------------
RegisterNetEvent('rsg-prison:server:checkRelease', function()
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end
    if (Player.PlayerData.metadata.injail or 0) > 0 then return end
    local wasJailed = Jailed[src]
    Jailed[src] = nil
    if wasJailed then -- released early before the tick noticed (e.g. lawman /unjail)
        PrisonLog('release', locale('dc_t_released'), src, {
            { locale('dc_f_reason'), locale('dc_r_early') },
            { locale('dc_f_time_served'), locale('dc_minutes', math.floor((os.time() - wasJailed.start) / 60)) },
        })
        returnItems(src, Player)
    elseif returnItems(src, Player) then
        PrisonLog('release', locale('dc_t_released'), src, { { locale('dc_f_reason'), locale('dc_r_offline') } })
    end
end)

---------------------------------
-- escape attempts (client reports leaving the zone; logged only, the client returns them)
---------------------------------
RegisterNetEvent('rsg-prison:server:escapeAttempt', function()
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player or (Player.PlayerData.metadata.injail or 0) <= 0 then return end
    local now = os.time()
    if EscapeCooldown[src] and now - EscapeCooldown[src] < 30 then return end
    EscapeCooldown[src] = now
    PrisonLog('escape', locale('dc_t_escape'), src, { { locale('dc_f_remaining'), locale('dc_minutes', Player.PlayerData.metadata.injail) } })
end)

---------------------------------
-- guard rations (water / bread)
---------------------------------
RegisterNetEvent('rsg-prison:server:requestRation', function(kind)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    local item = type(kind) == 'string' and Config.GuardRations.items[kind]
    if not item then
        return PrisonLog('security', locale('dc_t_invalid_ration'), src, { { locale('dc_f_sent'), tostring(kind):sub(1, 64) } })
    end

    if (Player.PlayerData.metadata.injail or 0) <= 0 then
        PrisonLog('security', locale('dc_t_ration_not_jailed'), src, { { locale('dc_f_item'), item } })
        return notify(src, locale('sv_ration_not_jailed'), 'error')
    end

    local pcoords = GetEntityCoords(GetPlayerPed(src))
    local near = false
    for _, v in ipairs(Config.MenuLocations) do
        if #(pcoords - v.coords) <= Config.GuardRations.distance then near = true break end
    end
    if not near then
        return PrisonLog('security', locale('dc_t_ration_range'), src, { { locale('dc_f_item'), item }, { locale('dc_f_max_distance'), Config.GuardRations.distance } })
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

    if exports['rsg-inventory']:AddItem(src, item, 1, nil, nil, 'rsg-prison-guard-ration') then
        RationCooldown[src] = now
        TriggerClientEvent('rsg-inventory:client:ItemBox', src, RSGCore.Shared.Items[item], 'add', 1)
        notify(src, locale('sv_ration_given'), 'success')
        if ConfigDiscord.LogRations then PrisonLog('rations', locale('dc_t_ration_given'), src, { { locale('dc_f_item'), item } }) end
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
end)
