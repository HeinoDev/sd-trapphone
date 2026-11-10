-- SERVER-ONLY: the odds behind street selling. Merged over configs/shared/selling.lua on the
-- server.
return {
    -- Seconds between "who's next" checks while a player is serving, before per-item cooldowns.
    CustomerInterval = { min = 12, max = 28 },

    CustomerInVehicleChance = 35, -- percent of customers who pull up in a car, when a spot is set
    RefuseDrugsChance = 40, -- percent of peds you pitch yourself who say no
    RobberyChance = 4, -- percent of sales where the customer tries to take it instead of paying

    MinServeSeconds = 4, -- a sale can't complete sooner than this after its offer was made

    -- Ped relationships (-100..100), kept per character per ped look.
    Relationship = {
        PerSale = 6,
        PerHaggleWin = -2, -- they paid more than they wanted to
        PerHaggleFail = -6,
        PerDecline = -3,
        PerRobbery = -25, -- they robbed you: that look is no friend of yours afterwards
        HaggleShift = 0.15, -- added to the counter-offer chance at +100, taken off at -100
        RegularAt = 40, -- at this they become a named regular in Contacts and text you orders
    },

    -- Every customer has a personality (picked from their look, so the same ped is always the
    -- same person). haggle shifts the counter-offer chance, tip is a chance of a little extra,
    -- snitch scales the snitch odds, patience scales how long their offer stays open.
    Personalities = {
        chill = { weight = 30, haggle = 0.10, tip = 0.10, snitch = 0.5, patience = 1.2 },
        tight = { weight = 20, haggle = -0.25, tip = 0.0, snitch = 0.8, patience = 1.0 },
        jumpy = { weight = 15, haggle = -0.05, tip = 0.0, snitch = 1.6, patience = 0.6 },
        baller = { weight = 10, haggle = 0.25, tip = 0.30, snitch = 0.4, patience = 0.9 },
        fiend = { weight = 15, haggle = 0.15, tip = 0.0, snitch = 0.3, patience = 1.5 },
        square = { weight = 10, haggle = 0.0, tip = 0.05, snitch = 2.2, patience = 0.8 },
    },
    TipShare = 0.10, -- a tip is this share of the sale
}
