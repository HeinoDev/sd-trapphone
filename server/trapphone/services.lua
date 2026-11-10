---@type table sd-trapphone config root (configs/config.lua).
local config = require 'configs.config'
---@type table Console log helper (shared.log).
local log = require 'shared.log'
---@type table Item label lookups (shared.items).
local items = require 'shared.items'
---@type table Audit-log helper (server.trapphone.audit).
local audit = require 'server.trapphone.audit'
---@type table Live phones (server.trapphone.phones).
local phones = require 'server.trapphone.phones'
---@type table XP and levels (server.trapphone.progress).
local progress = require 'server.trapphone.progress'
---@type table Inventory bridge (bridge.server.inventory).
local inventory = require 'bridge.server.inventory'
---@type table Money bridge (bridge.server.money).
local money = require 'bridge.server.money'

---@type table Money wash config (config.Services.MoneyWash), shared switches + server numbers.
local WASH = config.Services.MoneyWash
---@type table Black market config (config.Services.BlackMarket), shared switches + server stock.
local MARKET = config.Services.BlackMarket

---@class TrapWash
---@field amount integer dirty money taken
---@field payout integer clean money owed when it finishes
---@field ends integer os.time() it is done
---@field index integer which laundry it is spinning at

---@type table Services module; the table returned at end of file. The back rooms a growing
---business unlocks: the money wash and the black market. Also owns the one way this resource
---takes and returns money, so every purchase pays the same way.
local services = {}

---@type number How close a player must be to an attendant to deal with them, in metres.
local USE_RADIUS = 5.0
---@type number How far a player may drift from the laundry while their money spins.
local WAIT_RADIUS = 12.0
---@type integer Milliseconds between two service requests from one player.
local PACE_MS = 400

---@type table<integer, TrapWash> The wash each player has running, by server id.
local washes = {}
---@type table<integer, integer> GetGameTimer() of each player's last service request.
local pace = {}

---Take money from a player. `black` is the framework's dirty money, anything else an account.
---@param src integer player server id
---@param account string 'cash' | 'bank' | 'black'
---@param amount integer
---@param reason? string passed to the framework's own money log
---@return boolean paid true only when the whole amount was taken
function services.charge(src, account, amount, reason)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return amount == 0 end

    if account == 'black' then return money.removeBlack(src, amount) == true end

    return money.remove(src, account, amount, reason) == true
end

---Give money back to a player (a purchase whose items could not be handed over).
---@param src integer player server id
---@param account string 'cash' | 'bank' | 'black'
---@param amount integer
---@param reason? string passed to the framework's own money log
function services.refund(src, account, amount, reason)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return end

    if account == 'black' then
        money.addBlack(src, amount)
    else
        money.add(src, account, amount, reason)
    end
end

---What a player can currently pay from an account.
---@param src integer player server id
---@param account string 'cash' | 'bank' | 'black'
---@return integer balance
function services.balance(src, account)
    local ok, value

    if account == 'black' then
        ok, value = pcall(money.getBlack, src)
    else
        ok, value = pcall(money.get, src, account)
    end

    return ok and math.floor(tonumber(value) or 0) or 0
end

---Whether a request arrives too soon after the player's last one.
---@param src integer player server id
---@return boolean tooSoon
local function tooSoon(src)
    local now = GetGameTimer()

    if now - (pace[src] or -PACE_MS) < PACE_MS then return true end

    pace[src] = now

    return false
end

---A player's distance to a service location, from their real position.
---@param src integer player server id
---@param location table|nil { coords = vec4 }
---@return number distance math.huge when either end is missing
local function distanceTo(src, location)
    local ped = GetPlayerPed(src)
    if not location or not ped or ped == 0 then return math.huge end

    local coords = GetEntityCoords(ped)

    return #(coords - vec3(location.coords.x, location.coords.y, location.coords.z))
end

---Whether a phone has opened a service: the service is on and the phone holds the contact
---type that unlocks it.
---@param phone table|nil TrapPhone
---@param service table WASH or MARKET
---@return boolean unlocked
local function unlocked(phone, service)
    return phone ~= nil and service.Enabled == true and phones.hasContactType(phone, service.UnlockContactType)
end

