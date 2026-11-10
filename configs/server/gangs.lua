-- SERVER-ONLY: gang politics. Merged over configs/shared/gangs.lua on the server.
return {
    -- Reputation is per character per gang, -100..100, starting at StartRep.
    StartRep = 0,
    Rep = {
        PerSaleOnTurf = -1, -- selling on their ground without paying for it wears them down
        PerSaleProtected = 1, -- selling under their protection builds the name
        PerTaxPaid = 4,
        PerTaxRefused = -12,
        PerMemberKilled = -15,
        PerBribe = 10,
    },

    -- Selling on claimed ground without protection: after a sale there is a chance a few of
    -- them step to you. The chance depends on standing (configs/shared/gangs.lua Standings).
    Encounter = {
        Chance = { hostile = 45, cold = 25, neutral = 10, friendly = 0, family = 0 }, -- percent per sale
        Cooldown = 300, -- seconds between encounters for the same player
        Members = { min = 2, max = 4 },
        -- What they want when they step to you.
        TaxShare = 0.30, -- of what you made on their turf since the last tax, minimum TaxMin
        TaxMin = 250,
        AnswerSeconds = 25, -- no answer counts as refusing
        -- Standing 'hostile' skips the conversation: they just come for you.
    },

    -- Paying the shot caller for protection (the 'bribe' action on a gang contact).
    Bribe = {
        Price = 5000,
        Hours = 24, -- real hours of protection on their turf
        MinStanding = 'cold', -- a crew that wants you dead won't take your money
    },

    -- What a crew is paid with: turf tax, bribes and riot pay-offs. 'cash', 'bank' or 'black'.
    PayWith = 'cash',

    -- Jobs the gangs leave alone entirely (never stepped to, never rioted against).
    IgnoredJobs = { 'ambulance' },

    -- Job-wide standing: when one officer angers a crew the whole force wears it. Listed jobs
    -- share one rep per gang instead of each character keeping their own.
    SharedJobRep = { 'police', 'sheriff' },

    -- When a shared-rep job kills enough of a crew inside the window, the crew riots: waves of
    -- armed members come for the players of that job who are on their turf. Seeing it through
    -- (or paying the shot caller) resets the standing.
    Riot = {
        Enabled = true,
        KillsToTrigger = 6,
        WindowMinutes = 10,
        Waves = 3,
        MembersPerWave = { min = 4, max = 7 },
        SecondsBetweenWaves = 45,
        Cooldown = 3600, -- seconds before the same crew can riot again
        RepAfter = -10, -- job standing once the riot has burned out
        PayOffPrice = 25000, -- paying the shot caller to call it off
    },
}
