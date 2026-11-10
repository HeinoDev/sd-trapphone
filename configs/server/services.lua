-- SERVER-ONLY: money wash and black market. Merged over configs/shared/services.lua on the
-- server. A location is sent to a client only once that player has the contact that unlocks it.
return {
    MoneyWash = {
        UnlockContactType = 'launderer', -- having met a contact of this type opens the laundry
        Locations = {
            { coords = vec4(1135.9, -992.3, 46.1, 190.0), model = `s_m_m_linecook` },
        },
        -- The cut depends on the player's best level in any family. Highest `from` that fits wins.
        Tiers = {
            { from = 1, fee = 0.35, max = 10000 },
            { from = 6, fee = 0.28, max = 30000 },
            { from = 10, fee = 0.20, max = 75000 },
            { from = 15, fee = 0.12, max = 200000 },
        },
        SecondsPer1000 = 6, -- you wait while it spins; leaving the area cancels and refunds
        MaxSeconds = 180,
        AlertChance = 5, -- percent chance a wash tips off the police
        PayoutAccount = 'cash',
    },

    BlackMarket = {
        UnlockContactType = 'fixer',
        Locations = {
            { coords = vec4(707.6, -963.3, 30.4, 180.0), model = `s_m_y_dealer_01` },
        },
        PayWith = 'cash',
        -- [item] = { price, level? } - level is the best level in any family needed to see it.
        Stock = {
            trap_phone_graphite = { price = 750 },
            trap_phone_bling = { price = 6500, level = 6 },
            scales = { price = 400 },
            batteries = { price = 20 },
            lockpick = { price = 350 },
            armour = { price = 1800, level = 6 },
            weapon_knife = { price = 900, level = 6 },
            weapon_pistol = { price = 9500, level = 9 },
            ['ammo-9'] = { price = 12, level = 9 },
            weapon_microsmg = { price = 38000, level = 13 },
        },
        MaxPerPurchase = 10,
    },
}