---Resolve a service request: the phone the player carries unlocks the service and they are
---standing at the location they named. A request from anywhere else is logged, since the
---client only knows a location it was sent and only offers it up close.
---@param src integer player server id
---@param service table WASH or MARKET
---@param index any location index the client sent
---@param radius? number metres (USE_RADIUS when omitted)
---@return table|nil phone the player's phone when the request is good
---@return string|nil error localized reason when it is not
local function check(src, service, index, radius)
    local phone = phones.active(src)
    local location = type(index) == 'number' and service.Locations[index] or nil

    if not unlocked(phone, service) then
        -- Usually honest: the phone that opened this place was dropped or handed on. Tell the
        -- client so the attendant goes away.
        services.sync(src)
        return nil, locale('services.locked')
    end

    if not location then
        audit.log('suspect', src, 'named a back-room location that does not exist', { index = tostring(index) })
        return nil, locale('services.locked')
    end

    if distanceTo(src, location) > (radius or USE_RADIUS) then
        audit.log('suspect', src, 'used a back-room service from far away', { index = index, distance = distanceTo(src, location) })
        return nil, locale('services.too_far')
    end

    return phone, nil
end

---The wash tier a phone gets: the highest `from` its best level reaches.
---@param phone table TrapPhone
---@return table tier { from, fee, max }
local function tierOf(phone)
    local level = progress.bestLevel(phone)
    local tier = WASH.Tiers[1]

    for i = 1, #WASH.Tiers do
        if level >= WASH.Tiers[i].from and WASH.Tiers[i].from >= tier.from then tier = WASH.Tiers[i] end
    end

    return tier
end

---The service locations a player's phone has unlocked, as the client needs them.
---@param src integer player server id
---@return table list { wash?: { coords: vector4, model: integer }[], market?: ... }
function services.unlockedFor(src)
    local phone = phones.current(src) or phones.active(src)
    local out = {}

    if unlocked(phone, WASH) then out.wash = WASH.Locations end
    if unlocked(phone, MARKET) then out.market = MARKET.Locations end

    return out
end

---Send a player the locations their phone unlocks. Call after anything that changes them
---(a contact met, a number passed on, a phone reset).
---@param src integer player server id
function services.sync(src)
    TriggerClientEvent('sd-trapphone:client:services', src, services.unlockedFor(src))
end

---The nearest unlocked location of a service to a player, for the phone's "mark it" action.
---@param src integer player server id
---@param kind 'wash'|'market'
---@return vector4|nil coords
function services.nearest(src, kind)
    local service = kind == 'wash' and WASH or MARKET
    if not unlocked(phones.current(src), service) then return nil end

    local best, bestDistance

    for i = 1, #service.Locations do
        local distance = distanceTo(src, service.Locations[i])

        if not bestDistance or distance < bestDistance then best, bestDistance = service.Locations[i], distance end
    end

    return best and best.coords or nil
end

---Hand a running wash back as the dirty money it was.
---@param src integer player server id
---@return boolean refunded
local function cancelWash(src)
    local wash = washes[src]
    if not wash then return false end

    washes[src] = nil
    pcall(money.addBlack, src, wash.amount)

    return true
end

lib.callback.register('sd-trapphone:server:services', function(src)
    return services.unlockedFor(src)
end)

-- What the launderer would do for this player right now.
lib.callback.register('sd-trapphone:server:washQuote', function(src, index)
    if tooSoon(src) then return { ok = false, error = locale('services.slow_down') } end

    local phone, err = check(src, WASH, index)
    if not phone then return { ok = false, error = err } end
    if washes[src] then return { ok = false, error = locale('services.wash_busy') } end

    local tier = tierOf(phone)
    local dirty = services.balance(src, 'black')

    return {
        ok = true,
        data = { dirty = dirty, fee = tier.fee, max = math.min(tier.max, dirty), secondsPer1000 = WASH.SecondsPer1000, maxSeconds = WASH.MaxSeconds },
    }
end)

-- Start a wash. The dirty money is taken now; the clean money is paid when the wait is over.
lib.callback.register('sd-trapphone:server:washStart', function(src, index, amount)
    if tooSoon(src) then return { ok = false, error = locale('services.slow_down') } end

    local phone, err = check(src, WASH, index)
    if not phone then return { ok = false, error = err } end
    if washes[src] then return { ok = false, error = locale('services.wash_busy') } end

    local tier = tierOf(phone)

    if type(amount) ~= 'number' or amount ~= math.floor(amount) or amount < 1 or amount > tier.max then
        return { ok = false, error = locale('services.wash_bad_amount', tier.max) }
    end
    if not services.charge(src, 'black', amount) then return { ok = false, error = locale('services.wash_not_enough') } end

    local seconds = math.max(3, math.min(WASH.MaxSeconds, math.ceil(amount / 1000 * WASH.SecondsPer1000)))
    local wash = { amount = amount, payout = math.floor(amount * (1.0 - tier.fee)), ends = os.time() + seconds, index = index }

    washes[src] = wash

    if WASH.AlertChance > 0 and math.random(100) <= WASH.AlertChance then
        -- Required here so this file never depends on the street modules' load order.
        local ok, why = pcall(function() return require('server.trapphone.dispatch').alert(src, 'wash') end)
        if not ok then log.debug('services', 'wash alert failed: %s', why) end
    end

    -- A wash nobody comes back for is handed back dirty rather than kept.
    SetTimeout((seconds + 60) * 1000, function()
        if washes[src] == wash and GetPlayerName(src) then cancelWash(src) end
    end)

    return { ok = true, data = { seconds = seconds, payout = wash.payout } }
end)

