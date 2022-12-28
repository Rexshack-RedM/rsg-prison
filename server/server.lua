local RSGCore = exports['rsg-core']:GetCoreObject()
local GotItems = {}

RegisterNetEvent('rsg-prison:server:UpdatePlayer', function()
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end
    Player.Functions.SetMetaData("injail", 0)
    if Player.PlayerData.job.name ~= 'unemployed' and Config.RemoveJob == true then
        Player.Functions.SetJob('unemployed')
    end
end)

RegisterNetEvent('rsg-prison:server:SaveJailItems', function()
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end
    if not Player.PlayerData.metadata["jailitems"] or not next(Player.PlayerData.metadata["jailitems"]) then
        Player.Functions.SetMetaData("jailitems", Player.PlayerData.items)
        Player.Functions.AddMoney('cash', 10)
        Wait(2000)
        Player.Functions.ClearInventory()
    end
end)

RegisterNetEvent('rsg-prison:server:GiveJailItems', function()
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end
    Wait(1000)
    for _, v in pairs(Player.PlayerData.metadata["jailitems"]) do
        Player.Functions.AddItem(v.name, v.amount, false, v.info)
    end
    Wait(1000)
    Player.Functions.SetMetaData("jailitems", {})
end)

RegisterNetEvent('rsg-prison:server:CheckRecordStatus', function()
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end
    local CriminalRecord = Player.PlayerData.metadata["criminalrecord"]
    local currentDate = os.date("*t")
    if (CriminalRecord["date"].month + 1) == 13 then
        CriminalRecord["date"].month = 0
    end
    if CriminalRecord["hasRecord"] then
        if currentDate.month == (CriminalRecord["date"].month + 1) or currentDate.day == (CriminalRecord["date"].day - 1) then
            CriminalRecord["hasRecord"] = false
            CriminalRecord["date"] = nil
        end
    end
end)