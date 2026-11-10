---@type table sd-trapphone config root (configs/config.lua).
local config = require 'configs.config'
---@type table Handset items and colours (shared.handsets).
local handsets = require 'shared.handsets'
---@type table Console log helper (shared.log).
local log = require 'shared.log'
---@type table Pure offer maths (shared.pricing).
local pricing = require 'shared.pricing'
---@type table Pure zone lookup (shared.zones): a delivery is priced by the door's zone.
local zones = require 'shared.zones'
---@type table Live phones (server.trapphone.phones).
local phones = require 'server.trapphone.phones'
---@type table Police pressure (server.trapphone.dispatch).
local dispatch = require 'server.trapphone.dispatch'
---@type table Sessions, tickets and the payout (server.trapphone.selling).
local selling = require 'server.trapphone.selling'
---@type table Inventory bridge (bridge.server.inventory).
local inventory = require 'bridge.server.inventory'

---@type table Drop-off config (config.Deliveries).
local CFG = config.Deliveries or {}
---@type table[] The doors customers wait at (config.Deliveries.Spots).
local SPOTS = CFG.Spots or {}
---@type number Metres past CompleteRadius at which a completion stops looking like a mistake.
local SUSPECT_MARGIN = 30.0
---@type integer Seconds before another door is looked for when none was in range.
local RETRY_SECONDS = 20

---@type table Dropoffs module; the table returned at end of file. The delivery queue: while a
---player is taking orders, customers text them from doors around the map, and an accepted
---order is completed at that door.
local dropoffs = {}

---The stable id a door's customer is known by. The same door is always the same person, so
---they keep a relationship and can become a regular like anyone on the corner.
---@param index integer index into config.Deliveries.Spots
---@return string key
local function doorKey(index)
    return ('door-%d'):format(index)
end

---What a door's customer is told to expect, sent to the seller's client once they accept.
---@param ticket table TrapTicket of kind 'drop'
---@return table payload
local function routeOf(ticket)
    local spot = SPOTS[ticket.door]
    local coords = spot.coords

    return {
        ticketId = ticket.id,
        number = ticket.number,
        coords = { x = coords.x, y = coords.y, z = coords.z, w = coords.w },
        model = spot.model,
        item = ticket.item,
        qty = ticket.qty,
        price = ticket.total,
        place = ticket.place,
        expires = ticket.expires,
        radius = CFG.CompleteRadius or 6.0,
    }
end

