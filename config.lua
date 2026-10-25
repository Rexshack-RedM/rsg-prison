Config = {}

---------------------------------
-- general
---------------------------------
Config.RemoveJob      = true  -- player loses ALL their jobs (rsg-multijob) when jailed and must be re-hired
Config.JailAllowance  = 0     -- cash given when jailed (0 = none)
Config.DistanceSpawn  = 20.0  -- distance the guard npc spawns at
Config.FadeIn         = true  -- fade the guard npc in / out
Config.ReturnOnEscape = true  -- teleport prisoners back if they leave the prison zone

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
        coords    = vector3(3352.11, -690.77, 44.25),
        npcmodel  = `s_m_m_skpguard_01`,
        npccoords = vector4(3352.11, -690.77, 44.25, 31.30),
        showblip  = true
    },
}

-- prison boundary (ox_lib poly zone)
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
