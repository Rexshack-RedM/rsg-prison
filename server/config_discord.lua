-- SERVER ONLY. Webhook URLs must never be in a shared/client file (clients could read and spam them).
ConfigDiscord = {
    Enabled  = true,
    Username = 'rsg-prison',
    Avatar   = '',            -- optional image URL for the webhook avatar
    Footer   = 'rsg-prison logs',
    Default  = '',            -- fallback webhook for any category left blank below

    -- one webhook per category (blank = use Default, false = don't log this category)
    Webhooks = {
        jail     = '',  -- sentences started, resumed after reconnect, changed/extended
        release  = '',  -- sentence served, released early (lawman), released while offline
        items    = '',  -- belongings seized and returned (with item list), leftovers kept
        jobs     = '',  -- jobs removed on jailing
        escape   = '',  -- prisoners leaving the prison zone
        rations  = '',  -- water / bread handed out by the guard
        security = '',  -- suspicious requests (rations out of range / not jailed, spam)
    },

    -- embed colours (decimal)
    Colors = {
        jail = 15105570, release = 5763719, items = 9807270, jobs = 3447003,
        escape = 15548997, rations = 10181046, security = 10038562,
    },

    LogRations   = true,      -- rations are frequent; set false to skip them entirely
    MaxItemLines = 25,        -- item list lines shown on seize/return logs

    -- identifiers shown on each log
    ShowLicense = true,
    ShowDiscord = true,       -- pings nobody; shows <@id> as a clickable mention
    ShowCoords  = true,

    -- Discord limit is ~30 messages/min per webhook; embeds are batched (max 10 per message)
    FlushSeconds = 3,
}
