-- Street selling as the client plays it out: who walks up, how far away they are picked from,
-- how long things wait before giving up, and the camera. The odds and the money are server-only
-- (configs/server/selling.lua + economy.lua).
return {
    CustomerSearchRadius = 45.0, -- how far an ambient ped can be to be sent over on foot
    VehicleSpawnRadius = 80.0, -- how far away a buyer's car is created before it drives to your spot
    ServeDistance = 2.2, -- how close you must be to hand over

    -- Walking up to a ped yourself and pitching (the target option on ambient peds).
    ApproachEnabled = true,

    -- Seconds. Each is a failsafe so a stuck ped never blocks the next customer.
    CustomerOnRouteTimeout = 180, -- a walking customer who never arrives is released
    ParkUpTimeout = 30, -- a car that can't reach the spot gives up
    VehicleCustomerWaitTime = 30, -- a parked buyer leaves if you don't come to the window
    OfferSeconds = 75, -- how long a texted offer stays open (mirrors the server ticket)

    VehiclesAutoCleanUp = true,
    VehicleCleanUpMinutes = 5, -- a buyer's car that is still around is deleted after this

    -- Short scripted camera cuts. Each can be turned off on its own.
    Cinematics = {
        Sales = true, -- the hand-off on foot
        VehicleSales = false, -- the hand-off at a car window
        Robbery = false, -- a customer pulling a weapon instead of paying
        Encounters = false, -- gang members stepping to you
        Interactions = true, -- meeting a contact
    },

    HandOff = {
        Dict = 'mp_common',
        GiveClip = 'givetake1_a',
        TakeClip = 'givetake1_b',
        Ms = 1800,
    },

    -- Peds that never count as customers: service workers, animals, anything scripted.
    IgnorePedTypes = { 6, 20, 21, 27, 28, 29 }, -- cop, medic, fire, swat, animal, army

    -- For servers that run with ambient population off: customers are created instead of
    -- borrowed from the street.
    NoPedsServer = {
        Enabled = false,
        SpawnDistance = { min = 25.0, max = 50.0 },
    },

    -- Used for created customers (NoPedsServer, drop-offs without a model, car buyers).
    PedModels = {
        `a_m_y_stwhi_01`, `a_m_y_stbla_01`, `a_m_y_stlat_01`, `a_m_y_skater_01`, `a_m_y_hipster_01`,
        `a_m_y_genstreet_01`, `a_m_y_downtown_01`, `a_m_m_soucent_01`, `a_m_m_eastsa_01`,
        `a_f_y_hipster_02`, `a_f_y_genhot_01`, `a_f_y_soucent_01`, `a_f_y_eastsa_03`,
        `a_f_m_downtown_01`, `a_m_y_business_02`, `a_m_y_vinewood_03`, `a_f_y_vinewood_02`,
        `a_m_m_salton_02`, `a_m_y_methhead_01`, `a_f_y_rurmeth_01`,
    },
    VehicleModels = {
        `emperor`, `primo`, `stanier`, `asea`, `ingot`, `premier`, `tailgater`, `fugitive`,
        `buccaneer`, `manana`, `tornado`, `peyote`, `blista`, `prairie`, `felon`, `oracle`,
        `baller`, `cavalcade`, `rebel`, `bison`, `sultan`, `futo`, `sentinel`, `zion`,
    },

    -- Cash the customer visibly hands over, by sale value.
    MoneyProps = {
        { upTo = 500, model = `prop_anim_cash_note` },
        { upTo = 4999, model = `xs_prop_arena_cash_pile_s` },
        { upTo = 9999, model = `xs_prop_arena_cash_pile_m` },
        { upTo = 24999, model = `xs_prop_arena_cash_pile_l` },
        { upTo = math.huge, model = `prop_cash_case_01`, largePackage = true },
    },
}
