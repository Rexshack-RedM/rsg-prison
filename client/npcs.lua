local guards = {}

local function spawnGuard(model, coords)
    if not lib.requestModel(model, 10000) then return end
    local ped = CreatePed(model, coords.x, coords.y, coords.z - 1.0, coords.w, false, false, false, false)
    SetModelAsNoLongerNeeded(model)
    SetEntityAlpha(ped, Config.FadeIn and 0 or 255, false)
    SetRandomOutfitVariation(ped, true)
    SetEntityCanBeDamaged(ped, false)
    SetEntityInvincible(ped, true)
    FreezeEntityPosition(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedCanBeTargetted(ped, false)

    exports.ox_target:addLocalEntity(ped, {
        {
            name = 'rsg_prison_menu',
            icon = 'fa-solid fa-handcuffs',
            label = locale('cl_prison_menu'),
            distance = 2.0,
            onSelect = function() TriggerEvent('rsg-prison:client:menu') end
        }
    })

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
    exports.ox_target:removeLocalEntity(ped, 'rsg_prison_menu')
    if fade and Config.FadeIn then
        for i = 255, 0, -51 do
            Wait(50)
            SetEntityAlpha(ped, i, false)
        end
    end
    DeleteEntity(ped)
end

for k, v in ipairs(Config.MenuLocations) do
    local point = lib.points.new({ coords = v.npccoords.xyz, distance = Config.DistanceSpawn })

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
