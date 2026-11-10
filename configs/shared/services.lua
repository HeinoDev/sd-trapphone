-- The back-room services a growing business unlocks. Shared half: switches and how you
-- interact. Locations, rates and stock are server-only (configs/server/services.lua); the
-- server hands a location to a client only once that player has unlocked it.
return {
    MoneyWash = {
        Enabled = true,
        Interaction = 'target', -- 'target' (bridge target on the attendant) or 'zone' (press E in a marker)
        Blip = { sprite = 500, colour = 2, scale = 0.7, label = 'Laundry' },
    },
    BlackMarket = {
        Enabled = true,
        Interaction = 'target',
        Blip = { sprite = 110, colour = 1, scale = 0.7, label = 'Back room' },
    },
}
