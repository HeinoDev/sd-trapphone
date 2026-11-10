---@type table sd-trapphone config root (configs/config.lua).
local config = require 'configs.config'
---@type table Console log helper (shared.log).
local log = require 'shared.log'
---@type table Turf map resolver (shared.zones).
local zones = require 'shared.zones'
---@type table Audit-log helper (server.trapphone.audit).
local audit = require 'server.trapphone.audit'
---@type table Live phones (server.trapphone.phones).
local phones = require 'server.trapphone.phones'
---@type table Signed standing values (server.trapphone.relations).
local relations = require 'server.trapphone.relations'
---@type table Back-room services (server.trapphone.services): also owns charge / refund.
local services = require 'server.trapphone.services'
---@type table Player bridge (bridge.server.player): identifier and job lookups.
local playerBridge = require 'bridge.server.player'
---@type table Notify bridge (bridge.server.notify).
local notify = require 'bridge.server.notify'

---@type table Gang config (config.Gangs): the shared display half merged with the server numbers.
local CFG = config.Gangs
---@type table Encounter rules (config.Gangs.Encounter).
local ENC = CFG.Encounter
---@type table Riot rules (config.Gangs.Riot).
local RIOT = CFG.Riot
---@type table Contact and gang texts (config.Lines).
local LINES = config.Lines

---@class TrapEncounter
---@field id integer
---@field gang string key of config.Gangs.List
---@field tax integer what they want
---@field owner string who the standing belongs to (character id or shared job name)
---@field cid string character id of the player stepped to
---@field expires integer os.time() after which no answer counts as refusing

---@class TrapRiot
---@field job string the shared-rep job being rioted against
---@field gang string key of config.Gangs.List
---@field wave integer waves sent so far
---@field over boolean set when it is paid off, so the wave loop stops

---@type table Turf module; the table returned at end of file. Which ground a player stands on,
---what the crew that holds it thinks of them, and what that crew does about it.
local turf = {}

---@type table<string, boolean> Jobs the crews leave alone, as a set.
local IGNORED = {}
---@type table<string, boolean> Jobs that share one standing per crew, as a set.
local SHARED = {}

for _, job in ipairs(CFG.IgnoredJobs or {}) do IGNORED[job] = true end
for _, job in ipairs(CFG.SharedJobRep or {}) do SHARED[job] = true end

---@type table[] config.Gangs.Standings, lowest `from` first.
local STANDINGS = {}

for i = 1, #CFG.Standings do STANDINGS[i] = CFG.Standings[i] end
table.sort(STANDINGS, function(a, b) return a.from < b.from end)

---@type integer Seconds a crew gets to walk up before the answer timer would have started.
local ARRIVE_GRACE = 45
---@type integer Most gang-kill reports accepted from one player per minute.
local KILLS_PER_MINUTE = 12
---@type integer Milliseconds that must pass between two gang-kill reports from one player.
local KILL_GAP_MS = 750

---@type table<string, table<string, integer>> Money made on a crew's ground since the last
---tax, by character id then gang.
local tally = {}
---@type table<integer, TrapEncounter> The tax demand each player has yet to answer, by server id.
local encounters = {}
---@type table<integer, integer> os.time() of each player's last encounter, by server id.
local lastEncounter = {}
---@type integer Last encounter id handed out.
local encounterSeq = 0
---@type table<integer, { last: integer, stamps: integer[], flagged: integer }> Gang-kill report
---pacing per player.
local killPace = {}
---@type table<string, integer[]> os.time() of each recent kill, by 'job|gang'.
local riotKills = {}
---@type table<string, TrapRiot> Riots in progress, by 'job|gang'.
local riots = {}
---@type table<string, integer> os.time() each riot last ended, by 'job|gang'.
local lastRiot = {}
---@type table<integer, { at: integer, data: table }> Last turf snapshot per player, for pacing refreshes.
local lastSnapshot = {}

