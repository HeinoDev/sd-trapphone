-- SERVER-ONLY: the people you meet as the business grows. Merged over
-- configs/shared/contacts.lua on the server.
--
-- A special contact is never handed out by typing a number in. They reach out after a level-up
-- (IntroChance), you go and meet them, and only then does the number work.
return {
    IntroChance = 60, -- percent chance that a level-up makes an eligible contact reach out
    MaxPendingIntros = 1, -- unmet introductions at once

    -- Each entry:
    --   type      a key of configs/shared/contacts.lua Types
    --   name      how they sign their texts
    --   number    their fixed number (unique)
    --   unlock    { family = <drug family or 'any'>, level = <min level in it> }
    --   model     ped model
    --   meetups   places they meet; one is picked per meet. spawn is where they stand, walkTo
    --             (optional) where they stroll over from.
    --   gang      (type 'gang') which crew they speak for
    --   stock     (plug / supplier) { [item] = { price, min?, max?, level? } }
    --   intel     (informant) price for one tip: where demand is highest right now
    List = {
        {
            key = 'smoke', type = 'plug', name = 'Smoke', number = '555-0142',
            unlock = { family = 'weed', level = 2 },
            model = `a_m_y_soucent_02`,
            meetups = {
                { spawn = vec4(-1172.3, -1572.1, 4.7, 125.0) },
                { spawn = vec4(1128.4, -644.3, 56.8, 285.0) },
            },
            stock = {
                weed_1oz = { price = 320, max = 20 },
                weed_brick = { price = 9500, max = 3, level = 6 },
            },
        },
        {
            key = 'blanca', type = 'plug', name = 'Blanca', number = '555-0177',
            unlock = { family = 'coke', level = 3 },
            model = `a_f_y_bevhills_04`,
            meetups = {
                { spawn = vec4(-1387.9, -586.6, 30.2, 30.0) },
                { spawn = vec4(-709.1, -905.4, 19.2, 90.0) },
            },
            stock = {
                coke_1oz = { price = 1350, max = 10 },
                coke_brick = { price = 42000, max = 2, level = 8 },
            },
        },
        {
            key = 'chemist', type = 'plug', name = 'The Chemist', number = '555-0119',
            unlock = { family = 'meth', level = 3 },
            model = `a_m_m_hillbilly_02`,
            meetups = {
                { spawn = vec4(1391.8, 3608.5, 38.9, 200.0) },
                { spawn = vec4(2434.2, 4968.9, 42.3, 45.0) },
            },
            stock = {
                meth_1oz = { price = 720, max = 12 },
                meth_brick = { price = 23000, max = 2, level = 8 },
            },
        },
        {
            key = 'penny', type = 'supplier', name = 'Penny', number = '555-0103',
            unlock = { family = 'any', level = 2 },
            model = `a_f_m_business_02`,
            meetups = {
                { spawn = vec4(-48.6, -1757.5, 29.4, 50.0) },
                { spawn = vec4(1163.4, -323.9, 69.2, 100.0) },
            },
            stock = {
                scales = { price = 450, max = 2 },
                batteries = { price = 25, max = 20 },
                baggies = { price = 2, max = 500 },
                large_baggies = { price = 5, max = 200 },
                trap_phone_graphite = { price = 900, max = 1, level = 4 },
            },
        },
        {
            key = 'ears', type = 'informant', name = 'Ears', number = '555-0166',
            unlock = { family = 'any', level = 3 },
            model = `a_m_o_tramp_01`,
            meetups = { { spawn = vec4(189.6, -935.1, 30.7, 150.0) } },
            intel = { price = 300 },
        },
        {
            key = 'mrclean', type = 'launderer', name = 'Mr. Clean', number = '555-0188',
            unlock = { family = 'any', level = 5 },
            model = `a_m_m_business_01`,
            meetups = { { spawn = vec4(1136.0, -989.6, 46.1, 280.0) } },
        },
        {
            key = 'ghost', type = 'fixer', name = 'Ghost', number = '555-0131',
            unlock = { family = 'any', level = 7 },
            model = `s_m_y_dealer_01`,
            meetups = { { spawn = vec4(707.3, -966.9, 30.4, 270.0) } },
        },
        {
            key = 'oghollow', type = 'gang', gang = 'ballas', name = 'OG Hollow', number = '555-0151',
            unlock = { family = 'any', level = 4 },
            model = `g_m_y_ballaorig_01`,
            meetups = { { spawn = vec4(84.9, -1958.4, 21.1, 320.0) } },
        },
        {
            key = 'bigg', type = 'gang', gang = 'families', name = 'Big G', number = '555-0152',
            unlock = { family = 'any', level = 4 },
            model = `g_m_y_famfor_01`,
            meetups = { { spawn = vec4(-175.4, -1614.2, 33.8, 260.0) } },
        },
        {
            key = 'elviejo', type = 'gang', gang = 'vagos', name = 'El Viejo', number = '555-0153',
            unlock = { family = 'any', level = 4 },
            model = `g_m_y_mexgoon_03`,
            meetups = { { spawn = vec4(330.9, -2012.6, 22.4, 50.0) } },
        },
        {
            key = 'santo', type = 'gang', gang = 'marabunta', name = 'Santo', number = '555-0154',
            unlock = { family = 'any', level = 5 },
            model = `g_m_y_salvaboss_01`,
            meetups = { { spawn = vec4(1295.9, -1730.4, 54.0, 110.0) } },
        },
        {
            key = 'chains', type = 'gang', gang = 'lost', name = 'Chains', number = '555-0155',
            unlock = { family = 'any', level = 5 },
            model = `g_m_y_lost_02`,
            meetups = { { spawn = vec4(982.2, -103.4, 74.8, 220.0) } },
        },
    },

    IntelPayWith = 'cash', -- what an informant's tip is paid with: 'cash', 'bank' or 'black'
    IntelCooldown = 120, -- seconds between tips from the same informant

    -- Plug / supplier orders: placed on the phone, paid and collected in person.
    Order = {
        PayWith = 'cash', -- 'cash', 'bank' or 'black'
        MaxLines = 6, -- different items per order
        CooldownMinutes = 20, -- between orders with the same contact
    },
}
