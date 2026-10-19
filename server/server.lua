local RSGCore = exports['rsg-core']:GetCoreObject()

--------------------------
-- server-side jail tracking (never trust client times)
--------------------------
local JailStart = {}   -- [src] = os.time() when the current sentence (or reconnect) began
local JailMins  = {}   -- [src] = sentence minutes at that point
local ReleasedAt = {}  -- [src] = os.time() of the last legitimate release

local function ServerRemaining(src)
    if not JailStart[src] then return nil end
    local elapsed = os.time() - JailStart[src]
    return JailMins[src] - math.floor(elapsed / 60)
end

AddEventHandler('playerDropped', function()
    local src = source
    JailStart[src], JailMins[src], ReleasedAt[src] = nil, nil, nil
end)

--------------------------
-- update jail sentance (client value ignored, server time used)
--------------------------
RegisterNetEvent('rsg-prison:server:updateSentance', function()
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end
    if (Player.PlayerData.metadata['injail'] or 0) <= 0 then return end
    local remaining = ServerRemaining(src)
    if not remaining then return end
    -- never let the stored sentence hit 0 here; only FreePlayer releases
    Player.Functions.SetMetaData('injail', math.max(1, remaining))
end)

--------------------------
-- remove player job
--------------------------
RegisterNetEvent('rsg-prison:server:RemovePlayerJob', function()
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end
    if (Player.PlayerData.metadata['injail'] or 0) <= 0 then return end
    if Player.PlayerData.job.name ~= 'unemployed' and Config.RemoveJob == true then
        Player.Functions.SetJob('unemployed')
    end
end)

--------------------------
-- free player (only once the server-side sentence is served,
-- or a lawman has already set injail to 0 via /unjail)
--------------------------
RegisterNetEvent('rsg-prison:server:FreePlayer', function()
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end
    if (Player.PlayerData.metadata['injail'] or 0) > 0 then
        local remaining = ServerRemaining(src)
        -- 30s tolerance for client timer drift
        if not remaining or (os.time() - JailStart[src]) < (JailMins[src] * 60 - 30) then return end
    end
    Player.Functions.SetMetaData('injail', 0)
    JailStart[src], JailMins[src] = nil, nil
    ReleasedAt[src] = os.time()
end)

--------------------------
-- save inventory items (only while actually jailed)
--------------------------
RegisterNetEvent('rsg-prison:server:SaveJailItems', function()
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end
    local injail = Player.PlayerData.metadata['injail'] or 0
    if injail <= 0 then return end

    -- start / resume the server-side timer (also runs on reconnect)
    JailStart[src], JailMins[src] = os.time(), injail

    local saved = Player.PlayerData.metadata['jailitems']
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
    Player.Functions.AddMoney('cash', 10, 'rsg-prison-jail-allowance')
end)

--------------------------
-- give back inventory items (only after release, only once)
--------------------------
RegisterNetEvent('rsg-prison:server:GiveJailItems', function()
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end
    if (Player.PlayerData.metadata['injail'] or 0) > 0 then return end

    local items = Player.PlayerData.metadata['jailitems']
    if not items or not next(items) then return end

    -- wipe the record first so a repeat/spam call has nothing to hand out
    Player.Functions.SetMetaData('jailitems', {})
    Player.Functions.ClearInventory()
    for _, v in pairs(items) do
        if v.name and RSGCore.Shared.Items[v.name] and tonumber(v.amount) and v.amount > 0 then
            exports['rsg-inventory']:AddItem(src, v.name, v.amount, v.info, nil, 'rsg-prison-return-items')
        end
    end
end)

--------------------------
-- set criminal record
--------------------------
RegisterNetEvent('rsg-prison:server:CheckRecordStatus', function()
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end
    local CriminalRecord = Player.PlayerData.metadata['criminalrecord']
    local currentDate = os.date('*t')
    if (CriminalRecord['date'].month + 1) == 13 then
        CriminalRecord['date'].month = 0
    end
    if CriminalRecord['hasRecord'] then
        if currentDate.month == (CriminalRecord['date'].month + 1) or currentDate.day == (CriminalRecord['date'].day - 1) then
            CriminalRecord['hasRecord'] = false
            CriminalRecord['date'] = nil
        end
    end
end)

RegisterNetEvent('rsg-prison:server:resetoutlawstatus', function()
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end
    -- only straight after a legitimate release, once
    if not ReleasedAt[src] or os.time() - ReleasedAt[src] > 30 then return end
    ReleasedAt[src] = nil
    local citizenid = Player.PlayerData.citizenid
    MySQL.update('UPDATE players SET outlawstatus = ? WHERE citizenid = ?', { 0, citizenid })
end)
