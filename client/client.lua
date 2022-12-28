local RSGCore = exports['rsg-core']:GetCoreObject()
local jailtimeSecondsRemaining = 0
local inJail = false
local jailTime = 0

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
