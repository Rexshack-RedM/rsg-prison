local RSGCore = exports['rsg-core']:GetCoreObject()
local zones = {}
local working = false

-- the server issues the start, times the work and applies the reduction; this only plays the animation
local function startWork(index)
    if working then return end
    working = true
    CreateThread(function()
        local ok = RSGCore.Functions.AwaitCallback('rsg-prison:server:labourStart', 5000, index)
        if ok then
            local done = RSGCore.Functions.ProgressBar({
                duration = Config.Labour.duration,
                label = locale('cl_labour_progress'),
                canCancel = true,
                anim = { scenario = Config.Labour.scenario },
                disable = { move = true, combat = true },
            })
            if done then TriggerServerEvent('rsg-prison:server:labourFinish') end
        end
        working = false
    end)
end

if Config.Labour.enabled then
    for i, site in ipairs(Config.Labour.sites) do
        zones[#zones + 1] = exports['rsg-target']:addSphereZone({
            coords = site.coords,
            radius = site.radius,
            options = {{
                name = 'rsg_prison_labour_' .. i,
                icon = 'fa-solid fa-hammer',
                label = locale('cl_break_rocks'),
                distance = 2.0,
                canInteract = function() return not working and PrisonIsPrisoner() end,
                onSelect = function() startWork(i) end,
            }},
        })
    end
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, zone in ipairs(zones) do exports['rsg-target']:removeZone(zone) end
end)
