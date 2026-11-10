-- The crews that hold turf. Shared half: what the phone shows and which ambient peds count as
-- theirs. The numbers (rep, tax, bribes, riots) are server-only in configs/server/gangs.lua.
return {
    Enabled = true,

    -- relGroups: the game's own relationship groups for the crew's ambient members. A ped in one
    -- of these counts as "one of theirs" for kills and encounters.
    -- models: who is created when the crew steps to you or sends a riot wave.
    List = {
        ballas = {
            label = 'Ballas',
            color = '#a45bd6',
            relGroups = { `AMBIENT_GANG_BALLAS` },
            models = { `g_m_y_ballaeast_01`, `g_m_y_ballaorig_01`, `g_m_y_ballasout_01`, `g_f_y_ballas_01` },
            leaderModel = `g_m_y_ballaorig_01`,
        },
        families = {
            label = 'Families',
            color = '#4fb866',
            relGroups = { `AMBIENT_GANG_FAMILY` },
            models = { `g_m_y_famca_01`, `g_m_y_famdnf_01`, `g_m_y_famfor_01`, `g_f_y_families_01` },
            leaderModel = `g_m_y_famfor_01`,
        },
        vagos = {
            label = 'Vagos',
            color = '#f0c341',
            relGroups = { `AMBIENT_GANG_MEXICAN` },
            models = { `g_m_y_mexgoon_01`, `g_m_y_mexgoon_02`, `g_m_y_mexgoon_03`, `g_f_y_vagos_01` },
            leaderModel = `g_m_y_mexgoon_03`,
        },
        marabunta = {
            label = 'Marabunta Grande',
            color = '#56a8e8',
            relGroups = { `AMBIENT_GANG_SALVA` },
            models = { `g_m_y_salvaboss_01`, `g_m_y_salvagoon_01`, `g_m_y_salvagoon_02`, `g_m_y_salvagoon_03` },
            leaderModel = `g_m_y_salvaboss_01`,
        },
        lost = {
            label = 'The Lost',
            color = '#c9c9c9',
            relGroups = { `AMBIENT_GANG_LOST` },
            models = { `g_m_y_lost_01`, `g_m_y_lost_02`, `g_m_y_lost_03`, `g_f_y_lost_01` },
            leaderModel = `g_m_y_lost_02`,
        },
    },

    -- How a rep number (-100..100) reads on the phone. Highest `from` that fits wins.
    Standings = {
        { from = -100, id = 'hostile', label = 'On sight' },
        { from = -40, id = 'cold', label = 'Not welcome' },
        { from = -10, id = 'neutral', label = 'Nobody to them' },
        { from = 25, id = 'friendly', label = 'Known' },
        { from = 70, id = 'family', label = 'Family' },
    },

    -- Weapons a crew brings when it comes for you.
    EncounterWeapons = { `WEAPON_BAT`, `WEAPON_KNIFE`, `WEAPON_PISTOL` },
    RiotWeapons = { `WEAPON_PISTOL`, `WEAPON_MICROSMG`, `WEAPON_SAWNOFFSHOTGUN`, `WEAPON_BAT` },
}
