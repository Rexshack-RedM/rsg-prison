local RSGCore = exports['rsg-core']:GetCoreObject()
local jailtimeMinsRemaining = 0
local inJail = false
local inJailZone = false
local jailTime = 0
local Zones = {}

--------------------------
-- prompts
--------------------------
CreateThread(function()
    for prison, v in pairs(Config.MenuLocations) do
        exports['rsg-core']:createPrompt(v.prompt, v.coords, RSGCore.Shared.Keybinds[Config.Keybind], Lang:t('client.lang_1') .. v.name, {
            type = 'client',
            event = 'rsg-prison:client:menu',
        })
        if v.showblip == true then
            local PrisonBlip = BlipAddForCoords(1664425300, v.coords)
            SetBlipSprite(PrisonBlip, GetHashKey(Config.Blip.blipSprite), true)
            SetBlipScale(PrisonBlip, Config.Blip.blipScale)
            SetBlipName(PrisonBlip, Config.Blip.blipName)
        end
    end
end)

--------------------------
-- draw marker if set to true in config
--------------------------
CreateThread(function()
    while true do
        Wait(1)
        inRange = false
        local pos = GetEntityCoords(cache.ped)
        for prison, v in pairs(Config.MenuLocations) do
            if #(pos - v.coords) < Config.MarkerDistance then
                inRange = true
                if v.showmarker == true then
                    DrawMarker(0x07DCE236, v.coords, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 255, 215, 0, 155, false, false, false, 1, false, false, false)
                end
            end
            if not inRange then
                Wait(2500)
            end
        end
    end
end)

--------------------------
-- Prison Zone
--------------------------
CreateThread(function()
    for k = 1, #Config.PrisonZone do
        Zones[k] = PolyZone:Create(Config.PrisonZone[k].zones,
        {
            name = Config.PrisonZone[k].name,
            minZ = Config.PrisonZone[k].minz,
            maxZ = Config.PrisonZone[k].maxz,
            debugPoly = false
        })

        Zones[k]:onPlayerInOut(function(isPointInside)
            if not isPointInside then
                inJailZone = false
                return
            end

            inJailZone = true
        end)
    end
end)

--------------------------
-- Prison Zone Loop
--------------------------
CreateThread(function()
    while true do
        local isJailed = 0
        local teleport = vector3(3368.31, -665.94, 46.29)

        if LocalPlayer.state['isLoggedIn'] then
            RSGCore.Functions.GetPlayerData(function(PlayerData)
                isJailed = PlayerData.metadata["injail"]
            end)
        end

        if isJailed <= 0 then goto continue end
        if inJailZone then goto continue end
        lib.notify(
            { 
                title = Lang:t('client.lang_2'), 
                type = 'inform',
                icon = 'fa-solid fa-handcuffs',
                iconAnimation = 'shake',
                duration = 7000
            }
        )
        Wait(3000)
        DoScreenFadeOut(1000)
        Wait(1000)
        SetEntityCoords(cache.ped, teleport)
        Wait(1000)
        DoScreenFadeIn(1000)

        ::continue::

        Wait(10000)
    end
end)

--------------------------
-- prison menu
--------------------------

RegisterNetEvent('rsg-prison:client:menu', function()
    lib.registerContext(
        {
            id = 'prison_menu',
            title = Lang:t('client.lang_3'),
            position = 'top-right',
            options = {
                {
                    title = Lang:t('client.lang_4'),
                    description = Lang:t('client.lang_5'),
                    icon = 'fas fa-shopping-basket',
                    event = 'rsg-prison:client:shop'
                },
                {
                    title = Lang:t('client.lang_6'),
                    description = Lang:t('client.lang_7'),
                    icon = 'far fa-envelope-open',
                    event = 'rsg-prison:client:telegrammenu'
                },
            }
        }
    )
    lib.showContext('prison_menu')
end)

--------------------------
-- prison telegram
--------------------------
RegisterNetEvent('rsg-prison:client:telegrammenu', function()
    lib.registerContext(
        {
            id = 'telegram_menu',
            title = Lang:t('client.lang_8'),
            position = 'top-right',
            menu = 'prison_menu',
            onBack = function() end,
            options = {
                {
                    title = Lang:t('client.lang_9'),
                    description = Lang:t('client.lang_10'),
                    icon = 'far fa-envelope-open',
                    event = 'rsg-telegram:client:ReadMessages'
                },
                {
                    title = Lang:t('client.lang_11'),
                    description = Lang:t('client.lang_12'),
                    icon = 'far fa-envelope-open',
                    event = 'rsg-telegram:client:WriteMessagePostOffice'
                },
            }
        }
    )
    lib.showContext('telegram_menu')
end)