---One random line from a list, formatted. A broken translation never errors a sale.
---@param list string[]|nil
---@param ... any format arguments
---@return string|nil text
local function line(list, ...)
    if type(list) ~= 'table' or #list == 0 then return nil end

    local ok, text = pcall(string.format, list[math.random(#list)], ...)

    return ok and text or nil
end

---A player's real position, or nil when they have no ped yet.
---@param src integer player server id
---@return vector3|nil coords
local function coordsOf(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end

    return GetEntityCoords(ped)
end

---The turf a player is standing on, from their real position.
---@param src integer player server id
---@return table zone TrapZone (shared.zones); the default zone when they have no position
function turf.zoneOf(src)
    local coords = coordsOf(src)
    if not coords then return config.Zones.Default end

    return zones.at(coords.x, coords.y)
end

---Whether the crews leave this player alone entirely (config.Gangs.IgnoredJobs).
---@param src integer player server id
---@return boolean ignored
function turf.isIgnored(src)
    if not CFG.Enabled then return true end

    local job = playerBridge.getJob(src)

    return job ~= nil and IGNORED[job] == true
end

---Who a player's gang standing belongs to: their job when it shares one, else their character.
---@param src integer player server id
---@return string|nil owner relations owner key
---@return string|nil job the shared-rep job, when that is the owner
function turf.ownerOf(src)
    local job = playerBridge.getJob(src)
    if job and SHARED[job] then return job, job end

    return playerBridge.getIdentifier(src), nil
end

---How a rep number reads: the standing with the highest `from` that fits.
---@param rep integer -100..100
---@return table standing { from, id, label }
---@return integer rank position in the ladder, 1 = worst
function turf.standing(rep)
    local found, rank = STANDINGS[1], 1

    for i = 1, #STANDINGS do
        if rep >= STANDINGS[i].from then found, rank = STANDINGS[i], i end
    end

    return found, rank
end

---An owner's rep with a crew.
---@param owner string character id or shared job name
---@param gang string key of config.Gangs.List
---@return integer rep -100..100
function turf.rep(owner, gang)
    return relations.get(owner, 'gang', gang, CFG.StartRep)
end

---Move an owner's rep with a crew.
---@param owner string character id or shared job name
---@param gang string key of config.Gangs.List
---@param delta integer
---@return integer rep the value after the change
function turf.addRep(owner, gang, delta)
    return relations.add(owner, 'gang', gang, math.floor(delta), -100, 100, CFG.StartRep)
end

---When an owner's bought protection on a crew's ground runs out.
---@param owner string character id or shared job name
---@param gang string key of config.Gangs.List
---@return integer|nil untilTs os.time() expiry, nil when not protected
function turf.protectedUntil(owner, gang)
    local untilTs = relations.get(owner, 'protect', gang, 0)

    return untilTs > os.time() and untilTs or nil
end

---How much a zone of some wealth wants one product family: how many of the family's sizes
---list that wealth tier in config.Economy.Prices[item].demand.
---@param family string key of config.Drugs.Families
---@param wealth integer 0..5
---@return 'low'|'normal'|'high' level
---@return number share 0..1 of the family's sizes that are craved there
function turf.demand(family, wealth)
    local sizes, craved = 0, 0

    for item, info in pairs(config.Drugs.Items) do
        local price = info.family == family and config.Economy.Prices[item]

        if price then
            sizes += 1
            if price.demand and lib.table.contains(price.demand, wealth) then craved += 1 end
        end
    end

    if sizes == 0 or craved == 0 then return 'low', 0.0 end
    if craved == sizes then return 'high', 1.0 end

    return 'normal', craved / sizes
end

---The zone that wants a product family most right now (a random one of the best).
---@param family string key of config.Drugs.Families
---@return table|nil zone TrapZone, nil when nowhere wants it
function turf.hotZone(family)
    local best, bestShare = {}, 0.0

    for _, zone in ipairs(config.Zones.Areas) do
        local _, share = turf.demand(family, zone.wealth)

        if share > bestShare then
            best, bestShare = { zone }, share
        elseif share == bestShare and share > 0.0 then
            best[#best + 1] = zone
        end
    end

    return best[1] and best[math.random(#best)] or nil
end

---Police heat on a player, from the dispatch module. Required here, not at the top, so the
---two files can load in either order.
---@param src integer player server id
---@return integer heat 0..100
local function heatOf(src)
    local ok, value = pcall(function()
        return require('server.trapphone.dispatch').heat(src)
    end)

    if not ok or type(value) ~= 'number' then return 0 end

    return math.floor(math.max(0, math.min(100, value)))
end

---The handset's Turf section for a player (docs/design.md).
---@param src integer player server id
---@return table turf
function turf.snapshot(src)
    local zone = turf.zoneOf(src)
    local out = {
        zone = { id = zone.id, label = zone.label, wealth = zone.wealth, wealthLabel = zones.wealthLabel(zone.wealth) },
        heat = heatOf(src),
        demand = {},
    }

    local gang = CFG.Enabled and zone.gang and CFG.List[zone.gang]
    local owner = gang and turf.ownerOf(src)

    if gang and owner then
        local standing = turf.standing(turf.rep(owner, zone.gang))

        out.gang = {
            id = zone.gang,
            label = gang.label,
            color = gang.color,
            standing = standing.id,
            standingLabel = standing.label,
            protectedUntil = turf.protectedUntil(owner, zone.gang),
        }
    end

    for family, info in pairs(config.Drugs.Families) do
        out.demand[#out.demand + 1] = {
            family = family,
            label = info.label,
            color = info.color,
            level = turf.demand(family, zone.wealth),
        }
    end

    table.sort(out.demand, function(a, b) return a.label < b.label end)

    return out
end

---Re-send the Turf section to a player's handset, if they carry one.
---@param src integer player server id
local function refresh(src)
    local phone = phones.current(src)
    if phone then phones.refresh(phone, 'turf') end
end

---The number and name a crew texts from: its shot caller when one is configured.
---@param gang string key of config.Gangs.List
---@return string|nil number
---@return string name
---@return string|nil key the contact's key
local function voiceOf(gang)
    for _, contact in ipairs(config.Contacts.List or {}) do
        if contact.type == 'gang' and contact.gang == gang then return contact.number, contact.name, contact.key end
    end

    return nil, CFG.List[gang].label, nil
end

---Text a player's phone as a crew. From the shot caller under their own name once met, from
---the same number under the crew's name before that.
---@param src integer player server id
---@param gang string key of config.Gangs.List
---@param text string|nil
local function textFrom(src, gang, text)
    local phone = phones.current(src)
    if not phone or not text then return end

    local number, name, key = voiceOf(gang)
    if not number then return end

    local met = key and phone.data.met[key]

    phones.message(phone, number, { from = 'them', text = text },
        { name = met and name or CFG.List[gang].label, kind = met and 'contact' or 'system' })
end

---Send a crew at a player: a tax demand, or a straight attack when they are hated.
---@param src integer player server id
---@param gang string key of config.Gangs.List
---@param kind? 'tax'|'attack' forced kind (debug); picked from standing when omitted
---@return boolean started
function turf.startEncounter(src, gang, kind)
    if not CFG.List[gang] or encounters[src] then return false end

    local owner = turf.ownerOf(src)
    local cid = playerBridge.getIdentifier(src)
    if not owner or not cid then return false end

    local standing = turf.standing(turf.rep(owner, gang))
    local made = tally[cid] and tally[cid][gang] or 0
    local tax = math.max(ENC.TaxMin, math.floor(made * ENC.TaxShare))

    kind = kind or (standing.id == 'hostile' and 'attack' or 'tax')
    encounterSeq += 1
    lastEncounter[src] = os.time()

    local id = encounterSeq

    if kind == 'tax' then
        encounters[src] = { id = id, gang = gang, tax = tax, owner = owner, cid = cid, expires = os.time() + ENC.AnswerSeconds + ARRIVE_GRACE }
        textFrom(src, gang, line(LINES.tax.demand, tax))

        -- No answer counts as refusing, even when the client never asks.
        SetTimeout((ENC.AnswerSeconds + ARRIVE_GRACE) * 1000, function()
            local enc = encounters[src]
            if not enc or enc.id ~= id then return end

            turf.resolveEncounter(src, false)
            TriggerClientEvent('sd-trapphone:client:encounterResolve', src, id, 'refused')
        end)
    end

    TriggerClientEvent('sd-trapphone:client:encounter', src, {
        id = id,
        gang = gang,
        kind = kind,
        members = math.random(ENC.Members.min, ENC.Members.max),
        tax = tax,
        seconds = ENC.AnswerSeconds,
    })

    log.debug('turf', '%s stepped to player %d (%s, $%d)', gang, src, kind, tax)

    return true
end

---Settle a player's open tax demand.
---@param src integer player server id
---@param pay boolean true to pay, false to refuse
---@return 'paid'|'refused'|nil outcome nil when there was nothing to settle
---@return boolean broke true when they chose to pay and could not
function turf.resolveEncounter(src, pay)
    local enc = encounters[src]
    if not enc then return nil, false end

    encounters[src] = nil

    local broke = false

    if pay then
        if services.charge(src, CFG.PayWith, enc.tax, 'trapphone-tax') then
            turf.addRep(enc.owner, enc.gang, CFG.Rep.PerTaxPaid)
            if tally[enc.cid] then tally[enc.cid][enc.gang] = 0 end

            audit.log('tax', src, ('paid $%d turf tax to %s'):format(enc.tax, enc.gang), { gang = enc.gang, tax = enc.tax, paid = true })
            textFrom(src, enc.gang, line(LINES.tax.paid))
            refresh(src)

            return 'paid', false
        end

        broke = true
    end

    turf.addRep(enc.owner, enc.gang, CFG.Rep.PerTaxRefused)
    audit.log('tax', src, ('refused $%d turf tax to %s'):format(enc.tax, enc.gang), { gang = enc.gang, tax = enc.tax, paid = false, broke = broke })
    textFrom(src, enc.gang, line(LINES.tax.refused))
    refresh(src)

    return 'refused', broke
end

---A sale just completed. Moves the crew's opinion of the seller, counts what they made on the
---crew's ground and maybe sends the crew over.
---@param src integer player server id
---@param phone table TrapPhone the sale was made on
---@param zone table TrapZone the sale happened in (from the seller's real position)
---@param total number what the sale paid
function turf.onSale(src, phone, zone, total)
    if not CFG.Enabled or type(zone) ~= 'table' or not zone.gang or not CFG.List[zone.gang] then return end
    if turf.isIgnored(src) then return end

    local owner = turf.ownerOf(src)
    local cid = playerBridge.getIdentifier(src)
    if not owner or not cid then return end

    local gang = zone.gang

    if turf.protectedUntil(owner, gang) then
        turf.addRep(owner, gang, CFG.Rep.PerSaleProtected)
        if phone then phones.refresh(phone, 'turf') end
        return
    end

    local rep = turf.addRep(owner, gang, CFG.Rep.PerSaleOnTurf)

    tally[cid] = tally[cid] or {}
    tally[cid][gang] = (tally[cid][gang] or 0) + math.max(0, math.floor(tonumber(total) or 0))

    if phone then phones.refresh(phone, 'turf') end

    if encounters[src] or os.time() - (lastEncounter[src] or 0) < ENC.Cooldown then return end

    local chance = ENC.Chance[turf.standing(rep).id] or 0

    if chance > 0 and math.random(100) <= chance then turf.startEncounter(src, gang) end
end

---The riot a player's job is facing from a crew, if any.
---@param src integer player server id
---@param gang string key of config.Gangs.List
---@return TrapRiot|nil riot
---@return string|nil key 'job|gang'
local function riotAgainst(src, gang)
    local _, job = turf.ownerOf(src)
    if not job then return nil end

    local key = job .. '|' .. gang

    return riots[key], key
end

---Every online player of a job who is standing on a crew's ground.
---@param job string
---@param gang string key of config.Gangs.List
---@return integer[] sources
local function jobOnTurf(job, gang)
    local out = {}

    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id) --[[@as integer]]

        if playerBridge.getJob(src) == job and turf.zoneOf(src).gang == gang then out[#out + 1] = src end
    end

    return out
end

---Close a riot: the job's standing is reset and the crew can't riot again for a while.
---@param key string 'job|gang'
---@param paidBy? integer server id of the player who paid it off
local function endRiot(key, paidBy)
    local riot = riots[key]
    if not riot then return end

    riot.over = true
    riots[key] = nil
    riotKills[key] = nil
    lastRiot[key] = os.time()
    relations.set(riot.job, 'gang', riot.gang, RIOT.RepAfter)

    audit.log('riot', paidBy or 'system', ('%s riot against %s ended%s'):format(riot.gang, riot.job, paidBy and ' (paid off)' or ''),
        { gang = riot.gang, job = riot.job, waves = riot.wave, paidOff = paidBy ~= nil })

    local label = CFG.List[riot.gang].label

    for _, src in ipairs(jobOnTurf(riot.job, riot.gang)) do
        TriggerClientEvent('sd-trapphone:client:riotEnd', src, riot.gang)
        notify.to(src, line(LINES.riot.over, label) or locale('turf.riot_over', label), 'info')
        refresh(src)
    end
end

---Start a riot: waves of armed members go after the job's players on the crew's ground.
---@param job string the shared-rep job
---@param gang string key of config.Gangs.List
local function startRiot(job, gang)
    local key = job .. '|' .. gang
    local riot = { job = job, gang = gang, wave = 0, over = false }
    local label = CFG.List[gang].label

    riots[key] = riot
    audit.log('riot', 'system', ('%s riot against %s started'):format(gang, job), { gang = gang, job = job })
    log.info('turf', '%s are rioting against %s', gang, job)

    CreateThread(function()
        for wave = 1, RIOT.Waves do
            if riot.over then return end

            riot.wave = wave

            for _, src in ipairs(jobOnTurf(job, gang)) do
                if not turf.isIgnored(src) then
                    TriggerClientEvent('sd-trapphone:client:riotWave', src, {
                        gang = gang,
                        wave = wave,
                        waves = RIOT.Waves,
                        members = math.random(RIOT.MembersPerWave.min, RIOT.MembersPerWave.max),
                    })
                    notify.to(src, wave == 1 and (line(LINES.riot.start, label) or locale('turf.riot_start', label))
                        or (line(LINES.riot.wave, wave, RIOT.Waves) or locale('turf.riot_wave', wave, RIOT.Waves)), 'error')
                end
            end

            Wait(RIOT.SecondsBetweenWaves * 1000)
        end

        if not riot.over then endRiot(key) end
    end)
end

---Count one kill by a shared-rep job against a crew and start a riot when there are enough.
---@param job string the shared-rep job
---@param gang string key of config.Gangs.List
local function countRiotKill(job, gang)
    if not RIOT.Enabled then return end

    local key = job .. '|' .. gang
    local now = os.time()
    local recent = {}

    for _, stamp in ipairs(riotKills[key] or {}) do
        if now - stamp < RIOT.WindowMinutes * 60 then recent[#recent + 1] = stamp end
    end

    recent[#recent + 1] = now
    riotKills[key] = recent

    if #recent < RIOT.KillsToTrigger or riots[key] then return end
    if now - (lastRiot[key] or 0) < RIOT.Cooldown then return end

    startRiot(job, gang)
end

---What buying a crew's protection (or paying off its riot) would cost a player.
---@param src integer player server id
---@param gang string key of config.Gangs.List
---@return { price: integer, hours: integer, allowed: boolean, reason?: string, riot?: boolean } quote
function turf.bribeQuote(src, gang)
    local owner = turf.ownerOf(src)

    if not CFG.Enabled or not CFG.List[gang] or not owner then
        return { price = CFG.Bribe.Price, hours = CFG.Bribe.Hours, allowed = false, reason = locale('turf.bribe_unavailable') }
    end

    if riotAgainst(src, gang) then
        return { price = RIOT.PayOffPrice, hours = 0, allowed = true, riot = true }
    end

    local _, rank = turf.standing(turf.rep(owner, gang))
    local needed = 1

    for i = 1, #STANDINGS do
        if STANDINGS[i].id == CFG.Bribe.MinStanding then needed = i end
    end

    if rank < needed then
        return { price = CFG.Bribe.Price, hours = CFG.Bribe.Hours, allowed = false, reason = locale('turf.bribe_refused') }
    end

    return { price = CFG.Bribe.Price, hours = CFG.Bribe.Hours, allowed = true }
end

---Pay a crew: protection on its ground for a while, or an end to the riot it is running
---against the player's job.
---@param src integer player server id
---@param gang string key of config.Gangs.List
---@return boolean ok
---@return table|string result { price, hours, protectedUntil?, riot? } on success, a localized error otherwise
function turf.bribe(src, gang)
    local quote = turf.bribeQuote(src, gang)
    local owner = turf.ownerOf(src)

    if not quote.allowed or not owner then
        textFrom(src, gang, line(LINES.bribe.refused))
        return false, quote.reason or locale('turf.bribe_unavailable')
    end

    if not services.charge(src, CFG.PayWith, quote.price, 'trapphone-bribe') then
        return false, locale('turf.cant_afford', quote.price)
    end

    if quote.riot then
        local _, key = riotAgainst(src, gang)

        endRiot(key --[[@as string]], src)
        audit.log('bribe', src, ('paid $%d to call off the %s riot'):format(quote.price, gang), { gang = gang, price = quote.price, riot = true })
        textFrom(src, gang, line(LINES.riot.paidOff))

        return true, { price = quote.price, hours = 0, riot = true }
    end

    local from = turf.protectedUntil(owner, gang) or os.time()
    local untilTs = relations.set(owner, 'protect', gang, from + CFG.Bribe.Hours * 3600)

    turf.addRep(owner, gang, CFG.Rep.PerBribe)
    audit.log('bribe', src, ('paid $%d for %d hours of %s protection'):format(quote.price, CFG.Bribe.Hours, gang),
        { gang = gang, price = quote.price, hours = CFG.Bribe.Hours, owner = owner })
    textFrom(src, gang, line(LINES.bribe.paid, CFG.Bribe.Hours))
    refresh(src)

    return true, { price = quote.price, hours = CFG.Bribe.Hours, protectedUntil = untilTs }
end

phones.addPart('turf', function(src)
    return turf.snapshot(src)
end)

-- The Turf screen asking for a fresh read. Paced, because the page may ask on every open.
lib.callback.register('sd-trapphone:server:turfRefresh', function(src)
    if not phones.current(src) then return { ok = false, error = locale('turf.no_phone') } end

    local now = GetGameTimer()
    local last = lastSnapshot[src]

    if last and now - last.at < 1000 then return { ok = true, data = last.data } end

    local data = turf.snapshot(src)

    lastSnapshot[src] = { at = now, data = data }

    return { ok = true, data = data }
end)

-- The answer to a tax demand. The id must be the one this player was given.
lib.callback.register('sd-trapphone:server:encounterAnswer', function(src, id, pay)
    local enc = encounters[src]

    if type(id) ~= 'number' or type(pay) ~= 'boolean' or not enc or enc.id ~= id then
        if enc or type(id) ~= 'number' then
            audit.log('suspect', src, 'answered a tax demand that is not theirs', { id = tostring(id), expected = enc and enc.id })
        end

        return { ok = false, error = locale('turf.encounter_over') }
    end

    if os.time() > enc.expires then pay = false end

    local outcome, broke = turf.resolveEncounter(src, pay)

    if broke then notify.to(src, locale('turf.cant_afford', enc.tax), 'error') end

    return { ok = true, data = { outcome = outcome, broke = broke } }
end)

-- A client saying its player killed one of a crew's members. Believed only at a sane pace and
-- only on that crew's own ground, checked against the reporter's real position.
RegisterNetEvent('sd-trapphone:server:gangKill', function(gang)
    local src = source
    if not CFG.Enabled or type(gang) ~= 'string' or not CFG.List[gang] then return end

    local now, nowMs = os.time(), GetGameTimer()
    local pace = killPace[src]

    if not pace then
        pace = { last = 0, stamps = {}, flagged = 0 }
        killPace[src] = pace
    end

    local recent = {}

    for _, stamp in ipairs(pace.stamps) do
        if now - stamp < 60 then recent[#recent + 1] = stamp end
    end

    pace.stamps = recent

    if nowMs - pace.last < KILL_GAP_MS or #recent >= KILLS_PER_MINUTE then
        if now - pace.flagged >= 60 then
            pace.flagged = now
            audit.log('suspect', src, 'gang kill reports faster than anyone shoots', { gang = gang, lastMinute = #recent })
        end

        return
    end

    pace.last = nowMs
    recent[#recent + 1] = now

    if turf.zoneOf(src).gang ~= gang or turf.isIgnored(src) then return end

    local owner, job = turf.ownerOf(src)
    if not owner then return end

    turf.addRep(owner, gang, CFG.Rep.PerMemberKilled)
    refresh(src)

    if job then countRiotKill(job, gang) end
end)

AddEventHandler('playerDropped', function()
    local src = source

    encounters[src] = nil
    lastEncounter[src] = nil
    killPace[src] = nil
    lastSnapshot[src] = nil
end)

return turf