---Pick a door for a new order: far enough to be a drive, near enough to be worth it, and not
---one the player already has an order for.
---@param src integer player server id
---@return integer|nil index into config.Deliveries.Spots
local function pickDoor(src)
    local coords = selling.coords(src)
    if not coords then return nil end

    local taken = {}

    for _, ticket in ipairs(selling.ticketsOf(src, 'drop')) do
        taken[ticket.door] = true
    end

    local min, max = CFG.MinDistance or 0.0, CFG.MaxDistance or 10000.0
    local candidates = {}

    for i = 1, #SPOTS do
        if not taken[i] then
            local distance = #(coords - SPOTS[i].coords.xyz)
            if distance >= min and distance <= max then candidates[#candidates + 1] = i end
        end
    end

    if #candidates == 0 then return nil end

    return candidates[math.random(#candidates)]
end

---What a player can still promise: held stock minus what open orders already claim.
---@param src integer player server id
---@param family string a family key or 'any'
---@return { item: string, entry: table, free: integer }[] free stock
---@return boolean holding whether they hold anything sellable at all
local function freeStock(src, family)
    local stock = selling.sellable(src, family)
    local list = {}

    for i = 1, #stock do
        local free = stock[i].count - selling.committed(src, stock[i].item)
        if free > 0 then list[#list + 1] = { item = stock[i].item, entry = stock[i].entry, free = free } end
    end

    return list, #stock > 0
end

---One look at a player who is taking orders: stop them if they no longer can, otherwise text
---them a new order when one is due.
---@param src integer player server id
---@param session table TrapSession in 'drops' mode
local function tick(src, session)
    if not GetPlayerName(src) then return end

    local phone = phones.current(src)

    if not phone or phone.id ~= session.phoneId or handsets.count(src) < 1 then
        selling.stop(src, 'selling.stopped_phone')
        return
    end

    if not dispatch.canSell() then
        selling.stop(src, 'dispatch.not_enough_police')
        return
    end

    local now = os.time()
    if now < session.next then return end
    if selling.isDown(src) then return end
    if CFG.RequireVehicle and selling.onFoot(src) then return end

    local open = selling.ticketsOf(src, 'drop')
    if #open >= (CFG.MaxQueue or 1) then return end

    local stock, holding = freeStock(src, session.family)

    if not holding and #open == 0 then
        selling.stop(src, 'selling.stopped_stock')
        return
    end

    if #stock == 0 then return end

    local door = pickDoor(src)

    if not door then
        session.next = now + RETRY_SECONDS
        return
    end

    local pick = stock[math.random(#stock)]
    local spot = SPOTS[door]
    local zone = zones.at(spot.coords.x, spot.coords.y)

    local ticket = selling.newTicket(src, phone, {
        kind = 'drop',
        item = pick.item,
        qty = pricing.quantity(pick.entry, pick.free, math.random, CFG.QuantityMultiplier),
        zone = zone,
        seconds = CFG.AcceptSeconds,
        place = spot.label or zone.label,
        door = door,
    })

    selling.open(phone, ticket, doorKey(door), {
        moment = 'drop_order',
        bonus = CFG.PriceBonus,
        seconds = CFG.AcceptSeconds,
    })

    -- With texts off, every order is taken the moment it comes in.
    if not CFG.SmsOnRequest then selling.accept(src, phone, ticket, 'drop_accept') end

    session.next = now + (CFG.RequestDelay or 60)
    phones.refresh(phone, 'hustle')

    log.debug('dropoffs', 'order %s for %s: %d x %s to door %d', ticket.id, src, ticket.qty, ticket.item, door)
end

-- An accepted order is the first time the client learns where the door is.
selling.hook('drop', {
    acceptSeconds = (CFG.DeliverMinutes or 12) * 60,
    acceptLine = 'drop_accept',
    lateLine = 'drop_late',
    accepted = function(src, phone, ticket)
        TriggerClientEvent('sd-trapphone:client:dropAccepted', src, routeOf(ticket))
        phones.refresh(phone, 'hustle')
    end,
})

-- The hand-over at the door. The door's place comes from the config and the player's from
-- the server; the client only names the ticket.
lib.callback.register('sd-trapphone:server:completeDrop', function(src, ticketId)
    if selling.limited(src, 'completeDrop', 700) then return selling.fail('selling.slow_down') end

    local ticket = selling.owned(src, ticketId)
    if not ticket then return selling.fail('selling.offer_gone') end

    if ticket.kind ~= 'drop' then
        selling.suspect(src, ('tried to complete street ticket %s as a drop-off'):format(ticket.id), { ticketId = ticket.id })
        return selling.fail('selling.bad_request')
    end

    if ticket.state ~= 'accepted' then return selling.fail('selling.offer_gone') end

    if os.time() > ticket.expires then
        selling.close(ticket, 'expired', 'drop_late')
        return selling.fail('selling.offer_gone')
    end

    local phone = phones.current(src)
    if not phone or phone.id ~= ticket.phoneId then return selling.fail('selling.no_phone') end

    if selling.isDown(src) or not selling.onFoot(src) then return selling.fail('selling.on_foot') end

    local spot = SPOTS[ticket.door]
    local coords = selling.coords(src)
    local distance = coords and spot and #(coords - spot.coords.xyz) or math.huge
    local radius = CFG.CompleteRadius or 6.0

    if distance > radius then
        if distance > radius + SUSPECT_MARGIN then
            selling.suspect(src, ('completed drop-off %s %.0f m from its door'):format(ticket.id, distance),
                { ticketId = ticket.id, distance = distance })
        end

        return selling.fail('dropoffs.too_far')
    end

    local ok, result = selling.settle(src, phone, ticket, {
        xpScale = config.Economy.XP.DropOffBonus,
        stat = 'drops',
        thanks = 'drop_thanks',
    })
    if not ok then return selling.fail(result) end

    return { ok = true, data = result }
end)

---How many drop-off orders a player has open or accepted.
---@param src integer player server id
---@return integer count
function dropoffs.queued(src)
    return #selling.ticketsOf(src, 'drop')
end

CreateThread(function()
    while true do
        Wait(5000)

        if CFG.Enabled then
            local taking = {}

            for src, session in pairs(selling.sessions()) do
                if session.mode == 'drops' then taking[#taking + 1] = src end
            end

            for i = 1, #taking do
                local session = selling.session(taking[i])

                if session then
                    local ok, err = pcall(tick, taking[i], session)
                    if not ok then log.error('dropoffs', 'tick for %s failed: %s', taking[i], err) end
                end
            end
        end
    end
end)

return dropoffs