--------------------------
-- prison shop
--------------------------
RegisterNetEvent('rsg-prison:client:shop')
AddEventHandler('rsg-prison:client:shop', function()
    local ShopItems = {}
    ShopItems.label = "Prison Shop"
    ShopItems.items = Config.PrisonShop
    ShopItems.slots = #Config.PrisonShop
    TriggerServerEvent("inventory:server:OpenInventory", "shop", "PrisonShop_"..math.random(1, 99), ShopItems)
end)

--------------------------
-- check onload player
--------------------------
RegisterNetEvent('RSGCore:Client:OnPlayerLoaded', function()
    RSGCore.Functions.GetPlayerData(function(PlayerData)
        if PlayerData.metadata["injail"] > 0 then
            TriggerEvent("rsg-prison:client:Enter", PlayerData.metadata["injail"])
        end
    end)
end)

--------------------------
-- on resource start
--------------------------
AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    Wait(100)
    if LocalPlayer.state['isLoggedIn'] then
        RSGCore.Functions.GetPlayerData(function(PlayerData)
            if PlayerData.metadata["injail"] > 0 then
                TriggerEvent("rsg-prison:client:Enter", PlayerData.metadata["injail"])
            end
        end)
    end
end)

RegisterNetEvent('RSGCore:Client:OnPlayerUnload', function()
    inJail = false
end)

