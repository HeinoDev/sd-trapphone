-- What can be sold through the phone. Shared, because the client draws the hand prop and the
-- phone lists what you are holding. Prices, sale sizes and cooldowns live server-side in
-- configs/server/economy.lua, keyed by the same item names.
--
-- A `family` groups the sizes of one product: XP, levels and demand are tracked per family, and
-- the scales split one size of a family into another. `unit` must be one of the Scales.Weights
-- keys (gram, quarter, ounce, kilo).
return {
    Families = {
        weed = { label = 'Weed', color = '#6fcf4a' },
        coke = { label = 'Coke', color = '#e9eef5' },
        meth = { label = 'Meth', color = '#6fd3ff' },
    },

    -- [item name] = { family, unit, prop?, largePackage? }
    -- prop: what the character hands over. largePackage: carried two-handed (box carry).
    Items = {
        weedbaggy = { family = 'weed', unit = 'gram', prop = `prop_weed_bottle` },
        weed_7g = { family = 'weed', unit = 'quarter', prop = `prop_weed_bottle` },
        weed_1oz = { family = 'weed', unit = 'ounce', prop = `prop_weed_block_01` },
        weed_brick = { family = 'weed', unit = 'kilo', prop = `prop_weed_block_01`, largePackage = true },

        cokebaggy = { family = 'coke', unit = 'gram', prop = `prop_meth_bag_01` },
        coke_7g = { family = 'coke', unit = 'quarter', prop = `prop_meth_bag_01` },
        coke_1oz = { family = 'coke', unit = 'ounce', prop = `prop_coke_block_half_a` },
        coke_brick = { family = 'coke', unit = 'kilo', prop = `prop_coke_block_01`, largePackage = true },

        meth = { family = 'meth', unit = 'gram', prop = `prop_meth_bag_01` },
        meth_7g = { family = 'meth', unit = 'quarter', prop = `prop_meth_bag_01` },
        meth_1oz = { family = 'meth', unit = 'ounce', prop = `prop_meth_bag_01` },
        meth_brick = { family = 'meth', unit = 'kilo', prop = `prop_meth_bag_01`, largePackage = true },
    },

    -- How a unit reads on the phone ("3 x gram of Coke").
    Units = {
        gram = { label = 'gram', short = 'g' },
        quarter = { label = 'quarter', short = 'qtr' },
        ounce = { label = 'ounce', short = 'oz' },
        kilo = { label = 'brick', short = 'kg' },
    },
}
