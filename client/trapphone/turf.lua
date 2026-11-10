---@type table sd-trapphone config root (configs/config.lua).
local config = require 'configs.config'
---@type table Console log helper (shared.log).
local log = require 'shared.log'
---@type table The handset (client.trapphone.phone).
local phone = require 'client.trapphone.phone'
---@type table Shared world helpers (client.trapphone.world): owns every entity we create.
local world = require 'client.trapphone.world'
---@type table Notify bridge (bridge.client.notify).
local notify = require 'bridge.client.notify'

---@type table Gang config (config.Gangs), shared half: display, models, weapons.
local CFG = config.Gangs

---@class TrapCrew
---@field id integer|nil the server's encounter id (nil for a riot wave)
---@field gang string key of config.Gangs.List
---@field peds integer[] the members we created
---@field started integer GetGameTimer() they were created
---@field hostile boolean they are attacking
---@field resolved boolean the tax demand has been answered
---@field asking boolean the tax dialog is on screen
---@field done boolean it has been wound down

---@type table Turf module; the table returned at end of file. The crews as the player meets
---them: members stepping up for tax, coming for blood, riot waves, and telling the server
---when the player kills one of theirs.
local turf = {}

---@type TrapCrew|nil The crew currently stepping to the player.
local encounter
---@type TrapCrew[] Riot waves still on the street.
local waves = {}
---@type table<integer, string> Gang key by relationship group hash, from config.Gangs.List.
local groupToGang = {}
---@type table<integer, boolean> Dead peds already reported, by handle.
local reported = {}
---@type integer How many handles `reported` holds.
local reportedCount = 0

for id, gang in pairs(CFG.List) do
    for _, group in ipairs(gang.relGroups or {}) do groupToGang[group] = id end
end

---@type number How far away members are created, in metres.
local SPAWN_DISTANCE = 30.0
---@type number How close the leader comes before he speaks.
local TALK_DISTANCE = 4.5
---@type integer Milliseconds the crew gets to walk up before the demand is made anyway.
local ARRIVE_MS = 25000
---@type integer Milliseconds a fight may last before the survivors are pulled out.
local FIGHT_MS = 180000
---@type number The player getting this far away ends it.
local ESCAPE_DISTANCE = 150.0
---@type integer Milliseconds members get to walk off before they are removed.
local LEAVE_MS = 20000

---A spot on a pavement or road near a point, so nobody is created inside a building.
---@param x number
---@param y number
---@param z number
---@return number x, number y, number z
local function footing(x, y, z)
    local found, safe = GetSafeCoordForPed(x, y, z, true, 16)
    if found then return safe.x, safe.y, safe.z end

    return x, y, world.groundAt(x, y, z)
end

