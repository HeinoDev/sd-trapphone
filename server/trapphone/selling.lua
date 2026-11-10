---@type table sd-trapphone config root (configs/config.lua).
local config = require 'configs.config'
---@type table Handset items and colours (shared.handsets).
local handsets = require 'shared.handsets'
---@type table Console log helper (shared.log).
local log = require 'shared.log'
---@type table Audit-log helper (server.trapphone.audit).
local audit = require 'server.trapphone.audit'
---@type table Pure offer / haggle / personality maths (shared.pricing).
local pricing = require 'shared.pricing'
---@type table Pure zone lookup (shared.zones): the fallback when the turf module can't answer.
local zones = require 'shared.zones'
---@type table Item label lookups (shared.items).
local items = require 'shared.items'
---@type table Live phones (server.trapphone.phones).
local phones = require 'server.trapphone.phones'
---@type table XP and levels (server.trapphone.progress).
local progress = require 'server.trapphone.progress'
---@type table Standing storage (server.trapphone.relations): customer relationships.
local relations = require 'server.trapphone.relations'
---@type table Police pressure (server.trapphone.dispatch).
local dispatch = require 'server.trapphone.dispatch'
---@type table Inventory bridge (bridge.server.inventory).
local inventory = require 'bridge.server.inventory'
---@type table Money bridge (bridge.server.money).
local money = require 'bridge.server.money'
---@type table Player bridge (bridge.server.player): identifier lookups.
local playerBridge = require 'bridge.server.player'

---@type table Street selling config (config.Selling): shared half plus the server-only odds.
local CFG = config.Selling
---@type table Relationship steps (config.Selling.Relationship).
local REL = CFG.Relationship or {}
---@type table Per-item prices (config.Economy.Prices).
local PRICES = config.Economy.Prices
---@type table Haggling config (config.Economy.Haggle).
local HAGGLE = config.Economy.Haggle or {}
---@type table Drop-off config (config.Deliveries): only the switches the start checks need.
local DROPS = config.Deliveries or {}

---@type integer Seconds a sale must wait after its offer was made.
local MIN_SERVE = CFG.MinServeSeconds or 0
---@type integer Seconds a ticket may wait for the client to report who the customer is.
local PENDING_SECONDS = 30
---@type number Metres a player may be from where they asked for a customer when the sale completes.
local MAX_SALE_DISTANCE = (CFG.CustomerSearchRadius or 45.0) + 100.0
---@type number Metres a player may be from their pull-up spot for a customer to arrive by car.
local SPOT_RANGE = 40.0
---@type integer Seconds before the same ped look can be a customer of the same player again.
local KEY_REUSE = 120
---@type integer Seconds a ped who was pitched remembers it.
local PITCH_MEMORY = 300
---@type integer The largest counter-offer that is even looked at.
local MAX_PRICE = 10000000

---@class TrapSession
---@field src integer
---@field cid string character id
---@field phoneId string
---@field mode 'corner'|'drops'
---@field family string a family key or 'any'
---@field next integer os.time() the next customer or order may come
---@field cooldowns table<string, integer> per item, os.time() it can be asked for again
---@field recent table<string, integer> ped looks served lately, by os.time()

---@class TrapTicket
---@field id string
---@field src integer
---@field cid string character id of the seller
---@field phoneId string
---@field kind 'corner'|'car'|'pitch'|'drop'
---@field item string
---@field family string
---@field qty integer
---@field unit integer per-unit price as rolled
---@field total integer what the customer pays (a won haggle raises it)
---@field zone table TrapZone the sale is priced in
---@field state 'pending'|'open'|'accepted'|'declined'|'done'|'expired'|'walked'
---@field created integer os.time()
---@field offered integer|nil os.time() the offer was texted
---@field expires integer os.time()
---@field counters integer haggles left
---@field pedKey string|nil the customer's look key
---@field number string|nil the number they text from
---@field personality string|nil key of config.Selling.Personalities
---@field origin vector3|nil where the seller stood when the ticket was made
---@field place string|nil drop-offs: where it is going, as shown
---@field door integer|nil drop-offs: index into config.Deliveries.Spots
---@field settling boolean|nil true while the sale is being paid out

---@type table Selling module; the table returned at end of file. Owns who is hustling and
---every sale ticket: corner and car customers, pitches, haggling and the payout. Drop-offs
---build on the ticket functions exposed here.
local selling = {}

---@type table<integer, TrapSession> Who is hustling, by server id.
local sessions = {}
---@type table<string, TrapTicket> Every live ticket by id.
local tickets = {}
---@type integer Running number that keeps ticket ids unique.
local ticketSeq = 0
---@type table<string, table> Per-kind hooks registered with selling.hook.
local hooks = {}
---@type table<integer, table<string, integer>> GetGameTimer() of each player's last call, by name.
local stamps = {}
---@type table<integer, table<string, integer>> Ped looks each player pitched, by os.time().
local pitched = {}
---@type table<integer, table<string, integer>> os.time() each item is free to sell again, per player.
local cooling = {}

---A standard failed reply.
---@param key string locale key of the reason
---@return { ok: boolean, error: string } reply
local function fail(key)
    return { ok = false, error = locale(key) }
end

