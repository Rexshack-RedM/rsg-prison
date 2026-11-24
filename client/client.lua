local RSGCore = exports['rsg-core']:GetCoreObject()

local inJail = false
local busy = false      -- entering / being returned: the zone check pauses while the player is moved
local watching = false  -- zone + ped watchers only run while jailed
local blips = {}

-- true while the local player is serving a sentence (metadata is server-set, so this is only used for UI such as target visibility)
function PrisonIsPrisoner()
    local pd = RSGCore.Functions.GetPlayerData()
    return pd and pd.metadata and (tonumber(pd.metadata.injail) or 0) > 0 or false
end

---------------------------------
-- blips
---------------------------------
for _, v in ipairs(Config.MenuLocations) do
    if v.showblip then
        local blip = BlipAddForCoords(1664425300, v.npccoords.x, v.npccoords.y, v.npccoords.z)
        SetBlipSprite(blip, joaat(Config.Blip.blipSprite), true)
        SetBlipScale(blip, Config.Blip.blipScale)
        SetBlipName(blip, locale('cl_blip_name'))
        blips[#blips + 1] = blip
    end
end

---------------------------------
-- countdown HUD (NUI, top left, never takes focus)
---------------------------------
local function showTimer(left, total)
    SendNUIMessage({
        action = 'jail:hud', left = left, total = total,
        title = locale('cl_hud_title'), sub = locale('cl_hud_sub'), ready = locale('cl_getting'),
    })
end

local function hideTimer()
    SendNUIMessage({ action = 'jail:hide' })
end

-- server is the only source of truth for remaining time (seconds)
RegisterNetEvent('rsg-prison:client:updateTime', function(secs, total)
    if not inJail then return end
    secs = tonumber(secs)
    if secs then showTimer(secs, tonumber(total)) end
end)

---------------------------------
-- weapons (rsg-weapons): unequip on entry, re-equip on release
---------------------------------
RegisterNetEvent('rsg-prison:client:disarm', function()
    if GetResourceState('rsg-weapons') == 'started' then
        for _, v in pairs(exports['rsg-weapons']:GetUsedWeapons() or {}) do
            if v.name then TriggerEvent('rsg-weapons:client:UseWeapon', { name = v.name }) end -- name only = unequip
        end
    end
    RemoveAllPedWeapons(PlayerPedId(), true, true)
    SetCurrentPedWeapon(PlayerPedId(), `WEAPON_UNARMED`, true, 0, false, false)
end)

RegisterNetEvent('rsg-prison:client:reequip', function(weapons, knives)
    if GetResourceState('rsg-weapons') ~= 'started' then return end
    CreateThread(function()
        Wait(3500) -- after the release fade + ApplySkin and the inventory sync
        for _, item in ipairs(type(weapons) == 'table' and weapons or {}) do
            TriggerEvent('rsg-weapons:client:UseWeapon', item)
            Wait(500)
        end
        for _, name in ipairs(type(knives) == 'table' and knives or {}) do
            TriggerEvent('rsg-weapons:client:UseEquipment', { name = name, info = {} })
            Wait(500)
        end
        Wait(500)
        Citizen.InvokeNative(0x94A3C1B804D291EC, PlayerPedId(), false, false, false, true) -- holster (same as rsg-weapons restore)
    end)
end)

---------------------------------
-- prison clothing
---------------------------------
local function applyPrisonClothes()
    local ped = PlayerPedId()
    for _, category in ipairs(Config.Clothing.remove) do
        RemoveShopItemFromPedByCategory(ped, category, true, true, true)
    end
    for _, item in ipairs(IsPedMale(ped) and Config.Clothing.male or Config.Clothing.female) do
        ApplyShopItemToPed(ped, item, true, true, true)
    end
    RemoveAllPedWeapons(ped, true, true)
end

-- re-apply after a respawn (rsg-medic revive) or anything that swaps the ped (ApplySkin, wardrobe)
local reapplying = false
local function reapplyPrisonClothes()
    if not inJail or reapplying then return end
    reapplying = true
    SetTimeout(2000, function() -- let the revive / skin load finish first
        reapplying = false
        if inJail and not IsEntityDead(PlayerPedId()) then applyPrisonClothes() end
    end)
end

AddEventHandler('rsg-medic:client:revive', reapplyPrisonClothes)

---------------------------------
-- prison zone (return escapees)
---------------------------------
-- moves the player back inside the walls (client-side nicety; the server checks the position too)
local function returnToPrison()
    if not inJail or busy then return end
    busy = true
    TriggerServerEvent('rsg-prison:server:escapeAttempt')
    RSGCore.Functions.Notify({ title = locale('cl_returning'), type = 'inform', icon = 'fa-solid fa-handcuffs', iconAnimation = 'shake', duration = 7000 })
    Wait(3000)
    if inJail then
        local pos = Config.Locations.escape
        DoScreenFadeOut(1000)
        Wait(1000)
        SetEntityCoords(PlayerPedId(), pos.x, pos.y, pos.z, false, false, false, false)
        SetEntityHeading(PlayerPedId(), pos.w)
        Wait(1000)
        DoScreenFadeIn(1000)
    end
    busy = false
end

-- the server noticed the prisoner outside the walls
RegisterNetEvent('rsg-prison:client:return', function()
    CreateThread(returnToPrison)
end)

-- one watcher thread while jailed: zone check (500 ms) and ped swap check (every 2nd pass)
local function startWatchers()
    if watching then return end
    watching = true
    CreateThread(function()
        local lastPed, pass = PlayerPedId(), 0
        while inJail do
            if Config.ReturnOnEscape and not busy and not PrisonZoneContains(GetEntityCoords(PlayerPedId())) then
                CreateThread(returnToPrison)
            end
            pass = pass + 1
            if pass % 2 == 0 then
                local ped = PlayerPedId()
                if ped ~= lastPed then -- ped swapped (ApplySkin, wardrobe)
                    lastPed = ped
                    reapplyPrisonClothes()
                end
            end
            Wait(500)
        end
        watching = false
    end)
end

---------------------------------
-- send to jail
-- resume = true when rejoining / restarted / adopted by the server: no teleport if already inside the walls
---------------------------------
RegisterNetEvent('rsg-prison:client:Enter', function(time, resume)
    time = tonumber(time)
    if not time or time <= 0 then return end

    -- already inside (sentence extended, or a repeat call): just resync with the server
    if inJail then
        return TriggerServerEvent('rsg-prison:server:startSentence')
    end

    inJail = true
    busy = true -- zone check waits until the player is in place
    TriggerServerEvent('rsg-prison:server:startSentence') -- server replies with updateTime for the HUD

    if not (resume and PrisonZoneContains(GetEntityCoords(PlayerPedId()))) then
        local spawn = Config.Locations.spawns[math.random(#Config.Locations.spawns)]
        DoScreenFadeOut(500)
        Wait(500)
        SetEntityCoords(PlayerPedId(), spawn.x, spawn.y, spawn.z - 0.9, false, false, false, false)
        SetEntityHeading(PlayerPedId(), spawn.w)
        Wait(500)
        DoScreenFadeIn(500)
    end

    applyPrisonClothes()
    busy = false
    startWatchers()
    if not resume then
        RSGCore.Functions.Notify({ title = locale('cl_property'), type = 'inform', icon = 'fa-solid fa-handcuffs', iconAnimation = 'shake', duration = 7000 })
    end
end)

---------------------------------
-- released (triggered by the server, or by a lawman /unjail)
---------------------------------
RegisterNetEvent('rsg-prison:client:freedom', function()
    if not inJail then return end
    inJail = false
    hideTimer()
    TriggerServerEvent('rsg-prison:server:checkRelease')

    DoScreenFadeOut(1000)
    Wait(1500)
    local pos = Config.Locations.outside
    local health = GetEntityHealth(PlayerPedId())
    SetEntityCoords(PlayerPedId(), pos.x, pos.y, pos.z, false, false, false, false)
    SetEntityHeading(PlayerPedId(), pos.w)
    exports['rsg-character']:ApplySkin()
    Wait(500)
    SetEntityHealth(PlayerPedId(), health) -- ApplySkin can replace the ped, so fetch it again
    DoScreenFadeIn(1000)

    RSGCore.Functions.Notify({ title = locale('cl_freedom'), description = locale('cl_free'), type = 'inform', icon = 'fa-solid fa-handcuffs', duration = 7000 })
    RSGCore.Functions.Notify({ title = locale('cl_property_returned'), description = locale('cl_property_has_been'), type = 'success', icon = 'fa-solid fa-box-open', duration = 7000 })
end)

---------------------------------
-- load / unload
---------------------------------
local function checkJailState()
    local PlayerData = RSGCore.Functions.GetPlayerData()
    local injail = PlayerData and PlayerData.metadata and PlayerData.metadata.injail or 0
    if injail > 0 then
        TriggerEvent('rsg-prison:client:Enter', injail, true)
    else
        -- recover items if released while offline (after rsg-weapons restores its own loadout)
        SetTimeout(8000, function() TriggerServerEvent('rsg-prison:server:checkRelease') end)
    end
end

RegisterNetEvent('RSGCore:Client:OnPlayerLoaded', checkJailState)

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    Wait(1000)
    if LocalPlayer.state.isLoggedIn then checkJailState() end
end)

RegisterNetEvent('RSGCore:Client:OnPlayerUnload', function()
    inJail = false
    hideTimer()
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    hideTimer()
    for _, blip in ipairs(blips) do RemoveBlip(blip) end
end)