---Create a crew's members a little way off, all from the same side, facing the player.
---@param gang string key of config.Gangs.List
---@param count integer
---@return integer[] peds the ones that could be created
local function spawnMembers(gang, count)
    local def = CFG.List[gang]
    local here = GetEntityCoords(cache.ped)
    local side = math.random() * math.pi * 2
    local peds = {}

    for i = 1, math.max(1, math.min(12, count)) do
        local angle = side + (i - 1) * 0.12
        local distance = SPAWN_DISTANCE + math.random() * 6.0
        local x, y, z = footing(here.x + math.cos(angle) * distance, here.y + math.sin(angle) * distance, here.z)
        local model = i == 1 and def.leaderModel or def.models[math.random(#def.models)]
        local heading = GetHeadingFromVector_2d(here.x - x, here.y - y)
        local ped = world.spawnPed(model, vec4(x, y, z, heading))

        if ped then
            -- One of theirs in every sense: the same group as the crew's street members, so a
            -- kill counts the same and their friends nearby take it personally.
            if def.relGroups and def.relGroups[1] then SetPedRelationshipGroupHash(ped, def.relGroups[1]) end

            SetPedFleeAttributes(ped, 0, false)
            SetPedCombatAttributes(ped, 46, true) -- always fight
            SetPedCombatAttributes(ped, 5, true) -- fight armed peds when unarmed
            SetPedAccuracy(ped, 22)
            SetPedDropsWeaponsWhenDead(ped, false)
            SetPedCanRagdollFromPlayerImpact(ped, true)
            TaskGoToEntity(ped, cache.ped, -1, 2.0, 1.6, 1073741824, 0)

            peds[#peds + 1] = ped
        end
    end

    return peds
end

---Turn a crew on the player.
---@param crew TrapCrew
---@param weapons integer[] weapon hashes to arm them from
local function attack(crew, weapons)
    crew.hostile = true

    for _, ped in ipairs(crew.peds) do
        if DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true) then
            local weapon = weapons[math.random(#weapons)]

            SetBlockingOfNonTemporaryEvents(ped, false)
            GiveWeaponToPed(ped, weapon, 120, false, true)
            SetCurrentPedWeapon(ped, weapon, true)
            ClearPedTasks(ped)
            TaskCombatPed(ped, cache.ped, 0, 16)
            SetPedKeepTask(ped, true)
        end
    end
end

---Wind a crew down: the living walk off and everyone is removed a little later.
---@param crew TrapCrew
local function disperse(crew)
    if crew.done then return end
    crew.done = true

    for _, ped in ipairs(crew.peds) do
        if DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true) then
            SetPedKeepTask(ped, false)
            ClearPedTasks(ped)
            SetBlockingOfNonTemporaryEvents(ped, true)
            RemoveAllPedWeapons(ped, true)
            TaskWanderStandard(ped, 10.0, 10)
        end
    end

    SetTimeout(LEAVE_MS, function()
        for _, ped in ipairs(crew.peds) do world.release(ped) end
    end)
end

---Whether a crew has nobody left standing.
---@param crew TrapCrew
---@return boolean wiped
local function wiped(crew)
    for _, ped in ipairs(crew.peds) do
        if DoesEntityExist(ped) and not IsPedDeadOrDying(ped, true) then return false end
    end

    return true
end

---Whether a crew's business with the player is over: everyone is down, the player is down,
---the player got away, or it has simply gone on too long.
---@param crew TrapCrew
---@return boolean over
local function over(crew)
    if wiped(crew) or IsEntityDead(cache.ped) then return true end
    if GetGameTimer() - crew.started > FIGHT_MS then return true end

    local here = GetEntityCoords(cache.ped)

    for _, ped in ipairs(crew.peds) do
        if DoesEntityExist(ped) and #(here - GetEntityCoords(ped)) < ESCAPE_DISTANCE then return false end
    end

    return true
end

---End the current encounter and give the player back to the street.
local function endEncounter()
    local crew = encounter
    if not crew then return end

    encounter = nil
    world.setBusy('encounter', false)

    if crew.asking then lib.closeAlertDialog() end

    -- Walking away or dying before answering is an answer.
    if not crew.resolved and crew.id then
        crew.resolved = true
        CreateThread(function()
            lib.callback.await('sd-trapphone:server:encounterAnswer', false, crew.id, false)
        end)
    end

    disperse(crew)
end

---The leader makes the demand: pay or refuse, on a timer. No answer is a refusal.
---@param crew TrapCrew
---@param tax integer what they want
---@param seconds integer how long the player has
local function demand(crew, tax, seconds)
    local leader = crew.peds[1]
    local label = CFG.List[crew.gang].label

    if leader and DoesEntityExist(leader) then
        world.faceEachOther(cache.ped, leader)
        world.cinematic(leader, 2500, config.Selling.Cinematics.Encounters)
    end

    -- The handset and an ox_lib dialog can't both hold the cursor.
    phone.close()
    crew.asking = true

    SetTimeout(seconds * 1000, function()
        if crew.asking then lib.closeAlertDialog() end
    end)

    local choice = lib.alertDialog({
        header = locale('turf.tax_header', label),
        content = locale('turf.tax_content', tax, seconds),
        centered = true,
        cancel = true,
        labels = { confirm = locale('turf.tax_pay', tax), cancel = locale('turf.tax_refuse') },
    })

    crew.asking = false

    if encounter ~= crew or crew.resolved then return end

    crew.resolved = true

    local res = lib.callback.await('sd-trapphone:server:encounterAnswer', false, crew.id, choice == 'confirm')

    if encounter ~= crew then return end

    if res and res.ok and res.data.outcome == 'paid' then
        notify.show(locale('turf.tax_paid', label), 'success')
        endEncounter()
    else
        notify.show(locale('turf.tax_refused', label), 'error')
        world.setBusy('encounter', false)
        attack(crew, CFG.EncounterWeapons)
    end
end

-- A crew stepping to the player: created near them, walking up. Hostile standing skips the
-- talking.
RegisterNetEvent('sd-trapphone:client:encounter', function(data)
    if type(data) ~= 'table' or not CFG.List[data.gang] or encounter then return end
    if IsEntityDead(cache.ped) then return end

    local crew = {
        id = data.kind == 'tax' and data.id or nil,
        gang = data.gang,
        peds = spawnMembers(data.gang, data.members or 2),
        started = GetGameTimer(),
        hostile = false,
        resolved = data.kind ~= 'tax',
        asking = false,
        done = false,
    }

    encounter = crew

    if #crew.peds == 0 then
        log.debug('turf', 'no %s members could be created', data.gang)
        endEncounter()
        return
    end

    if data.kind ~= 'tax' then
        attack(crew, CFG.EncounterWeapons)
    else
        world.setBusy('encounter', true)

        CreateThread(function()
            local deadline = GetGameTimer() + ARRIVE_MS
            local leader = crew.peds[1]

            while encounter == crew and not crew.resolved and GetGameTimer() < deadline do
                if not DoesEntityExist(leader) or #(GetEntityCoords(leader) - GetEntityCoords(cache.ped)) <= TALK_DISTANCE then break end
                Wait(250)
            end

            if encounter == crew and not crew.resolved then demand(crew, data.tax or 0, data.seconds or 20) end
        end)
    end

    -- Watch for the end: a fight that is over, or a player who left or went down.
    CreateThread(function()
        while encounter == crew do
            Wait(1000)
            if encounter == crew and over(crew) then endEncounter() end
        end
    end)
end)

-- The server settled the demand itself (it timed out there): they stop waiting.
RegisterNetEvent('sd-trapphone:client:encounterResolve', function(id, outcome)
    local crew = encounter
    if not crew or crew.id ~= id or crew.resolved then return end

    crew.resolved = true
    if crew.asking then lib.closeAlertDialog() end

    if outcome == 'paid' then
        endEncounter()
    else
        world.setBusy('encounter', false)
        attack(crew, CFG.EncounterWeapons)
    end
end)

-- One riot wave: armed members created near the player, coming straight for them.
RegisterNetEvent('sd-trapphone:client:riotWave', function(data)
    if type(data) ~= 'table' or not CFG.List[data.gang] or IsEntityDead(cache.ped) then return end

    local crew = {
        gang = data.gang,
        peds = spawnMembers(data.gang, data.members or 4),
        started = GetGameTimer(),
        hostile = false,
        resolved = true,
        asking = false,
        done = false,
    }

    if #crew.peds == 0 then return end

    waves[#waves + 1] = crew
    attack(crew, CFG.RiotWeapons)

    CreateThread(function()
        while not crew.done do
            Wait(1000)
            if not crew.done and over(crew) then disperse(crew) end
        end

        for i = #waves, 1, -1 do
            if waves[i] == crew then table.remove(waves, i) end
        end
    end)
end)

-- The riot burned out or was paid off: whoever is left goes home.
RegisterNetEvent('sd-trapphone:client:riotEnd', function(gang)
    for _, crew in ipairs(waves) do
        if crew.gang == gang then disperse(crew) end
    end
end)

-- Tell the server when the player kills one of a crew's members, ours or the street's. The
-- server decides whether it counts (pace, and whether the player is on that crew's ground).
AddEventHandler('gameEventTriggered', function(name, args)
    if name ~= 'CEventNetworkEntityDamage' or not CFG.Enabled then return end

    local victim, attacker = args[1], args[2]

    if not victim or victim == 0 or reported[victim] or not DoesEntityExist(victim) then return end
    if attacker ~= cache.ped and not (cache.vehicle and cache.seat == -1 and attacker == cache.vehicle) then return end
    if not IsEntityAPed(victim) or IsPedAPlayer(victim) or not IsPedDeadOrDying(victim, true) then return end

    local gang = groupToGang[GetPedRelationshipGroupHash(victim)]
    if not gang then return end

    -- Handles are reused by the game, so the list is thrown away now and then.
    if reportedCount > 256 then reported, reportedCount = {}, 0 end

    reported[victim] = true
    reportedCount += 1

    TriggerServerEvent('sd-trapphone:server:gangKill', gang)
end)

RegisterNUICallback('trap:turf:refresh', function(_, cb)
    local res = lib.callback.await('sd-trapphone:server:turfRefresh', false)

    cb(type(res) == 'table' and res or { ok = false, error = locale('turf.no_phone') })
end)

---Whether a crew is stepping to the player or a riot wave is on them.
---@return boolean active
function turf.underPressure()
    return encounter ~= nil or #waves > 0
end

return turf
