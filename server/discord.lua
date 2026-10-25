-- Discord webhook logging (same system as rsg-drugs). Usage (server only):
--   PrisonLog('jail', 'Prisoner jailed', src, { { 'Sentence', '10 min' } })
-- Embeds are queued per webhook, batched (10 per message) and sent with 429 back-off.
local RSGCore = exports['rsg-core']:GetCoreObject()
lib.locale()
local C = ConfigDiscord
local queues = {}   -- [url] = { embeds... }
local waitUntil = {} -- [url] = GetGameTimer() ms when rate limit ends

local function urlFor(category)
    if not C or not C.Enabled then return end
    local url = C.Webhooks[category]
    if url == false then return end
    if not url or url == '' then url = C.Default end
    if url and url ~= '' then return url end
end

local function cut(s, n)
    s = tostring(s == nil and '-' or s)
    if s == '' then s = '-' end
    return #s > n and (s:sub(1, n - 3) .. '...') or s
end

local function playerFields(src)
    local out = {}
    if not src or src <= 0 then
        out[1] = { name = locale('dc_f_player'), value = locale('dc_console'), inline = true }
        return out
    end
    local Player = RSGCore.Functions.GetPlayer(src)
    local name = GetPlayerName(src) or '?'
    if Player then
        local ci = Player.PlayerData.charinfo or {}
        out[#out + 1] = { name = locale('dc_f_character'), value = cut(('%s %s'):format(ci.firstname or '', ci.lastname or ''), 256), inline = true }
        out[#out + 1] = { name = locale('dc_f_citizenid'), value = cut(Player.PlayerData.citizenid, 64), inline = true }
    end
    out[#out + 1] = { name = locale('dc_f_player'), value = cut(locale('dc_player_id', name, src), 256), inline = true }
    if C.ShowLicense then
        out[#out + 1] = { name = locale('dc_f_license'), value = cut(GetPlayerIdentifierByType(src, 'license'), 128), inline = false }
    end
    if C.ShowDiscord then
        local d = GetPlayerIdentifierByType(src, 'discord')
        if d then out[#out + 1] = { name = locale('dc_f_discord'), value = '<@' .. d:gsub('discord:', '') .. '>', inline = true } end
    end
    if C.ShowCoords then
        local p = GetEntityCoords(GetPlayerPed(src))
        out[#out + 1] = { name = locale('dc_f_coords'), value = ('%.1f, %.1f, %.1f'):format(p.x, p.y, p.z), inline = true }
    end
    return out
end

-- fields: array of { label, value[, inline] }
function PrisonLog(category, title, src, fields, description)
    local url = urlFor(category)
    if not url then return end
    local embedFields = {}
    for _, f in ipairs(fields or {}) do
        if #embedFields >= 18 then break end
        embedFields[#embedFields + 1] = { name = cut(f[1], 256), value = cut(f[2], 1024), inline = f[3] ~= false }
    end
    for _, f in ipairs(playerFields(src)) do
        if #embedFields >= 25 then break end
        embedFields[#embedFields + 1] = f
    end
    local q = queues[url] or {}
    queues[url] = q
    if #q >= 100 then table.remove(q, 1) end -- never grow unbounded if Discord is down
    q[#q + 1] = {
        title = cut(title, 256),
        description = description and cut(description, 2000) or nil,
        color = C.Colors[category] or 9807270,
        fields = embedFields,
        footer = { text = cut(('%s • %s'):format(C.Footer, category), 2048) },
        timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
    }
end

local function send(url, embeds)
    local body = json.encode({ username = C.Username, avatar_url = C.Avatar ~= '' and C.Avatar or nil, embeds = embeds })
    PerformHttpRequest(url, function(status, resp)
        if status == 429 then
            local ok, data = pcall(json.decode, resp or '')
            local retry = (ok and type(data) == 'table' and tonumber(data.retry_after)) or 5
            waitUntil[url] = GetGameTimer() + math.ceil(retry * 1000) + 250
            local q = queues[url] or {}
            for i = #embeds, 1, -1 do table.insert(q, 1, embeds[i]) end -- requeue in order
            queues[url] = q
        elseif status < 200 or status >= 300 then
            print(('^1[rsg-prison] Discord webhook failed (HTTP %s). Check ConfigDiscord.Webhooks.^7'):format(status))
        end
    end, 'POST', body, { ['Content-Type'] = 'application/json' })
end

local function flush()
    local now = GetGameTimer()
    for url, q in pairs(queues) do
        if #q > 0 and now >= (waitUntil[url] or 0) then
            local batch = {}
            for i = 1, math.min(10, #q) do batch[i] = table.remove(q, 1) end
            send(url, batch)
        end
    end
end

CreateThread(function()
    if not C or not C.Enabled then return end
    while true do
        Wait((C.FlushSeconds or 3) * 1000)
        flush()
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then flush() end -- best effort
end)

-- other server resources can log into the same channels
exports('DiscordLog', function(category, title, src, fields, description)
    return PrisonLog(category, title, src, fields, description)
end)
