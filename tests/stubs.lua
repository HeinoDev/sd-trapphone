-- A fake FiveM server for the offline harness. Installs the globals the resource's server
-- files expect (natives, ox_lib, vectors) and preloads fakes for every module that talks to a
-- live framework or database, backed by plain tables the tests can read and change.
local L = require 'loader'

local S = {
    clock = 1700000000, -- what os.time() returns; tests move it forward
    timer = 0, -- what GetGameTimer() returns
    force = nil, -- when set, every math.random roll lands on this point of its range (0..1)
    players = {},
    callbacks = {},
    handlers = {},
    threads = {},
    timeouts = {},
    sent = {}, -- TriggerClientEvent calls, in order
    logs = {}, -- audit lines, in order
    turfSales = {},
    strings = {}, -- locales/en.json flattened
}

-- Vectors: enough of the CfxLua vector types for distance maths and swizzles.
local V = {}

local function vec(x, y, z, w)
    return setmetatable({ x = x, y = y, z = z, w = w }, V)
end

V.__index = function(t, k)
    if k == 'xyz' then return vec(t.x, t.y, t.z) end
    if k == 'xy' then return vec(t.x, t.y) end
    return nil
end
V.__sub = function(a, b) return vec(a.x - b.x, a.y - b.y, (a.z or 0) - (b.z or 0)) end
V.__len = function(a) return math.sqrt(a.x * a.x + a.y * a.y + (a.z or 0) * (a.z or 0)) end

function vec2(x, y) return vec(x + 0.0, y + 0.0) end
function vec3(x, y, z) return vec(x + 0.0, y + 0.0, z + 0.0) end
function vec4(x, y, z, w) return vec(x + 0.0, y + 0.0, z + 0.0, w + 0.0) end
vector3 = vec3

function joaat(text)
    local h = 0
    for i = 1, #text do h = (h * 31 + text:lower():byte(i)) & 0x7FFFFFFF end
    return h
end

-- Time and randomness under test control.
local realRandom = math.random

os.time = function() return S.clock end
function GetGameTimer() return S.timer end

math.random = function(m, n)
    if not S.force then
        if m == nil then return realRandom() end
        if n == nil then return realRandom(m) end
        return realRandom(m, n)
    end

    if m == nil then return S.force end
    if n == nil then m, n = 1, m end

    return math.min(n, m + math.floor(S.force * (n - m + 1)))
end

math.randomseed = function() end

---Move both clocks forward.
---@param seconds number
function S.advance(seconds)
    S.clock = S.clock + seconds
    S.timer = S.timer + seconds * 1000
end

