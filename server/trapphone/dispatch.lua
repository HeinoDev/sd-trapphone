---@type table sd-trapphone config root (configs/config.lua).
local config = require 'configs.config'
---@type table Console log helper (shared.log).
local log = require 'shared.log'
---@type table Audit-log helper (server.trapphone.audit).
local audit = require 'server.trapphone.audit'
---@type table Live phones (server.trapphone.phones).
local phones = require 'server.trapphone.phones'
---@type table Job bridge (bridge.server.job): job name lookups.
local job = require 'bridge.server.job'

---@type table Police pressure config (config.Dispatch).
local CFG = config.Dispatch
---@type table Snitch odds and timings (config.Dispatch.Snitch).
local SNITCH = CFG.Snitch or {}
---@type table Heat numbers (config.Dispatch.Heat).
local HEAT = CFG.Heat or {}
---@type table How an alert looks on the dispatch (config.Dispatch.Alert).
local ALERT = CFG.Alert or {}

---@type integer Seconds a police head count is reused before the player list is walked again.
local COUNT_TTL = 15

---@type table Dispatch module; the table returned at end of file. Police pressure on a seller:
---how many officers are on, how hot the player is, and getting an alert out to the police.
local dispatch = {}

---@type table<string, boolean> Police job names as a set.
local POLICE = {}
for _, name in ipairs(CFG.PoliceJobs or {}) do
    POLICE[name] = true
end

---@type { count: integer, at: integer } Last police head count and when it was taken.
local counted = { count = 0, at = 0 }
---@type table<integer, { value: number, at: integer }> Heat per player server id, with the
---time it was last brought up to date.
local heat = {}
---@type table<integer, integer> os.time() of the last alert sent about each player.
local lastAlert = {}
---@type table<integer, integer> os.time() of the last snitch call rolled against each player.
local lastSnitch = {}

---How many players with a police job are online. The answer is reused for a few seconds so a
---busy corner doesn't walk the player list on every customer.
---@return integer count
function dispatch.policeCount()
    local now = os.time()
    if now - counted.at < COUNT_TTL then return counted.count end

    local count = 0

    for _, id in ipairs(GetPlayers()) do
        local name = job.getName(tonumber(id))
        if name and POLICE[name] then count += 1 end
    end

    counted.count, counted.at = count, now

    return count
end

---Whether a player is police (they are never alerted about themselves selling, and the turf
---code asks too).
---@param src integer player server id
---@return boolean police
function dispatch.isPolice(src)
    local name = job.getName(src)

    return name ~= nil and POLICE[name] == true
end

---Whether selling may start or carry on right now.
---@return boolean ok
---@return string|nil reason localized, when not ok
function dispatch.canSell()
    if not CFG.CheckForPolice then return true end

    if dispatch.policeCount() < (CFG.RequiredPolice or 0) then
        return false, locale('dispatch.not_enough_police')
    end

    return true
end

---Bring a player's stored heat up to date: it cools by CoolPerMinute for the time that passed.
---@param src integer player server id
---@return { value: number, at: integer } entry
local function cooled(src)
    local now = os.time()
    local entry = heat[src]

    if not entry then
        entry = { value = 0, at = now }
        heat[src] = entry
    end

    local minutes = (now - entry.at) / 60
    if minutes > 0 then
        entry.value = math.max(0, entry.value - minutes * (HEAT.CoolPerMinute or 0))
        entry.at = now
    end

    return entry
end

---How hot a player is right now.
---@param src integer player server id
---@return integer heat 0..100
function dispatch.heat(src)
    return math.floor(cooled(src).value + 0.5)
end

---Raise (or lower) a player's heat and redraw it on their phone.
---@param src integer player server id
---@param amount number points to add
---@return integer heat the heat afterwards
function dispatch.addHeat(src, amount)
    local entry = cooled(src)

    entry.value = math.max(0, math.min(100, entry.value + amount))

    local phone = phones.current(src)
    if phone then phones.refresh(phone, 'turf') end

    return math.floor(entry.value + 0.5)
end

