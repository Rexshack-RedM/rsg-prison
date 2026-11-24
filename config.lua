Config = {}

---------------------------------
-- general
---------------------------------
Config.RemoveJob      = true  -- player loses ALL their jobs (rsg-core multi-job) when jailed and must be re-hired
Config.JailAllowance  = 0     -- cash given when jailed (0 = none)
Config.DistanceSpawn  = 20.0  -- distance the guard npc spawns at
Config.FadeIn         = true  -- fade the guard npc in / out
Config.ReturnOnEscape = true  -- return prisoners if they leave the prison zone (client check + server-side backstop)

---------------------------------
-- guard rations
---------------------------------
Config.GuardRations = {
    max      = 5,   -- max of each item a prisoner can hold at once
    cooldown = 10,  -- seconds between requests
    distance = 5.0, -- max distance from the guard
    items = {
        water = 'water', -- inventory item name
        bread = 'bread', -- inventory item name
    }
}

---------------------------------
-- guard services
---------------------------------
Config.CollectProperty = true -- the guard hands back belongings that did not fit on release (no relog needed)

Config.Bail = {
    enabled        = true,
    account        = 'bank', -- account charged. Belongings (cash included) are seized on entry, so use 'bank'
    pricePerMinute = 2,      -- price per remaining minute
    minimum        = 5,      -- lowest price charged
    confirmSeconds = 15,     -- the prisoner asks the guard again within this time to confirm the quoted price
}

---------------------------------
-- prison labour: break rocks to take time off the sentence (all timing and limits are server-side)
---------------------------------
Config.Labour = {
    enabled      = true,
    duration     = 30000,   -- ms per work cycle
    cooldown     = 60,      -- seconds between cycles
    minutesOff   = 1,       -- minutes taken off per cycle
    maxReduction = 50,      -- % of the original sentence labour can remove
    distance     = 2.5,     -- extra server-side distance allowed around a site's radius
    scenario     = 'WORLD_HUMAN_FARMER_WEEDING', -- animation scenario while working (swap for a pickaxe scenario if you prefer)
    sites = {                -- inside the prison zone; replace with your rock / work spots
        { coords = vector3(3349.62, -650.41, 45.38), radius = 1.5 },
        { coords = vector3(3380.62, -672.35, 46.27), radius = 1.5 },
    },
}

---------------------------------
-- contraband: /searchprisoner (on-duty lawmen) seizes anything not allowed and adds time
---------------------------------
Config.Contraband = {
    enabled         = true,
    distance        = 3.0,                -- max distance between lawman and prisoner (server-side)
    allowed         = { 'dollar', 'cent' }, -- items a prisoner may hold, on top of the guard rations (cash is items)
    minutesPerItem  = 2,                  -- minutes added per seized stack
    maxExtraMinutes = 15,                 -- cap per search
    cooldown        = 60,                 -- seconds before the same prisoner can be searched again
}

---------------------------------
-- prison clothing (shop item category hashes to strip, then the outfit items applied)
---------------------------------
Config.Clothing = {
    remove = {
        0x9925C067, 0x485EE834, 0x18729F39, 0x3107499B, 0x3C1A74CD, 0x3F1F01E5, 0x3F7F3587, 0x49C89D9B,
        0x4A73515C, 0x514ADCEA, 0x5FC29285, 0x79D7DF96, 0x7A96FACA, 0x877A2CF7, 0x9B2C8B89, 0xA6D134C6,
        0xE06D30CE, 0x0662AC34, 0xAF14310B, 0x72E6EF74, 0xEABE0032, 0x2026C46D, 0xB6B6122D, 0xB9E2FA01,
    },
    male   = { 0x5BA76CCF, 0x216612F0, 0x1CCEE58D },
    female = { 0x6AB27695, 0x75BC0CF5, 0x14683CDF },
}

---------------------------------
-- blip
---------------------------------
Config.Blip = {
    blipSprite = 'blip_mp_roles_bounty_hunter_lock',
    blipScale  = 0.2
}

---------------------------------
-- locations
---------------------------------
Config.Locations = {
    outside = vector4(3340.71, -629.99, 43.72, 36.36),  -- release point
    escape  = vector4(3368.31, -665.94, 46.29, 165.59), -- where escapees are returned to
    spawns  = {
        vector4(3330.66, -692.75, 43.95, 292.86),
        vector4(3349.62, -650.41, 45.38, 207.53),
        vector4(3380.62, -672.35, 46.27, 110.95),
        vector4(3366.75, -666.08, 46.34, 297.69),
    }
}

-- prison guard (menu) locations
Config.MenuLocations = {
    {
        npcmodel  = `s_m_m_skpguard_01`,
        npccoords = vector4(3352.11, -690.77, 44.25, 31.30),
        showblip  = true
    },
}

-- prison boundary (poly zone; thickness = height around points' z)
Config.PrisonZone = {
    thickness = 30.0,
    points = {
        vec3(3318.40, -657.30, 45.3),
        vec3(3384.74, -640.31, 45.3),
        vec3(3406.61, -678.14, 45.3),
        vec3(3368.95, -724.20, 45.3),
        vec3(3334.64, -704.12, 45.3),
        vec3(3329.46, -698.78, 45.3),
    }
}
