Config = {}

-- config settings
Config.RemoveJob = false -- if true then player loses job

-- locations
Config.Locations = {
    ["outside"] = { coords = vector4(3340.71, -629.99, 43.72, 36.36) },
    ["middle"] = { coords = vector4(3357.41, -679.26, 46.26, 165.59) },
    spawns = {
        [1] = { coords = vector4(3330.66, -692.75, 43.95, 292.86) },
        [2] = { coords = vector4(3349.62, -650.41, 45.38, 207.53) },
        [3] = { coords = vector4(3380.62, -672.35, 46.27, 110.95) },
        [4] = { coords = vector4(3366.75, -666.08, 46.34, 297.69) }
    }
}

-- jail shop
Config.JailShopItems = {
    [1] = {
        name = "bread",
        price = 1,
        amount = 50,
        info = {},
        type = "item",
        slot = 1
    },
    [2] = {
        name = "water",
        price = 1,
        amount = 50,
        info = {},
        type = "item",
        slot = 2
    }
}
