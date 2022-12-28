local RSGCore = exports['rsg-core']:GetCoreObject()
local jailtimeSecondsRemaining = 0
local inJail = false
local jailTime = 0

-----------------------------------------------------------------------------------

-- prompts
Citizen.CreateThread(function()
    for trapper, v in pairs(Config.MenuLocations) do
        exports['rsg-core']:createPrompt(v.prompt, v.coords, RSGCore.Shared.Keybinds['J'], 'Open ' .. v.name, {
            type = 'client',
            event = 'rsg-prison:client:menu',
            args = {},
        })
        if v.showblip == true then
            local PrisonBlip = Citizen.InvokeNative(0x554D9D53F696D002, 1664425300, v.coords)
            SetBlipSprite(PrisonBlip, GetHashKey(Config.Blip.blipSprite), true)
            SetBlipScale(PrisonBlip, Config.Blip.blipScale)
            Citizen.InvokeNative(0x9CB1A1623062F402, PrisonBlip, Config.Blip.blipName)
        end
    end
end)

-- draw marker if set to true in config
CreateThread(function()
    while true do
        local sleep = 0
        for trapper, v in pairs(Config.MenuLocations) do
            if v.showmarker == true then
                Citizen.InvokeNative(0x2A32FAA57B937173, 0x07DCE236, v.coords, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 255, 215, 0, 155, false, false, false, 1, false, false, false)
            end
        end
        Wait(sleep)
    end
end)

-- prison menu
RegisterNetEvent('rsg-prison:client:menu', function()
    exports['rsg-menu']:openMenu({
        {
            header = "Prison Menu",
            isMenuHeader = true,
        },
        {
            header = "Prison Shop",
            icon = "fas fa-shopping-basket",
            txt = "keep yourself alive",
            params = { 
                event = 'rsg-prison:client:shop',
                isServer = false,
                args = {}
            }
        },
        {
            header = "Post Office",
            icon = "far fa-envelope-open",
            txt = "keep in touch with loved ones",
            params = { 
                event = 'rsg-prison:client:telegrammenu',
                isServer = false,
                args = {}
            }
        },
        {
            header = "Close Menu",
            txt = '',
            params = {
                event = 'rsg-menu:closeMenu',
            }
        },
    })
end)

-- telegram menu
RegisterNetEvent('rsg-prison:client:telegrammenu', function(data)
    exports['rsg-menu']:openMenu({
        {
            header = "| Telegram Menu |",
            isMenuHeader = true,
        },
        {
            header = "📥 | Read Messages",
            txt = "read your telegram messages",
            params = {
                event = 'rsg-telegram:client:readmessages',
                isServer = false,
                args = {}
            }
        },
        {
            header = "📤 | Send Telegram",
            txt = "send a telegram to another player",
            params = {
                event = 'rsg-telegram:client:writemessage',
                isServer = false,
                args = {}
            }
        },
        {
            header = "<<< Back",
            txt = '',
            params = {
                event = 'rsg-prison:client:menu',
            }
        },
    })
end)

-----------------------------------------------------------------------------------

-- prison shop
RegisterNetEvent('rsg-prison:client:shop')
AddEventHandler('rsg-prison:client:shop', function()
    local ShopItems = {}
    ShopItems.label = "Prison Shop"
    ShopItems.items = Config.PrisonShop
    ShopItems.slots = #Config.PrisonShop
    TriggerServerEvent("inventory:server:OpenInventory", "shop", "PrisonShop_"..math.random(1, 99), ShopItems)
end)

-----------------------------------------------------------------------------------

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    RSGCore.Functions.GetPlayerData(function(PlayerData)
        if PlayerData.metadata["injail"] > 0 then
            TriggerEvent("rsg-prison:client:Enter", PlayerData.metadata["injail"])
        end
    end)
end)

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

-----------------------------------------------------------------------------------

-- sent to jail
RegisterNetEvent('rsg-prison:client:Enter', function(time)
    jailTime = (60 * time) -- in seconds
    local RandomStartPosition = Config.Locations.spawns[math.random(1, #Config.Locations.spawns)]
    SetEntityCoords(PlayerPedId(), RandomStartPosition.coords.x, RandomStartPosition.coords.y, RandomStartPosition.coords.z - 0.9, 0, 0, 0, false)
    SetEntityHeading(PlayerPedId(), RandomStartPosition.coords.w)
    Wait(500)
    RSGCore.Functions.Notify('Prison Sentence '..jailTime..' Seconds', 'primary')
    Wait(5000)
    RSGCore.Functions.Notify('Your property has been seized', 'primary')
    inJail = true
    handleJailtime()
end)

-----------------------------------------------------------------------------------

-- jail timer
function handleJailtime()
    jailtimeSecondsRemaining = jailTime
    Citizen.CreateThread(function()
        while jailtimeSecondsRemaining > 0 do
            Wait(1000)
            jailtimeSecondsRemaining = jailtimeSecondsRemaining - 1
            if jailtimeSecondsRemaining > 0 then
                exports['rsg-core']:DrawText('Free in '..jailtimeSecondsRemaining..' seconds!', 'left')
            else
                exports['rsg-core']:HideText()
                TriggerEvent('rsg-prison:client:freedom')
            end
        end
    end)
end

-----------------------------------------------------------------------------------

-- released from jail
RegisterNetEvent('rsg-prison:client:freedom', function()
    TriggerServerEvent('rsg-prison:server:UpdatePlayer')
    TriggerServerEvent('rsg-prison:server:GiveJailItems')
    SetEntityCoords(PlayerPedId(), Config.Locations["outside"].coords.x, Config.Locations["outside"].coords.y, Config.Locations["outside"].coords.z, 0, 0, 0, false)
    SetEntityHeading(PlayerPedId(), Config.Locations["outside"].coords.w)
    Wait(500)
    RSGCore.Functions.Notify('You\'re free from prison, good luck', 'primary')
    Wait(5000)
    RSGCore.Functions.Notify('You received your property back', 'primary')
    inJail = false
end)

-----------------------------------------------------------------------------------
