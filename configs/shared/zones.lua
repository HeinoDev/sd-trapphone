-- The turf map. Each area is a circle; the smallest circle containing a point wins, so a
-- tight block can sit inside a wide district. Anything outside every circle is `Default`.
-- Resolved on the server from the player's real position (shared/zones.lua), so a client
-- cannot claim to be standing somewhere richer.
--
-- wealth 0..5: how much money walks these streets. Each product lists the wealth tiers that
-- crave it (configs/server/economy.lua `demand`).
-- gang: a key of configs/shared/gangs.lua, or nil for unclaimed ground.
return {
    Default = { id = 'open', label = 'Open ground', wealth = 2 },

    Areas = {
        { id = 'davis', label = 'Davis', center = vec2(105.0, -1940.0), radius = 330.0, wealth = 1, gang = 'ballas' },
        { id = 'chamberlain', label = 'Chamberlain Hills', center = vec2(-190.0, -1610.0), radius = 260.0, wealth = 1, gang = 'families' },
        { id = 'strawberry', label = 'Strawberry', center = vec2(230.0, -1400.0), radius = 240.0, wealth = 1 },
        { id = 'rancho', label = 'Rancho', center = vec2(440.0, -2070.0), radius = 230.0, wealth = 0, gang = 'vagos' },
        { id = 'elburro', label = 'El Burro Heights', center = vec2(1290.0, -1670.0), radius = 330.0, wealth = 0, gang = 'marabunta' },
        { id = 'lamesa', label = 'La Mesa', center = vec2(820.0, -1050.0), radius = 320.0, wealth = 2 },
        { id = 'mirrorpark', label = 'Mirror Park', center = vec2(1120.0, -620.0), radius = 330.0, wealth = 3 },
        { id = 'downtown', label = 'Downtown', center = vec2(110.0, -860.0), radius = 420.0, wealth = 3 },
        { id = 'vinewood', label = 'Vinewood', center = vec2(330.0, 180.0), radius = 420.0, wealth = 3 },
        { id = 'eastvinewood', label = 'East Vinewood', center = vec2(960.0, -130.0), radius = 280.0, wealth = 2, gang = 'lost' },
        { id = 'rockford', label = 'Rockford Hills', center = vec2(-850.0, -120.0), radius = 460.0, wealth = 5 },
        { id = 'vinewoodhills', label = 'Vinewood Hills', center = vec2(-620.0, 640.0), radius = 700.0, wealth = 5 },
        { id = 'delperro', label = 'Del Perro', center = vec2(-1500.0, -560.0), radius = 380.0, wealth = 4 },
        { id = 'vespucci', label = 'Vespucci', center = vec2(-1180.0, -1320.0), radius = 420.0, wealth = 3 },
        { id = 'lapuerta', label = 'La Puerta', center = vec2(-640.0, -1280.0), radius = 300.0, wealth = 2 },
        { id = 'sandy', label = 'Sandy Shores', center = vec2(1850.0, 3720.0), radius = 520.0, wealth = 0, gang = 'lost' },
        { id = 'grapeseed', label = 'Grapeseed', center = vec2(1960.0, 4860.0), radius = 420.0, wealth = 1 },
        { id = 'paleto', label = 'Paleto Bay', center = vec2(-150.0, 6360.0), radius = 520.0, wealth = 2 },
    },

    WealthLabels = { [0] = 'Broke', 'Rough', 'Working', 'Comfortable', 'Rich', 'Loaded' },
}