---Record a reject that an honest client would not have caused.
---@param src integer player server id
---@param what string one-line description
---@param data? table extra fields
local function suspect(src, what, data)
    audit.log('suspect', src, what, data)
    log.debug('selling', 'suspect %s: %s', src, what)
end

---Whether a player is calling something again too soon.
---@param src integer player server id
---@param name string which call
---@param ms integer minimum gap
---@return boolean tooSoon
local function limited(src, name, ms)
    local now = GetGameTimer()
    local mine = stamps[src]

    if not mine then
        mine = {}
        stamps[src] = mine
    end

    if mine[name] and now - mine[name] < ms then return true end

    mine[name] = now

    return false
end

---A player's real position.
---@param src integer player server id
---@return vector3|nil coords
local function realCoords(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end

    return GetEntityCoords(ped)
end

---Whether a player is on foot, by the server's own view of them.
---@param src integer player server id
---@return boolean onFoot
local function onFoot(src)
    local ped = GetPlayerPed(src)

    return ped ~= nil and ped ~= 0 and GetVehiclePedIsIn(ped, false) == 0
end

---Whether a player is dead or downed.
---@param src integer player server id
---@return boolean down
local function isDown(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return true end

    local state = Player(src).state

    return state.isDead == true or state.dead == true or GetEntityHealth(ped) <= 0
end

---The turf a player is standing on. Asks the turf module (required here, not at the top, so
---the two modules can't load in a circle) and falls back to the plain zone lookup.
---@param src integer player server id
---@return table zone TrapZone
local function zoneOf(src)
    local loaded, turf = pcall(require, 'server.trapphone.turf')

    if loaded and type(turf) == 'table' and turf.zoneOf then
        local ok, zone = pcall(turf.zoneOf, src)
        if ok and type(zone) == 'table' then return zone end
    end

    local coords = realCoords(src)

    return coords and zones.at(coords.x, coords.y) or config.Zones.Default
end

---A whole number in a { min, max } config pair.
---@param range { min: integer, max: integer }|nil
---@return integer value
local function inRange(range)
    if not range then return 0 end

    return math.random(range.min or 0, math.max(range.min or 0, range.max or 0))
end

---Validate a ped look key a client sent (world.pedKey: hex model, head drawable, head texture).
---@param key any
---@return string|nil key nil when it is not a look key
local function cleanKey(key)
    if type(key) ~= 'string' or #key > 32 then return nil end
    if not key:match('^%x+%-%d+%-%d+$') then return nil end

    return key
end

---What a player holds that can be sold on the street, optionally within one family.
---@param src integer player server id
---@param family string a family key or 'any'
---@return { item: string, info: table, entry: table, count: integer }[] stock sorted by item name
function selling.sellable(src, family)
    local list = {}

    for item, info in pairs(config.Drugs.Items) do
        local entry = PRICES[item]

        if entry and entry.npc ~= false and (family == 'any' or info.family == family) then
            local count = inventory.count(src, item) or 0
            if count > 0 then list[#list + 1] = { item = item, info = info, entry = entry, count = count } end
        end
    end

    table.sort(list, function(a, b) return a.item < b.item end)

    return list
end

---A player's live tickets, optionally of one kind.
---@param src integer player server id
---@param kind? string ticket kind; every kind when omitted
---@return TrapTicket[] list
function selling.ticketsOf(src, kind)
    local list = {}

    for _, ticket in pairs(tickets) do
        if ticket.src == src and (not kind or ticket.kind == kind) then list[#list + 1] = ticket end
    end

    return list
end

---How many of an item a player has already promised to open or accepted tickets.
---@param src integer player server id
---@param item string
---@return integer qty
function selling.committed(src, item)
    local qty = 0

    for _, ticket in pairs(tickets) do
        if ticket.src == src and ticket.item == item then qty += ticket.qty end
    end

    return qty
end

---The corner, car or pitch ticket a player has going (one at a time).
---@param src integer player server id
---@return TrapTicket|nil ticket
local function streetTicket(src)
    for _, ticket in pairs(tickets) do
        if ticket.src == src and ticket.kind ~= 'drop' then return ticket end
    end

    return nil
end

---A live ticket by id.
---@param id string
---@return TrapTicket|nil ticket
function selling.ticket(id)
    return tickets[id]
end

---The ticket a client named, when it is really theirs. A missing ticket is normal (it ran
---out); a wrong type or someone else's ticket is logged.
---@param src integer player server id
---@param ticketId any
---@return TrapTicket|nil ticket
local function owned(src, ticketId)
    if type(ticketId) ~= 'string' or #ticketId > 40 then
        suspect(src, 'sent a malformed ticket id', { ticketId = tostring(ticketId):sub(1, 60) })
        return nil
    end

    local ticket = tickets[ticketId]
    if not ticket then return nil end

    if ticket.src ~= src then
        suspect(src, ('used ticket %s that belongs to player %d'):format(ticketId, ticket.src), { ticketId = ticketId })
        return nil
    end

    return ticket
end

---The phone a ticket was made on, when the player still has it out as their current phone.
---@param src integer player server id
---@param ticket TrapTicket
---@return table|nil phone TrapPhone
local function phoneFor(src, ticket)
    local phone = phones.current(src)
    if not phone or phone.id ~= ticket.phoneId then return nil end

    return phone
end

---Register what a ticket kind does beyond the shared flow.
---@param kind string ticket kind ('drop')
---@param spec { accepted?: fun(src: integer, phone: table, ticket: TrapTicket), closed?: fun(ticket: TrapTicket, state: string), acceptSeconds?: integer, acceptLine?: string, lateLine?: string }
function selling.hook(kind, spec)
    hooks[kind] = spec
end

---Who is hustling.
---@param src integer player server id
---@return TrapSession|nil session
function selling.session(src)
    return sessions[src]
end

---Every hustling session. Treat as read-only.
---@return table<integer, TrapSession> sessions
function selling.sessions()
    return sessions
end

---What a player is doing with the phone's Hustle app.
---@param src integer player server id
---@return 'idle'|'corner'|'drops' mode
function selling.mode(src)
    local session = sessions[src]

    return session and session.mode or 'idle'
end

---The Hustle section of the phone state (docs/design.md `Hustle`).
---@param src integer player server id
---@param phone table TrapPhone
---@return table hustle
local function hustleOf(src, phone)
    local session = sessions[src]
    if session and session.phoneId ~= phone.id then session = nil end

    local ok, reason = dispatch.canSell()
    local products = {}

    for family, info in pairs(config.Drugs.Families) do
        local row = { family = family, label = info.label, color = info.color, items = {} }

        for item, def in pairs(config.Drugs.Items) do
            if def.family == family then
                local count = inventory.count(src, item) or 0

                if count > 0 then
                    row.items[#row.items + 1] = { item = item, label = items.label(item), unit = def.unit, count = count }
                end
            end
        end

        table.sort(row.items, function(a, b) return a.item < b.item end)
        products[#products + 1] = row
    end

    table.sort(products, function(a, b) return a.label < b.label end)

    return {
        mode = session and session.mode or 'idle',
        family = session and session.family or 'any',
        spotSet = phone.data.spot ~= nil,
        queue = #selling.ticketsOf(src, 'drop'),
        dropsEnabled = DROPS.Enabled == true,
        blocked = not ok and reason or nil,
        products = products,
    }
end

phones.addPart('hustle', hustleOf)

---One line of customer dialogue for a ticket's moment.
---@param ticket TrapTicket
---@param moment string key of config.Dialogue
---@param ... any placeholder values
---@return string line
local function say(ticket, moment, ...)
    return pricing.say(config.Dialogue, moment, ticket.personality, math.random, ...)
end

---The offer as the phone draws it (docs/design.md `Offer`).
---@param ticket TrapTicket
---@return table offer
local function offerOf(ticket)
    return {
        ticketId = ticket.id,
        kind = ticket.kind,
        item = ticket.item,
        label = items.label(ticket.item),
        family = ticket.family,
        unit = config.Drugs.Items[ticket.item].unit,
        qty = ticket.qty,
        price = ticket.total,
        state = ticket.state,
        counters = ticket.counters,
        expires = ticket.expires,
        place = ticket.place,
    }
end

---Create a ticket. It starts 'pending': nothing is texted until selling.open gives it a face.
---@param src integer player server id
---@param phone table TrapPhone
---@param fields { kind: string, item: string, qty: integer, zone: table, seconds?: integer, place?: string, door?: integer }
---@return TrapTicket ticket
function selling.newTicket(src, phone, fields)
    local now = os.time()

    ticketSeq += 1

    local ticket = {
        id = ('tk%d_%05d'):format(ticketSeq, math.random(0, 99999)),
        src = src,
        cid = playerBridge.getIdentifier(src) or ('src' .. src),
        phoneId = phone.id,
        kind = fields.kind,
        item = fields.item,
        family = config.Drugs.Items[fields.item].family,
        qty = fields.qty,
        unit = 0,
        total = 0,
        zone = fields.zone,
        state = 'pending',
        created = now,
        expires = now + (fields.seconds or PENDING_SECONDS),
        counters = 0,
        origin = realCoords(src),
        place = fields.place,
        door = fields.door,
    }

    tickets[ticket.id] = ticket

    return ticket
end

---Give a pending ticket its customer: fix who they are from the look key, roll the price with
---their relationship and the phone's level, and text the offer.
---@param phone table TrapPhone
---@param ticket TrapTicket
---@param pedKey string look key (or any stable id for a created customer)
---@param opts? { moment?: string, bonus?: number, seconds?: number, silent?: boolean }
---@return table offer the offer as texted
function selling.open(phone, ticket, pedKey, opts)
    opts = opts or {}

    local now = os.time()
    local name, personality = pricing.personality(pedKey, CFG.Personalities or {})
    local info = config.Drugs.Items[ticket.item]

    local rolled = pricing.offer({
        entry = PRICES[ticket.item],
        qty = ticket.qty,
        economy = config.Economy,
        wealth = ticket.zone and ticket.zone.wealth,
        relationship = relations.get(ticket.cid, 'ped', pedKey),
        level = progress.level(phone, ticket.family),
        bonus = opts.bonus,
    }, math.random)

    local seconds = opts.seconds or ((CFG.OfferSeconds or 75) * (personality and personality.patience or 1))

    ticket.pedKey = pedKey
    ticket.personality = name
    ticket.number = pricing.customerNumber(pedKey, config.Phone.NumberPrefix)
    ticket.unit = rolled.unit
    ticket.total = rolled.total
    ticket.state = 'open'
    ticket.offered = now
    ticket.expires = now + math.max(MIN_SERVE + 5, math.floor(seconds))
    ticket.counters = HAGGLE.Enabled and (HAGGLE.MaxCounters or 0) or 0

    local contact = phones.getContact(phone, ticket.number)
    local unit = config.Drugs.Units[info.unit]
    local offer = offerOf(ticket)

    phones.message(phone, ticket.number, {
        from = 'them',
        text = say(ticket, opts.moment or 'offer', ticket.qty, unit and unit.short or info.unit,
            config.Drugs.Families[ticket.family].label:lower(), ticket.total),
        offer = offer,
    }, { name = contact and contact.name or nil, kind = contact and 'contact' or 'customer', silent = opts.silent })

    return offer
end

---Move the relationship between a ticket's seller and its customer.
---@param ticket TrapTicket
---@param delta integer|nil
---@return integer value the relationship afterwards
local function moveRelation(ticket, delta)
    if not ticket.pedKey then return 0 end
    if not delta or delta == 0 then return relations.get(ticket.cid, 'ped', ticket.pedKey) end

    return relations.add(ticket.cid, 'ped', ticket.pedKey, delta)
end

---End a ticket: mark its offer on the phone, optionally have the customer say something,
---tell the seller's client so it lets the customer go, and time the next one.
---@param ticket TrapTicket
---@param state 'declined'|'done'|'expired'|'walked' how the offer reads afterwards
---@param moment? string key of config.Dialogue for a parting text
function selling.close(ticket, state, moment)
    if not tickets[ticket.id] then return end

    tickets[ticket.id] = nil
    ticket.state = state

    local phone = phones.get(ticket.phoneId)

    if phone and ticket.number then
        phones.updateOffer(phone, ticket.number, ticket.id, { state = state })

        if moment then
            local line = say(ticket, moment, ticket.total)
            if line ~= '' then phones.message(phone, ticket.number, { from = 'them', text = line }) end
        end
    end

    local hook = hooks[ticket.kind]
    if hook and hook.closed then
        local ok, err = pcall(hook.closed, ticket, state)
        if not ok then log.error('selling', 'close hook for %s failed: %s', ticket.kind, err) end
    end

    local session = sessions[ticket.src]

    if session and ticket.kind ~= 'drop' then
        session.next = os.time() + inRange(CFG.CustomerInterval)
    end

    if GetPlayerName(ticket.src) then
        TriggerClientEvent('sd-trapphone:client:ticketClosed', ticket.src, { ticketId = ticket.id, kind = ticket.kind, state = state })

        if phone and ticket.kind == 'drop' then phones.refresh(phone, 'hustle') end
    end
end

---Stop a player hustling and let every customer of theirs go.
---@param src integer player server id
---@param reasonKey? string locale key; when given the player is told why (a stop they did not ask for)
function selling.stop(src, reasonKey)
    local session = sessions[src]

    sessions[src] = nil

    for _, ticket in ipairs(selling.ticketsOf(src)) do
        selling.close(ticket, 'expired')
    end

    if not session then return end

    local phone = phones.get(session.phoneId)
    if phone then phones.refresh(phone, 'hustle') end

    if reasonKey and GetPlayerName(src) then
        TriggerClientEvent('sd-trapphone:client:hustleStopped', src, { reason = locale(reasonKey) })
    end
end

---Pay a sale out through the configured account: cash or bank, the framework's dirty money,
---or an item handed over one per dollar.
---@param src integer player server id
---@param amount integer
---@return boolean paid
function selling.pay(src, amount)
    local account = config.Economy.PayoutAccount or 'cash'

    if amount <= 0 then return true end

    if account == 'cash' or account == 'bank' then
        if not playerBridge.get(src) then return false end
        money.add(src, account, amount, 'sd-trapphone sale')
        return true
    end

    if account == 'black' then return money.addBlack(src, amount) == true end

    return inventory.add(src, account, amount) == true
end

---Turn a customer into a named regular once the relationship is there.
---@param phone table TrapPhone
---@param ticket TrapTicket
---@param relationship integer the relationship after the sale
local function promote(phone, ticket, relationship)
    if not REL.RegularAt or relationship < REL.RegularAt then return end
    if phones.getContact(phone, ticket.number) then return end

    phones.addContact(phone, {
        number = ticket.number,
        name = pricing.customerName(ticket.pedKey),
        type = 'regular',
        key = ticket.pedKey,
    })

    local line = say(ticket, 'regular')
    if line ~= '' then phones.message(phone, ticket.number, { from = 'them', text = line }) end
end

---Carry a sale out: take the product, then pay, then everything that follows from a sale.
---Nothing is paid unless the product really left the inventory, and if the payout fails the
---product is handed back.
---@param src integer player server id
---@param phone table TrapPhone
---@param ticket TrapTicket an open or accepted ticket that has passed its own checks
---@param opts? { xpScale?: number, stat?: string, thanks?: string, robbery?: boolean }
---@return boolean ok
---@return table|string result { total, tip, xp } or { robbed = true } when ok, a locale key when not
function selling.settle(src, phone, ticket, opts)
    opts = opts or {}

    if ticket.settling then return false, 'selling.busy' end

    local item, qty = ticket.item, ticket.qty

    if (inventory.count(src, item) or 0) < qty then
        selling.close(ticket, 'walked', 'walked')
        return false, 'selling.not_enough'
    end

    ticket.settling = true

    local personality = CFG.Personalities and CFG.Personalities[ticket.personality] or nil
    local relationship = moveRelation(ticket, 0)
    local robbed = opts.robbery == true and relationship < (REL.RegularAt or 101)
        and math.random() * 100 < (CFG.RobberyChance or 0)

    if not inventory.remove(src, item, qty) then
        ticket.settling = nil
        return false, 'selling.remove_failed'
    end

    -- Kept per player as well as per session, so pitching can't dodge an item's cooldown.
    cooling[src] = cooling[src] or {}
    cooling[src][item] = os.time() + (PRICES[item].cooldown or 0)

    local session = sessions[src]
    if session then
        session.cooldowns[item] = os.time() + (PRICES[item].cooldown or 0)
        if ticket.pedKey then session.recent[ticket.pedKey] = os.time() end
    end

    if robbed then
        progress.remove(phone, ticket.family, progress.failLoss(phone, ticket.family))
        moveRelation(ticket, REL.PerRobbery)
        audit.log('sale', src, ('robbed of %d x %s by a customer'):format(qty, items.display(item)),
            { ticket = ticket.id, item = item, qty = qty, robbed = true })
        selling.close(ticket, 'walked', 'robbery')
        phones.refresh(phone, 'hustle')

        return true, { robbed = true }
    end

    local tip = pricing.tip(ticket.total, personality, CFG.TipShare or 0, math.random)
    local paid = ticket.total + tip

    if not selling.pay(src, paid) then
        inventory.add(src, item, qty)
        ticket.settling = nil
        log.error('selling', 'payout of %d to %s failed; %d x %s handed back', paid, src, qty, item)

        return false, 'selling.pay_failed'
    end

    local gain = math.floor(progress.saleGain(phone, ticket.family) * (opts.xpScale or 1))
    progress.add(phone, ticket.family, gain)

    local stats = phone.data.stats
    local stat = opts.stat or 'sales'

    stats[stat] = (stats[stat] or 0) + 1
    stats.earned = (stats.earned or 0) + paid
    phones.touch(phone)
    phones.push(phone, { stats = stats })

    promote(phone, ticket, moveRelation(ticket, REL.PerSale))

    audit.log(ticket.kind == 'drop' and 'drop' or 'sale', src,
        ('sold %d x %s for $%d (%s, %s)'):format(qty, items.display(item), paid, ticket.kind, ticket.zone and ticket.zone.id or '?'),
        { ticket = ticket.id, item = item, qty = qty, total = ticket.total, tip = tip, kind = ticket.kind, zone = ticket.zone and ticket.zone.id })

    selling.close(ticket, 'done', opts.thanks or 'thanks')

    -- The turf module is required here, not at the top, so the two can't load in a circle.
    local loaded, turf = pcall(require, 'server.trapphone.turf')
    if loaded and type(turf) == 'table' and turf.onSale then
        local ok, err = pcall(turf.onSale, src, phone, ticket.zone, ticket.total)
        if not ok then log.error('selling', 'turf.onSale failed: %s', err) end
    end

    dispatch.snitch(src, personality and personality.snitch or 1, 'witness')
    phones.refresh(phone, 'hustle')

    return true, { total = ticket.total, tip = tip, xp = gain }
end

---Mark a ticket accepted, tell the phone, and run the kind's own follow-up.
---@param src integer player server id
---@param phone table TrapPhone
---@param ticket TrapTicket
---@param moment string key of config.Dialogue for the customer's reply
local function accept(src, phone, ticket, moment)
    local hook = hooks[ticket.kind] or {}
    local now = os.time()

    ticket.state = 'accepted'
    ticket.expires = math.max(ticket.expires, now + (hook.acceptSeconds or CFG.OfferSeconds or 75))

    phones.updateOffer(phone, ticket.number, ticket.id,
        { state = 'accepted', price = ticket.total, counters = ticket.counters, expires = ticket.expires })

    local line = say(ticket, moment, ticket.total)
    if line ~= '' then phones.message(phone, ticket.number, { from = 'them', text = line }, { silent = true }) end

    if hook.accepted then
        local ok, err = pcall(hook.accepted, src, phone, ticket)
        if not ok then log.error('selling', 'accept hook for %s failed: %s', ticket.kind, err) end
    end
end

-- The checks drop-offs share with street sales, so both judge a client the same way.
selling.accept = accept
selling.owned = owned
selling.limited = limited
selling.suspect = suspect
selling.coords = realCoords
selling.onFoot = onFoot
selling.isDown = isDown
selling.fail = fail

-- Phone > Hustle > Start. Everything the session depends on is checked here from the server's
-- own view of the player.
lib.callback.register('sd-trapphone:server:hustleStart', function(src, mode, family)
    if limited(src, 'start', 1500) then return fail('selling.slow_down') end

    if mode ~= 'corner' and mode ~= 'drops' then return fail('selling.bad_request') end
    if family ~= 'any' and (type(family) ~= 'string' or not config.Drugs.Families[family]) then
        return fail('selling.bad_request')
    end

    local phone = phones.active(src)
    if not phone then return fail('selling.no_phone') end

    local ok, reason = dispatch.canSell()
    if not ok then return { ok = false, error = reason } end

    if isDown(src) then return fail('selling.not_now') end

    if mode == 'drops' then
        if not DROPS.Enabled then return fail('dropoffs.disabled') end
        if DROPS.RequireVehicle and onFoot(src) then return fail('dropoffs.need_vehicle') end
    elseif not onFoot(src) then
        return fail('selling.on_foot')
    end

    if #selling.sellable(src, family) == 0 then return fail('selling.nothing_to_sell') end

    selling.stop(src)

    local now = os.time()

    sessions[src] = {
        src = src,
        cid = playerBridge.getIdentifier(src) or ('src' .. src),
        phoneId = phone.id,
        mode = mode,
        family = family,
        next = now + math.random(4, 9),
        cooldowns = {},
        recent = {},
    }

    phones.refresh(phone, 'hustle')
    log.debug('selling', '%s started %s (%s)', src, mode, family)

    return { ok = true, data = hustleOf(src, phone) }
end)

lib.callback.register('sd-trapphone:server:hustleStop', function(src)
    selling.stop(src)

    local phone = phones.current(src)

    return { ok = true, data = phone and hustleOf(src, phone) or nil }
end)

-- The pull-up spot is wherever the player really is when they set it, never a place they name.
lib.callback.register('sd-trapphone:server:setSpot', function(src)
    if limited(src, 'spot', 1000) then return fail('selling.slow_down') end

    local phone = phones.current(src)
    if not phone then return fail('selling.no_phone') end
    if not onFoot(src) then return fail('selling.on_foot') end

    local coords = realCoords(src)
    if not coords then return fail('selling.not_now') end

    phone.data.spot = {
        x = math.floor(coords.x * 100 + 0.5) / 100,
        y = math.floor(coords.y * 100 + 0.5) / 100,
        z = math.floor(coords.z * 100 + 0.5) / 100,
        w = math.floor(GetEntityHeading(GetPlayerPed(src)) + 0.5),
    }
    phones.touch(phone)
    phones.refresh(phone, 'hustle')

    return { ok = true, data = hustleOf(src, phone) }
end)

lib.callback.register('sd-trapphone:server:clearSpot', function(src)
    local phone = phones.current(src)
    if not phone then return fail('selling.no_phone') end

    if phone.data.spot ~= nil then
        phone.data.spot = nil
        phones.touch(phone)
        phones.refresh(phone, 'hustle')
    end

    return { ok = true, data = hustleOf(src, phone) }
end)

-- "Who's next": the client asks on its own timer, the server decides when a customer exists
-- and what they want. The reply never carries a price; that waits for the customer's look.
lib.callback.register('sd-trapphone:server:requestCustomer', function(src)
    local session = sessions[src]
    if not session or session.mode ~= 'corner' then return { ok = false, stopped = true } end
    if limited(src, 'request', 1500) then return { ok = false, wait = 2 } end

    local phone = phones.current(src)

    if not phone or phone.id ~= session.phoneId or handsets.count(src) < 1 then
        selling.stop(src, 'selling.stopped_phone')
        return { ok = false, stopped = true }
    end

    if not dispatch.canSell() then
        selling.stop(src, 'dispatch.not_enough_police')
        return { ok = false, stopped = true }
    end

    local now = os.time()

    if streetTicket(src) then return { ok = false, wait = 5 } end
    if now < session.next then return { ok = false, wait = session.next - now } end
    if isDown(src) or not onFoot(src) then return { ok = false, wait = 5 } end

    local stock = selling.sellable(src, session.family)

    if #stock == 0 then
        selling.stop(src, 'selling.stopped_stock')
        return { ok = false, stopped = true }
    end

    local ready, soonest = {}, nil

    for i = 1, #stock do
        local free = session.cooldowns[stock[i].item] or 0

        if free <= now then
            ready[#ready + 1] = stock[i]
        elseif not soonest or free < soonest then
            soonest = free
        end
    end

    if #ready == 0 then return { ok = false, wait = math.max(1, (soonest or now) - now) } end

    local pick = ready[math.random(#ready)]
    local coords = realCoords(src)
    local spot = phone.data.spot
    local kind = 'corner'

    if spot and coords and #(coords - vec3(spot.x, spot.y, spot.z)) <= SPOT_RANGE
        and math.random() * 100 < (CFG.CustomerInVehicleChance or 0) then
        kind = 'car'
    end

    local ticket = selling.newTicket(src, phone, {
        kind = kind,
        item = pick.item,
        qty = pricing.quantity(pick.entry, pick.count, math.random),
        zone = zoneOf(src),
    })

    -- If the client never reports a customer, the next attempt should come soon, not after a
    -- full interval. A closed ticket sets the real interval.
    session.next = now + 5

    return { ok = true, ticketId = ticket.id, kind = kind, spot = kind == 'car' and spot or nil }
end)

-- The client found (or created) the customer and says what they look like. The look decides
-- who they are; the offer is rolled and texted here.
lib.callback.register('sd-trapphone:server:customerLook', function(src, ticketId, pedKey)
    local ticket = owned(src, ticketId)
    if not ticket then return fail('selling.offer_gone') end

    if ticket.state ~= 'pending' or (ticket.kind ~= 'corner' and ticket.kind ~= 'car') then
        suspect(src, ('reported a look for ticket %s in state %s'):format(ticket.id, ticket.state), { ticketId = ticket.id })
        return fail('selling.offer_gone')
    end

    local key = cleanKey(pedKey)
    local phone = phoneFor(src, ticket)

    if not key then
        suspect(src, 'sent a malformed ped look key', { key = tostring(pedKey):sub(1, 60) })
        selling.close(ticket, 'expired')
        return fail('selling.bad_request')
    end

    if not phone then
        selling.close(ticket, 'expired')
        return fail('selling.no_phone')
    end

    local session = sessions[src]
    local now = os.time()

    -- The same look straight after a sale is either the same ped being farmed or a client
    -- picking its favourite key. Either way that customer isn't buying again yet.
    if session and session.recent[key] and now - session.recent[key] < KEY_REUSE then
        selling.close(ticket, 'expired')
        return { ok = false, retry = true }
    end

    local offer = selling.open(phone, ticket, key)

    return { ok = true, number = ticket.number, offer = offer, serveAfter = MIN_SERVE }
end)

-- The client could not produce or keep a customer (nobody around, the ped died or got stuck).
RegisterNetEvent('sd-trapphone:server:customerLost', function(ticketId)
    local src = source
    if limited(src, 'lost', 500) then return end

    local ticket = owned(src, ticketId)
    if not ticket or ticket.kind == 'drop' then return end

    if ticket.state == 'pending' then
        selling.close(ticket, 'expired')
    else
        selling.close(ticket, 'walked', 'walked')
    end
end)

-- Accept, decline or counter an offer from the phone. Works for every kind of ticket; a
-- decline on an accepted ticket is the player calling it off.
lib.callback.register('sd-trapphone:server:offerRespond', function(src, number, ticketId, action, price)
    if limited(src, 'respond', 700) then return fail('selling.slow_down') end

    local ticket = owned(src, ticketId)
    if not ticket or type(number) ~= 'string' or number ~= ticket.number then return fail('selling.offer_gone') end

    local phone = phoneFor(src, ticket)
    if not phone then return fail('selling.no_phone') end

    if ticket.settling then return fail('selling.busy') end

    if os.time() > ticket.expires then
        selling.close(ticket, 'expired', 'walked')
        return fail('selling.offer_gone')
    end

    if action == 'accept' then
        if ticket.state ~= 'open' then return fail('selling.offer_gone') end

        accept(src, phone, ticket, (hooks[ticket.kind] or {}).acceptLine or 'accept')

        return { ok = true, data = { state = ticket.state, price = ticket.total, counters = ticket.counters } }
    end

    if action == 'decline' then
        if ticket.state ~= 'open' and ticket.state ~= 'accepted' then return fail('selling.offer_gone') end

        local state = ticket.state == 'accepted' and 'walked' or 'declined'

        moveRelation(ticket, REL.PerDecline)
        selling.close(ticket, state, 'decline')

        return { ok = true, data = { state = state, price = ticket.total, counters = 0 } }
    end

    if action == 'counter' then
        if not HAGGLE.Enabled then return fail('selling.no_haggle') end
        if ticket.state ~= 'open' or ticket.counters <= 0 then return fail('selling.no_haggle') end

        if type(price) ~= 'number' or price ~= price or price ~= math.floor(price)
            or price <= ticket.total or price > MAX_PRICE then
            return fail('selling.bad_price')
        end

        local ask = math.floor(price)
        local personality = CFG.Personalities and CFG.Personalities[ticket.personality] or nil

        local chance = pricing.haggleChance({
            offer = ticket.total,
            ask = ask,
            ceiling = pricing.ceiling(PRICES[ticket.item], ticket.qty),
            haggle = HAGGLE,
            shift = personality and personality.haggle or 0,
            relationship = moveRelation(ticket, 0),
            relationshipShift = REL.HaggleShift or 0,
        })
        local won = math.random() < chance

        audit.log('haggle', src, ('countered $%d with $%d (%d%%): %s'):format(ticket.total, ask, math.floor(chance * 100), won and 'taken' or 'refused'),
            { ticket = ticket.id, offer = ticket.total, ask = ask, chance = chance, won = won })

        if won then
            ticket.total = ask
            ticket.counters = 0
            moveRelation(ticket, REL.PerHaggleWin)
            accept(src, phone, ticket, 'counter_ok')
        else
            ticket.counters -= 1
            moveRelation(ticket, REL.PerHaggleFail)

            if ticket.counters <= 0 then
                selling.close(ticket, 'walked', 'walked')
            else
                phones.updateOffer(phone, ticket.number, ticket.id, { counters = ticket.counters })
                phones.message(phone, ticket.number, { from = 'them', text = say(ticket, 'counter_no', ticket.total) }, { silent = true })
            end
        end

        return { ok = true, data = { state = ticket.state, price = ticket.total, counters = ticket.counters, won = won } }
    end

    return fail('selling.bad_request')
end)

-- The hand-off was played out. This is the only place a street sale pays.
lib.callback.register('sd-trapphone:server:completeSale', function(src, ticketId)
    if limited(src, 'complete', 700) then return fail('selling.slow_down') end

    local ticket = owned(src, ticketId)
    if not ticket then return fail('selling.offer_gone') end

    if ticket.kind == 'drop' then
        suspect(src, ('tried to complete drop-off %s as a street sale'):format(ticket.id), { ticketId = ticket.id })
        return fail('selling.bad_request')
    end

    if ticket.state ~= 'open' and ticket.state ~= 'accepted' then return fail('selling.offer_gone') end

    local now = os.time()

    if now > ticket.expires then
        selling.close(ticket, 'expired', 'walked')
        return fail('selling.offer_gone')
    end

    if now - (ticket.offered or now) < MIN_SERVE then
        suspect(src, ('completed ticket %s %d s after the offer'):format(ticket.id, now - (ticket.offered or now)), { ticketId = ticket.id })
        return fail('selling.too_fast')
    end

    local phone = phoneFor(src, ticket)
    if not phone then
        selling.close(ticket, 'expired')
        return fail('selling.no_phone')
    end

    if isDown(src) or not onFoot(src) then return fail('selling.on_foot') end

    local coords = realCoords(src)

    if not coords or (ticket.origin and #(coords - ticket.origin) > MAX_SALE_DISTANCE) then
        suspect(src, ('completed ticket %s far from where it was made'):format(ticket.id),
            { ticketId = ticket.id, distance = coords and ticket.origin and #(coords - ticket.origin) or -1 })
        selling.close(ticket, 'walked', 'walked')
        return fail('selling.too_far')
    end

    local ok, result = selling.settle(src, phone, ticket, { robbery = true })
    if not ok then return fail(result) end

    return { ok = true, data = result }
end)

-- Walking up to a ped and offering. They either want nothing to do with it, or there is a
-- ticket that is served on the spot.
lib.callback.register('sd-trapphone:server:pitch', function(src, pedKey)
    if not CFG.ApproachEnabled then return fail('selling.bad_request') end
    if limited(src, 'pitch', 3000) then return fail('selling.slow_down') end

    local key = cleanKey(pedKey)
    if not key then
        suspect(src, 'sent a malformed ped look key with a pitch', { key = tostring(pedKey):sub(1, 60) })
        return fail('selling.bad_request')
    end

    local phone = phones.active(src)
    if not phone then return fail('selling.no_phone') end

    local ok, reason = dispatch.canSell()
    if not ok then return { ok = false, error = reason } end

    if isDown(src) or not onFoot(src) then return fail('selling.on_foot') end
    if streetTicket(src) then return fail('selling.busy') end

    local now = os.time()
    local mine = pitched[src]

    if not mine then
        mine = {}
        pitched[src] = mine
    end

    for seen, at in pairs(mine) do
        if now - at >= PITCH_MEMORY then mine[seen] = nil end
    end

    if mine[key] then return fail('selling.already_pitched') end

    local session = sessions[src]
    local stock = selling.sellable(src, session and session.mode == 'corner' and session.family or 'any')
    if #stock == 0 then return fail('selling.nothing_to_sell') end

    local resting, ready = cooling[src] or {}, {}

    for i = 1, #stock do
        if (resting[stock[i].item] or 0) <= now then ready[#ready + 1] = stock[i] end
    end

    if #ready == 0 then return fail('selling.slow_down') end
    stock = ready

    mine[key] = now

    local cid = playerBridge.getIdentifier(src) or ('src' .. src)
    local name, personality = pricing.personality(key, CFG.Personalities or {})
    local pick = stock[math.random(#stock)]
    local refuse = pricing.refuseChance(CFG.RefuseDrugsChance or 0, relations.get(cid, 'ped', key), REL.RegularAt)

    if math.random() * 100 < refuse then
        progress.remove(phone, pick.info.family, progress.failLoss(phone, pick.info.family))
        dispatch.snitch(src, personality and personality.snitch or 1, 'pitch')

        return { ok = false, refused = true, error = pricing.say(config.Dialogue, 'refused', name, math.random) }
    end

    local ticket = selling.newTicket(src, phone, {
        kind = 'pitch',
        item = pick.item,
        qty = pricing.quantity(pick.entry, pick.count, math.random),
        zone = zoneOf(src),
    })
    local offer = selling.open(phone, ticket, key, { silent = true })

    return { ok = true, ticketId = ticket.id, number = ticket.number, offer = offer, serveAfter = MIN_SERVE }
end)

-- Tickets run out on their own: a customer who was never given a face is dropped quietly, an
-- open or accepted offer that timed out means the customer walked.
CreateThread(function()
    while true do
        Wait(3000)

        local now = os.time()
        local expired = {}

        for _, ticket in pairs(tickets) do
            if now > ticket.expires and not ticket.settling then expired[#expired + 1] = ticket end
        end

        for i = 1, #expired do
            local ticket = expired[i]

            if ticket.state == 'pending' then
                selling.close(ticket, 'expired')
            elseif ticket.state == 'accepted' then
                moveRelation(ticket, REL.PerDecline)
                selling.close(ticket, 'expired', (hooks[ticket.kind] or {}).lateLine or 'walked')
            else
                selling.close(ticket, 'expired', 'walked')
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    local src = source

    selling.stop(src)

    for _, ticket in ipairs(selling.ticketsOf(src)) do
        selling.close(ticket, 'expired')
    end

    stamps[src] = nil
    pitched[src] = nil
    cooling[src] = nil
end)

return selling