-- The wait is over: pay out, if they really waited and are still there.
lib.callback.register('sd-trapphone:server:washFinish', function(src)
    local wash = washes[src]
    if not wash then return { ok = false, error = locale('services.wash_none') } end

    if os.time() < wash.ends - 1 then
        audit.log('suspect', src, 'tried to collect a wash before it finished', { left = wash.ends - os.time(), amount = wash.amount })
        return { ok = false, error = locale('services.wash_not_done') }
    end

    if distanceTo(src, WASH.Locations[wash.index]) > WAIT_RADIUS then
        cancelWash(src)
        return { ok = false, error = locale('services.wash_left') }
    end

    washes[src] = nil

    if WASH.PayoutAccount == 'black' then
        money.addBlack(src, wash.payout)
    else
        money.add(src, WASH.PayoutAccount, wash.payout, 'trapphone-wash')
    end

    audit.log('wash', src, ('washed $%d into $%d'):format(wash.amount, wash.payout), { amount = wash.amount, payout = wash.payout })

    return { ok = true, data = { payout = wash.payout, amount = wash.amount } }
end)

-- Walked away or cancelled: the dirty money comes back untouched.
lib.callback.register('sd-trapphone:server:washCancel', function(src)
    return { ok = cancelWash(src) }
end)

-- What the back room will sell this player. Stock above their level is not listed at all.
lib.callback.register('sd-trapphone:server:marketStock', function(src, index)
    if tooSoon(src) then return { ok = false, error = locale('services.slow_down') } end

    local phone, err = check(src, MARKET, index)
    if not phone then return { ok = false, error = err } end

    local level = progress.bestLevel(phone)
    local list = {}

    for item, info in pairs(MARKET.Stock) do
        if level >= (info.level or 1) then
            list[#list + 1] = { item = item, label = items.label(item), price = info.price, max = MARKET.MaxPerPurchase }
        end
    end

    table.sort(list, function(a, b)
        if a.price ~= b.price then return a.price < b.price end
        return a.item < b.item
    end)

    return { ok = true, data = { items = list, balance = services.balance(src, MARKET.PayWith) } }
end)

-- A black market purchase: pay, then hand over; anything that can't be handed over is refunded.
lib.callback.register('sd-trapphone:server:marketBuy', function(src, index, item, qty)
    if tooSoon(src) then return { ok = false, error = locale('services.slow_down') } end

    local phone, err = check(src, MARKET, index)
    if not phone then return { ok = false, error = err } end

    local info = type(item) == 'string' and MARKET.Stock[item] or nil

    if not info or type(qty) ~= 'number' or qty ~= math.floor(qty) or qty < 1 or qty > MARKET.MaxPerPurchase then
        return { ok = false, error = locale('services.market_bad_order') }
    end

    if progress.bestLevel(phone) < (info.level or 1) then
        audit.log('suspect', src, 'tried to buy black market stock above their level', { item = item, level = info.level })
        return { ok = false, error = locale('services.locked') }
    end

    if not inventory.canCarry(src, item, qty) then return { ok = false, error = locale('services.cant_carry') } end

    local total = info.price * qty

    if not services.charge(src, MARKET.PayWith, total, 'trapphone-market') then
        return { ok = false, error = locale('services.cant_afford', total) }
    end

    local ok, given = pcall(inventory.add, src, item, qty)

    if not ok or not given then
        services.refund(src, MARKET.PayWith, total, 'trapphone-market-refund')
        return { ok = false, error = locale('services.cant_carry') }
    end

    audit.log('market', src, ('bought %d x %s for $%d'):format(qty, items.display(item), total), { item = item, qty = qty, total = total })

    return { ok = true, data = { item = item, label = items.label(item), qty = qty, total = total } }
end)

-- A wash only exists in memory once the dirty money is taken, so a restart hands it all back.
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    for src in pairs(washes) do
        cancelWash(src)
    end
end)

AddEventHandler('playerDropped', function()
    local src = source

    -- Leaving mid-wash: try to hand the dirty money back while the character still exists.
    cancelWash(src)
    pace[src] = nil
end)

return services