--------------------------
-- send to jail
--------------------------
RegisterNetEvent('rsg-prison:client:Enter', function(time)
    jailTime = time -- in mins
    local RandomStartPosition = Config.Locations.spawns[math.random(1, #Config.Locations.spawns)]
    SetEntityCoords(cache.ped, RandomStartPosition.coords.x, RandomStartPosition.coords.y, RandomStartPosition.coords.z - 0.9, 0, 0, 0, false)
    SetEntityHeading(cache.ped, RandomStartPosition.coords.w)
    Wait(500)
    TriggerServerEvent('rsg-prison:server:SaveJailItems')
    lib.notify(
        { 
            title = Lang:t('client.lang_13'), 
            type = 'inform',
            icon = 'fa-solid fa-handcuffs',
            iconAnimation = 'shake',
            duration = 7000
        }
    )
    TriggerEvent('rsg-prison:client:prisonclothes')
    TriggerServerEvent('rsg-prison:server:RemovePlayerJob')
    TriggerServerEvent('InteractSound_SV:PlayWithinDistance', 5, 'jail', 0.6)
    inJail = true
    handleJailtime()
end)

--------------------------
-- set prison clothing
--------------------------
RegisterNetEvent("rsg-prison:client:prisonclothes") -- prison outfit event
AddEventHandler("rsg-prison:client:prisonclothes", function()
    RemoveShopItemFromPedByCategory(cache.ped, 0x9925C067, true, true, true)
    RemoveShopItemFromPedByCategory(cache.ped, 0x485EE834, true, true, true)
    RemoveShopItemFromPedByCategory(cache.ped, 0x18729F39, true, true, true)
    RemoveShopItemFromPedByCategory(cache.ped, 0x3107499B, true, true, true)
    RemoveShopItemFromPedByCategory(cache.ped, 0x3C1A74CD, true, true, true)
    RemoveShopItemFromPedByCategory(cache.ped, 0x3F1F01E5, true, true, true)
    RemoveShopItemFromPedByCategory(cache.ped, 0x3F7F3587, true, true, true)
    RemoveShopItemFromPedByCategory(cache.ped, 0x49C89D9B, true, true, true)
    RemoveShopItemFromPedByCategory(cache.ped, 0x4A73515C, true, true, true)
    RemoveShopItemFromPedByCategory(cache.ped, 0x514ADCEA, true, true, true)
    RemoveShopItemFromPedByCategory(cache.ped, 0x5FC29285, true, true, true)
    RemoveShopItemFromPedByCategory(cache.ped, 0x79D7DF96, true, true, true)
    RemoveShopItemFromPedByCategory(cache.ped, 0x7A96FACA, true, true, true)
    RemoveShopItemFromPedByCategory(cache.ped, 0x877A2CF7, true, true, true)
    RemoveShopItemFromPedByCategory(cache.ped, 0x9B2C8B89, true, true, true)
    RemoveShopItemFromPedByCategory(cache.ped, 0xA6D134C6, true, true, true)
    RemoveShopItemFromPedByCategory(cache.ped, 0xE06D30CE, true, true, true)
    RemoveShopItemFromPedByCategory(cache.ped, 0x662AC34,  true, true, true)
    RemoveShopItemFromPedByCategory(cache.ped, 0xAF14310B, true, true, true)
    RemoveShopItemFromPedByCategory(cache.ped, 0x72E6EF74, true, true, true)
    RemoveShopItemFromPedByCategory(cache.ped, 0xEABE0032, true, true, true)
    RemoveShopItemFromPedByCategory(cache.ped, 0x2026C46D, true, true, true)
    RemoveShopItemFromPedByCategory(cache.ped, 0xB6B6122D, true, true, true)
    RemoveShopItemFromPedByCategory(cache.ped, 0xB9E2FA01, true, true, true)

    if IsPedMale(cache.ped) then
        ApplyShopItemToPed(cache.ped, 0x5BA76CCF, true, true, true)
        ApplyShopItemToPed(cache.ped, 0x216612F0, true, true, true)
        ApplyShopItemToPed(cache.ped, 0x1CCEE58D, true, true, true)
    else
        ApplyShopItemToPed(cache.ped, 0x6AB27695, true, true, true)
        ApplyShopItemToPed(cache.ped, 0x75BC0CF5, true, true, true)
        ApplyShopItemToPed(cache.ped, 0x14683CDF, true, true, true)
    end
    RemoveAllPedWeapons(cache.ped, true, true)
end)

--------------------------
-- jail timer
--------------------------
function handleJailtime()
    jailtimeMinsRemaining = jailTime
    CreateThread(function()
        while jailtimeMinsRemaining > 0 do
            Wait(1000 * 60)
            jailtimeMinsRemaining = jailtimeMinsRemaining - 1
            if jailtimeMinsRemaining > 0 then
                if jailtimeMinsRemaining > 1 then
                    exports['rsg-core']:DrawText(Lang:t('client.lang_14')..jailtimeMinsRemaining..Lang:t('client.lang_15'), 'left')
                    TriggerServerEvent('rsg-prison:server:updateSentance', jailtimeMinsRemaining)
                else
                    exports['rsg-core']:DrawText(Lang:t('client.lang_16'), 'left')
                    TriggerServerEvent('rsg-prison:server:updateSentance', jailtimeMinsRemaining)
                end
            else
                exports['rsg-core']:HideText()
                TriggerEvent('rsg-prison:client:freedom')
            end
        end
    end)
end

--------------------------
-- released from jail
--------------------------
RegisterNetEvent('rsg-prison:client:freedom', function()
    TriggerServerEvent('rsg-prison:server:FreePlayer')
    TriggerServerEvent('rsg-prison:server:GiveJailItems')
    TriggerServerEvent('RSGCore:Server:SetMetaData', 'outlawstatus', 0)
    Wait(500)
    DoScreenFadeOut(1000)
    Wait(3000)
    SetEntityCoords(cache.ped, Config.Locations["outside"].coords.x, Config.Locations["outside"].coords.y, Config.Locations["outside"].coords.z, 0, 0, 0, false)
    SetEntityHeading(cache.ped, Config.Locations["outside"].coords.w)
    local currentHealth = GetEntityHealth(cache.ped)
    local maxStamina = GetPedMaxStamina(cache.ped, Citizen.ResultAsFloat())
    local currentStamina = GetPedStamina(cache.ped, Citizen.ResultAsFloat()) / maxStamina * 100
    ExecuteCommand('loadskin')
    Wait(1000)
    SetEntityHealth(cache.ped, currentHealth )
    ChangePedStamina(cache.ped, currentStamina)
    DoScreenFadeIn(1000)
    lib.notify(
        { 
            title = Lang:t('client.lang_17'), 
            description = Lang:t('client.lang_18'),
            type = 'inform',
            icon = 'fa-solid fa-handcuffs',
            iconAnimation = 'shake',
            duration = 7000
        }
    )
    Wait(7000)
    lib.notify(
        { 
            title = Lang:t('client.lang_19'), 
            description = Lang:t('client.lang_20'),
            type = 'inform',
            icon = 'fa-solid fa-handcuffs',
            iconAnimation = 'shake',
            duration = 7000
        }
    )
    inJail = false
end)