---The text an alert carries for a reason, falling back to the configured title.
---@param reason string|nil why the alert went out ('snitch', 'witness', 'sale', 'wash', ...)
---@return string message
local function reasonText(reason)
    if type(reason) == 'string' then
        local key = ('dispatch.reason_%s'):format(reason)
        local text = locale(key)
        if text and text ~= key then return text end
    end

    return ALERT.title or 'Suspected drug deal'
end

---Send a police alert about a player. Held back by the per-player cooldown. Raises their heat
---and tells their own client to fire the dispatch bridge, since every supported dispatch
---resource is driven from the suspect's client.
---@param src integer player server id
---@param reason? string why ('snitch', 'witness', 'sale', 'wash', ...); picks the message
---@param coords? vector3 where it happened; the player's position when omitted
---@return boolean sent
function dispatch.alert(src, reason, coords)
    if not GetPlayerName(src) then return false end

    local now = os.time()
    if lastAlert[src] and now - lastAlert[src] < (CFG.Cooldown or 0) then return false end

    lastAlert[src] = now

    if not coords then
        local ped = GetPlayerPed(src)
        if ped and ped ~= 0 then coords = GetEntityCoords(ped) end
    end

    local level = dispatch.addHeat(src, HEAT.PerAlert or 0)

    TriggerClientEvent('sd-trapphone:client:alert', src, {
        code = ALERT.code,
        title = ALERT.title,
        message = reasonText(reason),
        sprite = ALERT.sprite,
        colour = ALERT.colour,
        scale = ALERT.scale,
        blipSeconds = ALERT.blipSeconds,
        jobs = CFG.PoliceJobs,
        coords = coords and { x = coords.x, y = coords.y, z = coords.z } or nil,
    })

    audit.log('snitch', src, ('police alerted (%s), heat now %d'):format(tostring(reason or 'unknown'), level),
        { reason = reason, heat = level })
    log.debug('dispatch', 'alert about %s (%s), heat %d', src, tostring(reason), level)

    return true
end

---Roll for someone reporting a player, and if they do, send the alert after a delay from
---where the player was standing when it happened. In Simple mode a sale rolls SimpleChance
---and alerts straight away, and refused pitches report nothing.
---@param src integer player server id
---@param scale? number multiplier on the odds (the witness's personality `snitch` value)
---@param kind? 'pitch'|'witness' a refused pitch (Snitch.Chance) or a seen sale (Snitch.WitnessChance)
---@return boolean rolled whether a call is on its way
function dispatch.snitch(src, scale, kind)
    if dispatch.isPolice(src) then return false end

    if CFG.Simple then
        if kind == 'pitch' then return false end
        if math.random() * 100 >= (CFG.SimpleChance or 0) then return false end

        return dispatch.alert(src, 'sale')
    end

    local now = os.time()
    if lastSnitch[src] and now - lastSnitch[src] < (SNITCH.Timeout or 0) then return false end

    local base = kind == 'pitch' and (SNITCH.Chance or 0) or (SNITCH.WitnessChance or 0)
    local heatScale = 1 + ((HEAT.SnitchScaleAtMax or 1) - 1) * dispatch.heat(src) / 100
    local odds = base * (tonumber(scale) or 1) * heatScale

    if math.random() * 100 >= odds then return false end

    lastSnitch[src] = now

    local ped = GetPlayerPed(src)
    local coords = ped and ped ~= 0 and GetEntityCoords(ped) or nil
    local delay = SNITCH.DelaySeconds or { min = 0, max = 0 }
    local seconds = math.random(delay.min or 0, math.max(delay.min or 0, delay.max or 0))
    local reason = kind == 'pitch' and 'snitch' or 'witness'

    SetTimeout(seconds * 1000, function()
        dispatch.alert(src, reason, coords)
    end)

    return true
end

---Forget a player's pressure when they leave, so a reused server id starts clean.
AddEventHandler('playerDropped', function()
    local src = source

    heat[src] = nil
    lastAlert[src] = nil
    lastSnitch[src] = nil
end)

return dispatch
