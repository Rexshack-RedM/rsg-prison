local RSGCore = exports['rsg-core']:GetCoreObject()
lib.locale()

---------------------------------
-- server-side sentence tracking (client never decides time)
---------------------------------
local Jailed = {}         -- [src] = { start = os.time(), mins = sentence at start }
local RationCooldown = {}

local function notify(src, desc, ntype)
    TriggerClientEvent('ox_lib:notify', src, { title = locale('sv_ration_title'), description = desc, type = ntype })
end

local function returnItems(src, Player)
    local items = Player.PlayerData.metadata.jailitems
    if not items or not next(items) then return false end

    -- wipe the record first so nothing can be handed out twice
    Player.Functions.SetMetaData('jailitems', {})
    Player.Functions.ClearInventory() -- remove prison rations
    for _, v in pairs(items) do
        local amount = tonumber(v.amount)
        if v.name and RSGCore.Shared.Items[v.name] and amount and amount > 0 then
            exports['rsg-inventory']:AddItem(src, v.name, amount, v.info, nil, 'rsg-prison-return-items')
        end
    end
    MySQL.update('UPDATE players SET outlawstatus = ? WHERE citizenid = ?', { 0, Player.PlayerData.citizenid })
    return true
end

local function release(src, Player, tellClient)
    Jailed[src] = nil
    Player.Functions.SetMetaData('injail', 0)
    returnItems(src, Player)
    if tellClient then TriggerClientEvent('rsg-prison:client:freedom', src) end
end

---------------------------------
-- sentence tick (once a minute)
---------------------------------
CreateThread(function()
    while true do
        Wait(60000)
        local now = os.time()
        for src, j in pairs(Jailed) do
            local Player = RSGCore.Functions.GetPlayer(src)
            if not Player then
                Jailed[src] = nil
            elseif (Player.PlayerData.metadata.injail or 0) <= 0 then
                release(src, Player, true) -- released externally (e.g. lawman)
            else
                local remaining = j.mins - math.floor((now - j.start) / 60)
                if remaining <= 0 then
                    release(src, Player, true)
                else
                    Player.Functions.SetMetaData('injail', remaining)
                    TriggerClientEvent('rsg-prison:client:updateTime', src, remaining)
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
    if injail <= 0 or Jailed[src] then return end

    Jailed[src] = { start = os.time(), mins = injail }
    TriggerClientEvent('rsg-prison:client:updateTime', src, injail)

    if Config.RemoveJob and Player.PlayerData.job.name ~= 'unemployed' then
        Player.Functions.SetJob('unemployed', 0)
    end

    local saved = Player.PlayerData.metadata.jailitems
    if saved and next(saved) then return end -- already holding items for this sentence

    -- snapshot and clear in the same tick so nothing can be moved out first
    local items = {}
    for slot, v in pairs(Player.PlayerData.items or {}) do
        if v and v.name and v.amount and v.amount > 0 then
            items[#items + 1] = { name = v.name, amount = v.amount, info = v.info, slot = v.slot or slot }
        end
    end
    Player.Functions.ClearInventory()
    Player.Functions.SetMetaData('jailitems', items)

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
    Jailed[src] = nil
    returnItems(src, Player)
end)

---------------------------------
-- guard rations (water / bread)
---------------------------------
RegisterNetEvent('rsg-prison:server:requestRation', function(kind)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    local item = type(kind) == 'string' and Config.GuardRations.items[kind]
    if not item then return end

    if (Player.PlayerData.metadata.injail or 0) <= 0 then
        return notify(src, locale('sv_ration_not_jailed'), 'error')
    end

    local pcoords = GetEntityCoords(GetPlayerPed(src))
    local near = false
    for _, v in ipairs(Config.MenuLocations) do
        if #(pcoords - v.coords) <= Config.GuardRations.distance then near = true break end
    end
    if not near then return end

    local now = os.time()
    if RationCooldown[src] and now - RationCooldown[src] < Config.GuardRations.cooldown then
        return notify(src, locale('sv_ration_wait'), 'error')
    end
    RationCooldown[src] = now

    if (exports['rsg-inventory']:GetItemCount(src, item) or 0) >= Config.GuardRations.max then
        return notify(src, locale('sv_ration_max', Config.GuardRations.max), 'error')
    end

    if not exports['rsg-inventory']:CanAddItem(src, item, 1) then
        return notify(src, locale('sv_ration_full'), 'error')
    end

    if exports['rsg-inventory']:AddItem(src, item, 1, nil, nil, 'rsg-prison-guard-ration') then
        TriggerClientEvent('rsg-inventory:client:ItemBox', src, RSGCore.Shared.Items[item], 'add', 1)
        notify(src, locale('sv_ration_given'), 'success')
    end
end)

---------------------------------
-- cleanup
---------------------------------
AddEventHandler('playerDropped', function()
    local src = source
    Jailed[src] = nil
    RationCooldown[src] = nil
end)
