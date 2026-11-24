local RSGCore = exports['rsg-core']:GetCoreObject()
local guards = {}

-- belongings that did not fit on release (set by the server, readable client side)
local function hasOwedProperty()
    local pd = RSGCore.Functions.GetPlayerData()
    local owed = pd and pd.metadata and pd.metadata.jailowed
    return type(owed) == 'table' and next(owed) ~= nil
end

local optionNames = {}
local function guardOptions()
    optionNames = { 'rsg_prison_water', 'rsg_prison_bread' }
    local options = {
        {
            name = 'rsg_prison_water',
            icon = 'fas fa-tint',
            label = locale('cl_request_water'),
            distance = 2.0,
            canInteract = PrisonIsPrisoner, -- the ration options only show for prisoners
            onSelect = function() TriggerServerEvent('rsg-prison:server:requestRation', 'water') end
        },
        {
            name = 'rsg_prison_bread',
            icon = 'fas fa-bread-slice',
            label = locale('cl_request_bread'),
            distance = 2.0,
            canInteract = PrisonIsPrisoner,
            onSelect = function() TriggerServerEvent('rsg-prison:server:requestRation', 'bread') end
        },
    }
    if Config.Bail.enabled then
        options[#options + 1] = {
            name = 'rsg_prison_bail',
            icon = 'fas fa-coins',
            label = locale('cl_request_bail'),
            distance = 2.0,
            canInteract = PrisonIsPrisoner,
            onSelect = function() TriggerServerEvent('rsg-prison:server:requestBail') end
        }
        optionNames[#optionNames + 1] = 'rsg_prison_bail'
    end
    if Config.CollectProperty then
        options[#options + 1] = {
            name = 'rsg_prison_collect',
            icon = 'fas fa-box-open',
            label = locale('cl_collect_property'),
            distance = 2.0,
            canInteract = function() return not PrisonIsPrisoner() and hasOwedProperty() end,
            onSelect = function() TriggerServerEvent('rsg-prison:server:collectProperty') end
        }
        optionNames[#optionNames + 1] = 'rsg_prison_collect'
    end
    return options
end

local function spawnGuard(model, coords)
    if not RSGCore.Functions.RequestModel(model, 10000) then return end
    local ped = CreatePed(model, coords.x, coords.y, coords.z - 1.0, coords.w, false, false, false, false)
    SetModelAsNoLongerNeeded(model)
    SetEntityAlpha(ped, Config.FadeIn and 0 or 255, false)
    SetRandomOutfitVariation(ped, true)
    SetEntityCanBeDamaged(ped, false)
    SetEntityInvincible(ped, true)
    FreezeEntityPosition(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedCanBeTargetted(ped, false)

    exports['rsg-target']:addLocalEntity(ped, guardOptions())

    if Config.FadeIn then
        for i = 0, 255, 51 do
            Wait(50)
            SetEntityAlpha(ped, i, false)
        end
    end
    return ped
end

local function removeGuard(ped, fade)
    if not ped or not DoesEntityExist(ped) then return end
    exports['rsg-target']:removeLocalEntity(ped, optionNames)
    if fade and Config.FadeIn then
        for i = 255, 0, -51 do
            Wait(50)
            SetEntityAlpha(ped, i, false)
        end
    end
    DeleteEntity(ped)
end

for k, v in ipairs(Config.MenuLocations) do
    local point = points.new({ coords = v.npccoords.xyz, distance = Config.DistanceSpawn })

    function point:onEnter()
        self.inside = true
        if self.ped or self.spawning then return end
        self.spawning = true
        CreateThread(function()
            local ped = spawnGuard(v.npcmodel, v.npccoords)
            self.spawning = false
            if not self.inside then
                return removeGuard(ped, false) -- walked away while loading
            end
            self.ped = ped
        end)
    end

    function point:onExit()
        self.inside = false
        local ped = self.ped
        self.ped = nil
        if ped then CreateThread(function() removeGuard(ped, true) end) end
    end

    guards[k] = point
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, point in pairs(guards) do
        removeGuard(point.ped, false)
        point:remove()
    end
end)
