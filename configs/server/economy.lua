-- SERVER-ONLY (not in fxmanifest files{}): the money and the progression curve.
return {
    -- How a sale pays out: 'cash', 'bank', 'black' (the framework's dirty money, through the
    -- bridge: markedbills / black_money), or any item name (paid 1 item per dollar).
    PayoutAccount = 'cash',

    -- Per item (keys match configs/shared/drugs.lua Items). Prices are per ONE unit sold.
    --   price    what a neutral customer in a neutral zone offers, before the roll
    --   min/max  the offer is clamped here after every modifier; a haggle can't pass max either
    --   maxSale  the most a customer asks for in one go
    --   npc      false = never asked for on the street (plug / player trade only)
    --   cooldown seconds before the next customer for this item
    --   demand   wealth tiers (configs/shared/zones.lua) that crave it: sales there get DemandBonus
    Prices = {
        weedbaggy = { price = 50, min = 35, max = 100, maxSale = 7, npc = true, cooldown = 10, demand = { 2, 3, 4 } },
        weed_7g = { price = 350, min = 250, max = 500, maxSale = 3, npc = true, cooldown = 15, demand = { 1, 2, 3 } },
        weed_1oz = { price = 500, min = 350, max = 1000, maxSale = 1, npc = false, cooldown = 90, demand = { 1, 2, 3, 4 } },

        cokebaggy = { price = 150, min = 100, max = 220, maxSale = 5, npc = true, cooldown = 20, demand = { 3, 4, 5 } },
        coke_7g = { price = 550, min = 350, max = 750, maxSale = 3, npc = true, cooldown = 45, demand = { 4, 5 } },
        coke_1oz = { price = 2000, min = 1000, max = 3000, maxSale = 1, npc = false, cooldown = 90, demand = { 4, 5 } },

        meth = { price = 100, min = 50, max = 150, maxSale = 5, npc = true, cooldown = 15, demand = { 0, 1, 2 } },
        meth_7g = { price = 1000, min = 750, max = 1500, maxSale = 3, npc = true, cooldown = 25, demand = { 0, 1 } },
        meth_1oz = { price = 1100, min = 800, max = 2000, maxSale = 1, npc = true, cooldown = 90, demand = { 0, 1, 2 } },
    },

    DemandBonus = 1.25, -- price multiplier in a zone that craves the product
    OfferSpread = 0.15, -- each offer rolls +/- this share around the modified price

    -- A good relationship pays. Applied to the offer, scaled by the customer's relationship
    -- (-100..100): at +100 the offer is up by RelationshipBonus, at -100 down by it.
    RelationshipBonus = 0.12,
    -- Level pays too: each level above 1 in the product's family adds this share, capped.
    LevelBonusPerLevel = 0.02,
    LevelBonusCap = 0.20,

    -- Haggling. A counter-offer above the customer's offer is accepted with a chance that
    -- falls as the ask climbs: BaseChance at +0%, zero at +MaxMarkup. Personality and
    -- relationship shift it (configs/server/selling.lua).
    Haggle = {
        Enabled = true,
        BaseChance = 0.85,
        MaxMarkup = 0.40, -- a counter more than 40% over the offer is always refused
        MaxCounters = 2, -- counters per offer before the customer walks
    },

    -- XP is tracked per product family, on the phone (or the character, see Phone config).
    -- Reaching the next level takes LevelStep x current level XP.
    XP = {
        LevelStep = 1000,
        MaxLevel = 20,
        GainBase = 50, -- per sale: max(GainMin, floor(GainBase / level))
        GainMin = 5,
        LossBase = 5, -- per failure (refused pitch, robbed, snitched on): min(LossMax, LossBase x level)
        LossMax = 50,
        DropOffBonus = 1.5, -- drop-offs are worth this much more XP than a corner sale
    },

    -- What the phone calls each level, shown instead of numbers when ShowLevelNumbers is false.
    ShowLevelNumbers = false,
    Titles = {
        { from = 1, label = 'Nobody' },
        { from = 2, label = 'Corner boy' },
        { from = 4, label = 'Runner' },
        { from = 6, label = 'Dealer' },
        { from = 9, label = 'Trapper' },
        { from = 12, label = 'Supplier' },
        { from = 16, label = 'Kingpin' },
    },
}
