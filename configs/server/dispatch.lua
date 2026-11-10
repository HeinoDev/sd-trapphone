-- SERVER-ONLY: police pressure. Alerts go out through the dispatch bridge on the seller's
-- client (bridge/client/alert.lua), which supports the common dispatch resources.
return {
    PoliceJobs = { 'police', 'sheriff' },

    CheckForPolice = false, -- true: selling can't start with fewer than RequiredPolice on duty
    RequiredPolice = 3,

    -- Simple mode: every sale just rolls SimpleChance for an alert. When false, alerts come
    -- only from snitches (below), which is the more readable game.
    Simple = false,
    SimpleChance = 20, -- percent
    Cooldown = 90, -- seconds between alerts about the same player

    -- A snitch is a ped who saw the deal or turned you down. They phone it in after a delay.
    Snitch = {
        Chance = 25, -- percent of refused pitches that turn into a call (scaled by personality)
        WitnessChance = 6, -- percent of completed sales that someone nearby reports
        DelaySeconds = { min = 8, max = 25 },
        Timeout = 120, -- seconds before another snitch call can be made about the same player
    },

    -- Heat (0..100) rises with every alert and cools over time. It is shown on the phone and
    -- raises snitch odds while it is high.
    Heat = {
        PerAlert = 18,
        CoolPerMinute = 2,
        SnitchScaleAtMax = 2.0, -- snitch odds multiplier at 100 heat
    },

    Alert = {
        code = '10-66',
        title = 'Suspected drug deal',
        sprite = 51,
        colour = 1,
        scale = 1.0,
        blipSeconds = 90,
    },
}
