local RSGCore = exports['rsg-core']:GetCoreObject()

local inJail = false
local blips = {}

---------------------------------
-- blips
---------------------------------
CreateThread(function()
    for _, v in ipairs(Config.MenuLocations) do
        if v.showblip then
            local blip = BlipAddForCoords(1664425300, v.coords.x, v.coords.y, v.coords.z)
            SetBlipSprite(blip, joaat(Config.Blip.blipSprite), true)
            SetBlipScale(blip, Config.Blip.blipScale)
            SetBlipName(blip, locale('cl_blip_name'))
            blips[#blips + 1] = blip
        end
    end
end)

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
-- prison zone (return escapees)
---------------------------------
local returning = false
local function insidePrison(pos)
    local pts, inside = Config.PrisonZone.points, false
    local half = Config.PrisonZone.thickness / 2
    if math.abs(pos.z - pts[1].z) > half then return false end
    local j = #pts
    for i = 1, #pts do
        local a, b = pts[i], pts[j]
        if ((a.y > pos.y) ~= (b.y > pos.y)) and (pos.x < (b.x - a.x) * (pos.y - a.y) / (b.y - a.y) + a.x) then
            inside = not inside
        end
        j = i
    end
    return inside
end

local function onPrisonExit()
    if not inJail or returning then return end
    returning = true
    TriggerServerEvent('rsg-prison:server:escapeAttempt')
    CreateThread(function()
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
        returning = false
    end)
end

if Config.ReturnOnEscape then
    -- plain Lua poly zone (replaces lib.zones.poly; no rsg-core zones yet)
    CreateThread(function()
        local wasInside = false
        while true do
            if inJail then
                local now = insidePrison(GetEntityCoords(PlayerPedId()))
                if wasInside and not now then onPrisonExit() end
                wasInside = now
                Wait(500)
            else
                wasInside = false
                Wait(2000)
            end
        end
    end)
end

---------------------------------
-- guard menu
---------------------------------
local function requestRation(kind)
    TriggerServerEvent('rsg-prison:server:requestRation', kind)
end

RegisterNetEvent('rsg-prison:client:requestRation', function(kind)
    if not inJail then return end
    requestRation(kind)
end)

---------------------------------
-- prison clothing
---------------------------------
local removeCategories = {
    0x9925C067, 0x485EE834, 0x18729F39, 0x3107499B, 0x3C1A74CD, 0x3F1F01E5, 0x3F7F3587, 0x49C89D9B,
    0x4A73515C, 0x514ADCEA, 0x5FC29285, 0x79D7DF96, 0x7A96FACA, 0x877A2CF7, 0x9B2C8B89, 0xA6D134C6,
    0xE06D30CE, 0x0662AC34, 0xAF14310B, 0x72E6EF74, 0xEABE0032, 0x2026C46D, 0xB6B6122D, 0xB9E2FA01,
}
local outfitMale   = { 0x5BA76CCF, 0x216612F0, 0x1CCEE58D }
local outfitFemale = { 0x6AB27695, 0x75BC0CF5, 0x14683CDF }

local function applyPrisonClothes()
    local ped = PlayerPedId()
    for i = 1, #removeCategories do
        RemoveShopItemFromPedByCategory(ped, removeCategories[i], true, true, true)
    end
    for _, item in ipairs(IsPedMale(ped) and outfitMale or outfitFemale) do
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
-- watch for ped swaps (replaces lib.onCache('ped'))
CreateThread(function()
    local last = PlayerPedId()
    while true do
        Wait(1000)
        local ped = PlayerPedId()
        if ped ~= last then
            last = ped
            reapplyPrisonClothes()
        end
    end
end)

---------------------------------
-- send to jail
---------------------------------
RegisterNetEvent('rsg-prison:client:Enter', function(time)
    time = tonumber(time)
    if not time or time <= 0 then return end

    -- already inside (sentence extended): just resync with the server
    if inJail then
        return TriggerServerEvent('rsg-prison:server:startSentence')
    end

    local spawn = Config.Locations.spawns[math.random(#Config.Locations.spawns)]
    DoScreenFadeOut(500)
    Wait(500)
    SetEntityCoords(PlayerPedId(), spawn.x, spawn.y, spawn.z - 0.9, false, false, false, false)
    SetEntityHeading(PlayerPedId(), spawn.w)
    Wait(500)
    DoScreenFadeIn(500)

    inJail = true
    TriggerServerEvent('rsg-prison:server:startSentence') -- server replies with updateTime for the HUD
    applyPrisonClothes()
    RSGCore.Functions.Notify({ title = locale('cl_property'), type = 'inform', icon = 'fa-solid fa-handcuffs', iconAnimation = 'shake', duration = 7000 })
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
        TriggerEvent('rsg-prison:client:Enter', injail)
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