-- Threads, timers and events. A thread is a coroutine that is resumed once per S.pump(), so a
-- `while true do Wait(n) ... end` loop runs one pass of its body per pump.
function CreateThread(fn) S.threads[#S.threads + 1] = coroutine.create(fn) end
function Wait(ms) if coroutine.isyieldable() then coroutine.yield(ms) end end
function SetTimeout(_, fn) S.timeouts[#S.timeouts + 1] = fn end

function S.pump()
    for i = 1, #S.threads do
        local co = S.threads[i]
        if coroutine.status(co) == 'suspended' then
            local ok, err = coroutine.resume(co)
            if not ok then error('thread failed: ' .. tostring(err)) end
        end
    end
end

function S.flushTimeouts()
    local due = S.timeouts
    S.timeouts = {}
    for i = 1, #due do due[i]() end
end

function AddEventHandler(name, fn)
    S.handlers[name] = S.handlers[name] or {}
    table.insert(S.handlers[name], fn)
end

RegisterNetEvent = AddEventHandler

---Fire an event as a player.
function S.trigger(name, src, ...)
    source = src
    for _, fn in ipairs(S.handlers[name] or {}) do fn(...) end
    source = nil
end

function TriggerClientEvent(name, src, payload)
    S.sent[#S.sent + 1] = { name = name, src = src, payload = payload }
end

function TriggerEvent() end

---Client events sent since a mark, optionally filtered.
function S.events(name, src, from)
    local out = {}
    for i = (from or 0) + 1, #S.sent do
        local e = S.sent[i]
        if (not name or e.name == name) and (not src or e.src == src) then out[#out + 1] = e end
    end
    return out
end

function S.mark() return #S.sent end

---Call a registered ox_lib callback as a player.
function S.call(name, src, ...)
    local fn = S.callbacks['sd-trapphone:server:' .. name]
    if not fn then error('no callback ' .. name) end
    return fn(src, ...)
end

-- Players.
function S.addPlayer(src, opts)
    S.players[src] = {
        name = opts.name or ('Player' .. src),
        cid = opts.cid or ('CID' .. src),
        job = opts.job or 'unemployed',
        coords = vec3(opts.x or 0.0, opts.y or 0.0, opts.z or 30.0),
        vehicle = 0,
        health = 200,
        state = {},
        items = {},
        phoneMeta = {},
        cash = 0,
        bank = 0,
        black = 0,
    }
end

function S.dropPlayer(src)
    S.trigger('playerDropped', src, 'left')
    S.players[src] = nil
end

function GetPlayers()
    local out = {}
    for src in pairs(S.players) do out[#out + 1] = tostring(src) end
    return out
end

function GetPlayerName(src) return S.players[src] and S.players[src].name or nil end
function GetPlayerPed(src) return S.players[src] and (src + 1000) or 0 end
function GetEntityCoords(ped) return S.players[ped - 1000].coords end
function GetEntityHeading() return 90.0 end
function GetEntityHealth(ped) return S.players[ped - 1000].health end
function GetVehiclePedIsIn(ped) return S.players[ped - 1000].vehicle end
function Player(src) return { state = S.players[src].state } end
function GetCurrentResourceName() return 'sd-trapphone' end
function IsDuplicityVersion() return true end
function IsPlayerAceAllowed() return 1 end

-- Locale: the real strings from locales/en.json, so a missing key shows up in a test.
do
    local raw = L.readFile(L.resource .. '/locales/en.json') or ''
    local section

    for line in raw:gmatch('[^\r\n]+') do
        local opened = line:match('^%s*"([%w_]+)"%s*:%s*{')
        local key, value = line:match('^%s*"([%w_]+)"%s*:%s*"(.*)",?%s*$')

        if opened then
            section = opened
        elseif key and section then
            S.strings[section .. '.' .. key] = value:gsub('\\"', '"')
        end
    end
end

function locale(key, ...)
    local text = S.strings[key]
    if not text then return key end
    if select('#', ...) > 0 then return text:format(...) end
    return text
end

-- ox_lib.
lib = {
    locale = function() end,
    callback = { register = function(name, fn) S.callbacks[name] = fn end },
    table = {
        contains = function(list, value)
            for i = 1, #list do if list[i] == value then return true end end
            return false
        end,
    },
    logger = function(src, event, message, data)
        S.logs[#S.logs + 1] = { src = src, event = event, message = message, data = data }
    end,
}

---Audit lines of one event since a mark.
function S.audit(event, from)
    local out = {}
    for i = (from or 0) + 1, #S.logs do
        if S.logs[i].event == event then out[#out + 1] = S.logs[i] end
    end
    return out
end

json = { encode = function(v) return tostring(v) end, decode = function() return {} end }

-- Bridge fakes.
local inventory = { system = 'ox_inventory', failRemove = false, failAdd = false }

function inventory.count(src, item) return S.players[src] and S.players[src].items[item] or 0 end
function inventory.has(src, item, amount) return inventory.count(src, item) >= (amount or 1) end

function inventory.add(src, item, count)
    if inventory.failAdd or not S.players[src] then return false end
    S.players[src].items[item] = inventory.count(src, item) + count
    return true
end

function inventory.remove(src, item, count)
    if inventory.failRemove or inventory.count(src, item) < count then return false end
    S.players[src].items[item] = inventory.count(src, item) - count
    return true
end

function inventory.getSlots(src, item)
    local count = inventory.count(src, item)
    if count < 1 then return {} end
    return { { slot = 1, count = count, metadata = S.players[src].phoneMeta } }
end

function inventory.setMetadata(src, _, metadata)
    S.players[src].phoneMeta = metadata
    return true
end

function inventory.label(item) return item end
function inventory.registerUsable() end

local money = {}

function money.add(src, account, amount) S.players[src][account] = S.players[src][account] + amount end
function money.addBlack(src, amount)
    S.players[src].black = S.players[src].black + amount
    return true
end
function money.get(src, account) return S.players[src][account] end

local player = {}

function player.get(src) return S.players[src] end
function player.getIdentifier(src) return S.players[src] and S.players[src].cid or nil end
function player.getName(src) return S.players[src] and S.players[src].name or 'Unknown' end

local job = {}

function job.getName(src) return S.players[src] and S.players[src].job or nil end

-- Storage: nothing is ever on disk, every phone is new.
local store = {}

function store.ensureSchema() end
function store.loadPhone() return nil end
function store.phoneIdByNumber() return nil end
function store.numberTaken() return false end
function store.savePhone() end
function store.loadRelations() return {} end
function store.saveRelation() end

-- The turf module belongs to another slice. The fake answers to the signatures in
-- docs/design.md and records what selling tells it.
local turf = {}

function turf.zoneOf(src)
    local coords = S.players[src].coords
    return require('shared.zones').at(coords.x, coords.y)
end

function turf.onSale(src, phone, zone, total)
    S.turfSales[#S.turfSales + 1] = { src = src, phone = phone.id, zone = zone, total = total }
end

package.preload['bridge.server.inventory'] = function() return inventory end
package.preload['bridge.server.money'] = function() return money end
package.preload['bridge.server.player'] = function() return player end
package.preload['bridge.server.job'] = function() return job end
package.preload['bridge.client.inventory'] = function() return inventory end
package.preload['server.trapphone.store'] = function() return store end
package.preload['server.trapphone.turf'] = function() return turf end

S.inventory = inventory
S.vec = vec

return S
