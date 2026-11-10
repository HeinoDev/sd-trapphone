-- Bagging up: use the scales to break a bigger unit of a product into smaller ones.
return {
    Enabled = true,
    Item = 'scales',
    BatteryItem = 'batteries',

    Prop = `bkr_prop_coke_scale_01`,
    Anim = { Dict = 'anim@amb@business@coc@coc_unpack_cut_left@', Clip = 'coke_cut_v1_coccutter', Flag = 1 },

    -- Grams in one of each unit. A split turns 1 x from-unit into (from / to) x to-unit.
    Weights = { gram = 1, quarter = 7, ounce = 28, kilo = 1000 },

    -- Which splits exist and how long weighing ONE source unit takes, in seconds.
    Splits = {
        kilo = { ounce = 30, quarter = 50, gram = 100 },
        ounce = { quarter = 20, gram = 50 },
        quarter = { gram = 10 },
    },

    -- A kilo is 1000 g but an ounce is 28 g: what is left over after the split is lost as
    -- "shake" unless this is true, in which case the remainder is handed back as grams.
    ReturnRemainderAsGrams = true,

    -- The scales run on batteries. Charge is stored on the scales item (metadata `battery`,
    -- 0..100). A fresh set of scales starts full.
    Battery = {
        Enabled = true,
        DrainPerSourceUnit = { kilo = 12, ounce = 3, quarter = 1 }, -- percent per unit weighed
        ReplaceTo = 100,
    },

    -- When true, every bag produced also uses up one baggie of the right size.
    UseBaggies = false,
    SmallBaggiesItem = 'baggies', -- grams and quarters
    LargeBaggiesItem = 'large_baggies', -- ounces
}
