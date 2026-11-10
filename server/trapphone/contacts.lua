---@type table sd-trapphone config root (configs/config.lua).
local config = require 'configs.config'
---@type table Console log helper (shared.log).
local log = require 'shared.log'
---@type table Turf map resolver (shared.zones).
local zones = require 'shared.zones'
---@type table Item label lookups (shared.items).
local items = require 'shared.items'
---@type table Audit-log helper (server.trapphone.audit).
local audit = require 'server.trapphone.audit'
---@type table Live phones (server.trapphone.phones).
local phones = require 'server.trapphone.phones'
---@type table XP and levels (server.trapphone.progress).
local progress = require 'server.trapphone.progress'
---@type table Turf and gang standing (server.trapphone.turf).
local turf = require 'server.trapphone.turf'
---@type table Back-room services (server.trapphone.services): locations, charge / refund.
local services = require 'server.trapphone.services'
---@type table Inventory bridge (bridge.server.inventory).
local inventory = require 'bridge.server.inventory'
---@type table Notify bridge (bridge.server.notify).
local notify = require 'bridge.server.notify'

---@type table Contact config (config.Contacts): the shared types merged with the server list.
local CFG = config.Contacts
---@type table Contact and gang texts (config.Lines).
local LINES = config.Lines

---@class TrapPendingMeet
---@field kind 'intro'|'order'
---@field meetup integer index into the contact's meetups
---@field expires integer os.time() the contact stops waiting
---@field reminded? boolean the "still here" text went out
---@field lines? { item: string, qty: integer }[] (order) what was asked for
---@field total? integer (order) what it costs

---@type table Contacts module; the table returned at end of file. The people a growing
---business meets: who reaches out and when, meeting them, and everything their number does
---on the phone afterwards.
local contacts = {}

---@type table<string, table> Configured contacts by key.
local byKey = {}
---@type table<string, table> Configured contacts by number.
local byNumber = {}

for _, def in ipairs(CFG.List or {}) do
    byKey[def.key] = def
    byNumber[def.number] = def
end

---@type number How close a player must stand to the contact to meet them, in metres.
local MEET_RANGE = 8.0
---@type number How close another player must stand to be handed a number, in metres.
local SHARE_RANGE = 3.5
---@type integer Seconds left on a meet when the contact texts a reminder.
local REMIND_AT = 180
---@type integer Milliseconds between two contact actions from one player.
local PACE_MS = 300
---@type integer Seconds between two requests for an introduction from one player.
local INTRO_REQUEST_COOLDOWN = 300

---@type table<integer, integer> GetGameTimer() of each player's last contact action.
local pace = {}
---@type table<integer, integer> os.time() of each player's last number hand-over.
local lastShare = {}
---@type table<integer, integer> os.time() of each player's last introduction request.
local lastIntroRequest = {}
---@type table<string, boolean> Replies already on their way, by phone id and number.
local replying = {}

---One random line from a list, formatted. A broken translation never errors an action.
---@param list string[]|nil
---@param ... any format arguments
---@return string|nil text
local function line(list, ...)
    if type(list) ~= 'table' or #list == 0 then return nil end

    local ok, text = pcall(string.format, list[math.random(#list)], ...)

    return ok and text or nil
end

---Text a phone as one of the configured contacts.
---@param phone table TrapPhone
---@param def table configured contact
---@param text string|nil nothing is sent when nil
local function textFrom(phone, def, text)
    if not text then return end

    phones.message(phone, def.number, { from = 'them', text = text }, { name = def.name, kind = 'contact' })
end

---Whether a configured contact can exist on this server: its type is known and the feature
---behind it is switched on.
---@param def table configured contact
---@return boolean usable
local function usable(def)
    if not CFG.Types[def.type] or type(def.meetups) ~= 'table' or #def.meetups == 0 then return false end

    if def.type == 'gang' then return config.Gangs.Enabled and config.Gangs.List[def.gang] ~= nil end
    if def.type == 'launderer' then return config.Services.MoneyWash.Enabled == true end
    if def.type == 'fixer' then return config.Services.BlackMarket.Enabled == true end
    if def.type == 'plug' or def.type == 'supplier' then return type(def.stock) == 'table' end
    if def.type == 'informant' then return type(def.intel) == 'table' end

    return true
end

---The area a meetup is in, as a contact would name it.
---@param def table configured contact
---@param index integer meetup index
---@return string label
local function placeOf(def, index)
    local spawn = def.meetups[index].spawn

    return zones.at(spawn.x, spawn.y).label
end

---A player's real position, or nil when they have no ped yet.
---@param src integer player server id
---@return vector3|nil coords
local function coordsOf(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end

    return GetEntityCoords(ped)
end

---Send the holder of a phone its pending meets, so the client can mark and stage them.
---@param phone table TrapPhone
local function pushMeets(phone)
    local src = phones.holderOf(phone)
    if src then TriggerClientEvent('sd-trapphone:client:meets', src, contacts.meetsFor(phone)) end
end

---Drop the meets on a phone whose contact stopped waiting, and send the one reminder.
---@param phone table TrapPhone
---@return boolean changed whether any meet was dropped
local function sweep(phone)
    local now = os.time()
    local changed = false

    for key, meet in pairs(phone.data.pending) do
        local def = byKey[key]

        if not def or not def.meetups[meet.meetup] or now >= meet.expires then
            phone.data.pending[key] = nil
            changed = true
            if def then textFrom(phone, def, line(LINES.meet.missed)) end
        elseif not meet.reminded and meet.expires - now <= REMIND_AT then
            meet.reminded = true
            textFrom(phone, def, line(LINES.meet.reminder, placeOf(def, meet.meetup)))
        end
    end

    if changed then phones.touch(phone) end

    return changed
end

---A phone's pending meets as the client stages them.
---@param phone table TrapPhone
---@return table[] meets { key, kind, name, model, spawn, walkTo?, left, label }
function contacts.meetsFor(phone)
    sweep(phone)

    local now = os.time()
    local list = {}

    for key, meet in pairs(phone.data.pending) do
        local def = byKey[key]
        local meetup = def.meetups[meet.meetup]

        list[#list + 1] = {
            key = key,
            kind = meet.kind,
            name = def.name,
            model = def.model,
            spawn = meetup.spawn,
            walkTo = meetup.walkTo,
            left = meet.expires - now,
            label = placeOf(def, meet.meetup),
        }
    end

    return list
end

---Ping the player's everyday phone (sd-phone) about a contact reaching out, when that
---resource is running and the config allows it.
---@param src integer player server id
---@param def table configured contact
---@param text string
local function pingSdPhone(src, def, text)
    local cfg = config.Phone.SdPhone
    if not cfg or not cfg.Enabled or not cfg.NotifyIntros then return end
    if GetResourceState('sd-phone') ~= 'started' then return end

    pcall(function()
        exports['sd-phone']:notify(src, { title = locale('contacts.sdphone_title', def.number), description = text })
    end)
end

---Have a contact reach out to a phone: a text with a meeting place and a pending meet.
---@param phone table TrapPhone
---@param src integer|nil the player carrying it, when online
---@param opts? { key?: string, force?: boolean } key names the contact; force skips the unlock
---rule and the pending limit (admin)
---@return boolean introduced
---@return string|nil reason why not: 'limit' | 'none' | 'unknown' | 'met' | 'pending'
function contacts.introduce(phone, src, opts)
    opts = opts or {}
    sweep(phone)

    local waiting = 0

    for _, meet in pairs(phone.data.pending) do
        if meet.kind == 'intro' then waiting += 1 end
    end

    if not opts.force and waiting >= CFG.MaxPendingIntros then return false, 'limit' end

    local def

    if opts.key then
        def = byKey[opts.key]

        if not def or not usable(def) then return false, 'unknown' end
        if phone.data.met[def.key] then return false, 'met' end
        if phone.data.pending[def.key] then return false, 'pending' end
        if not opts.force and not progress.meets(phone, def.unlock) then return false, 'none' end
    else
        local eligible = {}

        for _, candidate in ipairs(CFG.List) do
            if usable(candidate) and not phone.data.met[candidate.key] and not phone.data.pending[candidate.key]
                and (opts.force or progress.meets(phone, candidate.unlock)) then
                eligible[#eligible + 1] = candidate
            end
        end

        if #eligible == 0 then return false, 'none' end

        def = eligible[math.random(#eligible)]
    end

    local meetup = math.random(#def.meetups)

    phone.data.pending[def.key] = { kind = 'intro', meetup = meetup, expires = os.time() + CFG.MeetWaitMinutes * 60 }
    phones.touch(phone)

    local text = line(LINES.intro[def.type], placeOf(def, meetup)) or locale('contacts.intro_fallback', placeOf(def, meetup))

    -- Their name is not known yet: the first text comes from a bare number.
    phones.message(phone, def.number, { from = 'them', text = text }, { kind = 'contact' })
    pushMeets(phone)

    if src then pingSdPhone(src, def, text) end

    log.debug('contacts', '%s reached out to phone %s', def.key, phone.id)

    return true
end

---What a contact stocks, as the phone lists it.
---@param phone table TrapPhone
---@param def table configured plug / supplier
---@return table[] list { item, label, price, min, max, locked? }
local function stockList(phone, def)
    local list = {}

    for item, info in pairs(def.stock) do
        local product = config.Drugs.Items[item]
        local level = product and progress.level(phone, product.family) or progress.bestLevel(phone)

        list[#list + 1] = {
            item = item,
            label = items.label(item),
            price = info.price,
            min = info.min or 1,
            max = info.max or 1,
            locked = (info.level and level < info.level) or nil,
        }
    end

    table.sort(list, function(a, b)
        if a.price ~= b.price then return a.price < b.price end
        return a.item < b.item
    end)

    return list
end

---Seconds until a contact takes another order from a phone.
---@param phone table TrapPhone
---@param def table configured contact
---@return integer seconds 0 when they are ready
local function orderCooldown(phone, def)
    local last = phone.data.ordered and phone.data.ordered[def.key] or 0

    return math.max(0, last + CFG.Order.CooldownMinutes * 60 - os.time())
end

---Validate the lines of an order a client sent against a contact's stock.
---@param phone table TrapPhone
---@param def table configured plug / supplier
---@param raw any what the client sent as args.lines
---@return { item: string, qty: integer }[]|nil lines nil when anything about it is wrong
---@return integer total
local function cleanOrder(phone, def, raw)
    if type(raw) ~= 'table' or #raw < 1 or #raw > CFG.Order.MaxLines then return nil, 0 end

    local stock = {}

    for _, entry in ipairs(stockList(phone, def)) do stock[entry.item] = entry end

    local lines, seen, total = {}, {}, 0

    for i = 1, #raw do
        local entry = raw[i]
        local item = type(entry) == 'table' and entry.item
        local qty = type(entry) == 'table' and entry.qty
        local info = type(item) == 'string' and stock[item] or nil

        if not info or info.locked or seen[item] then return nil, 0 end
        if type(qty) ~= 'number' or qty ~= math.floor(qty) or qty < info.min or qty > info.max then return nil, 0 end

        seen[item] = true
        lines[#lines + 1] = { item = item, qty = qty }
        total += info.price * qty
    end

    return lines, total
end

---Hand a collected order over: pay first, then give, refunding any line that will not fit.
---@param src integer player server id
---@param phone table TrapPhone
---@param def table configured plug / supplier
---@param meet TrapPendingMeet the order being collected
---@return boolean ok
---@return table|string result { kind, total, items } on success, a localized error otherwise
local function collectOrder(src, phone, def, meet)
    local account = CFG.Order.PayWith
    local prices = def.stock

    for _, entry in ipairs(meet.lines) do
        if not prices[entry.item] or not inventory.canCarry(src, entry.item, entry.qty) then
            textFrom(phone, def, line(LINES.order.cantCarry))
            return false, locale('contacts.order_cant_carry')
        end
    end

    if not services.charge(src, account, meet.total, 'trapphone-order') then
        textFrom(phone, def, line(LINES.order.broke, meet.total))
        return false, locale('contacts.cant_afford', meet.total)
    end

    local given, charged = {}, meet.total

    for _, entry in ipairs(meet.lines) do
        local ok, added = pcall(inventory.add, src, entry.item, entry.qty)

        if ok and added then
            given[#given + 1] = { item = entry.item, label = items.label(entry.item), qty = entry.qty }
        else
            local back = prices[entry.item].price * entry.qty

            charged -= back
            services.refund(src, account, back, 'trapphone-order-refund')
        end
    end

    phone.data.pending[def.key] = nil
    phones.touch(phone)
    pushMeets(phone)

    if #given == 0 then return false, locale('contacts.order_cant_carry') end

    audit.log('order', src, ('collected an order from %s for $%d'):format(def.key, charged), { contact = def.key, total = charged, items = given })
    textFrom(phone, def, line(LINES.order.collected))

    return true, { kind = 'order', name = def.name, total = charged, items = given }
end

---@type table<string, fun(src: integer, phone: table, contact: table, def: table|nil, args: table): boolean, table|string|nil>
---What each contact action does. Returns ok plus the reply data, or false plus a localized error.
local actions = {}

---The page opens the conversation itself; this only confirms the number is real.
function actions.message(_, _, contact)
    return true, { number = contact.number }
end

---No lines: what they stock. With lines: place the order and get a meeting place.
function actions.order(src, phone, _, def, args)
    if not def or type(def.stock) ~= 'table' then return false, locale('contacts.not_available') end

    local cooldown = orderCooldown(phone, def)

    if args.lines == nil then
        return true, { items = stockList(phone, def), cooldown = cooldown > 0 and cooldown or nil, payWith = CFG.Order.PayWith }
    end

    if phone.data.pending[def.key] then
        textFrom(phone, def, line(LINES.order.waiting))
        return false, locale('contacts.order_waiting')
    end

    if cooldown > 0 then
        textFrom(phone, def, line(LINES.order.cooldown, math.ceil(cooldown / 60)))
        return false, locale('contacts.order_cooldown', math.ceil(cooldown / 60))
    end

    local lines, total = cleanOrder(phone, def, args.lines)

    if not lines then
        audit.log('suspect', src, 'sent an order the contact does not sell', { contact = def.key })
        return false, locale('contacts.order_invalid')
    end

    local meetup = math.random(#def.meetups)
    local expires = os.time() + CFG.MeetWaitMinutes * 60

    phone.data.pending[def.key] = { kind = 'order', meetup = meetup, expires = expires, lines = lines, total = total }
    phone.data.ordered = phone.data.ordered or {}
    phone.data.ordered[def.key] = os.time()
    phones.touch(phone)

    textFrom(phone, def, line(LINES.order.confirm, placeOf(def, meetup), total))
    pushMeets(phone)

    return true, { total = total, place = placeOf(def, meetup), expires = expires }
end

---No confirm: the price of protection. With confirm: pay for it.
function actions.bribe(src, _, _, def, args)
    if not def or not def.gang then return false, locale('contacts.not_available') end

    if args.confirm ~= true then return true, turf.bribeQuote(src, def.gang) end

    return turf.bribe(src, def.gang)
end

---Where the player stands with the crew this contact speaks for.
function actions.standing(src, _, _, def)
    local gang = def and def.gang and config.Gangs.List[def.gang]
    local owner = turf.ownerOf(src)

    if not gang or not owner then return false, locale('contacts.not_available') end

    local standing = turf.standing(turf.rep(owner, def.gang))

    return true, {
        label = gang.label,
        color = gang.color,
        standing = standing.id,
        standingLabel = standing.label,
        protectedUntil = turf.protectedUntil(owner, def.gang),
    }
end

---No confirm: what a tip costs. With confirm: pay, and the tip arrives as a text.
function actions.intel(src, phone, _, def, args)
    if not def or type(def.intel) ~= 'table' then return false, locale('contacts.not_available') end

    local price = def.intel.price

    if args.confirm ~= true then return true, { price = price } end

    phone.data.tipped = phone.data.tipped or {}

    local wait = (phone.data.tipped[def.key] or 0) + CFG.IntelCooldown - os.time()

    if wait > 0 then return false, locale('contacts.intel_cooldown', math.ceil(wait / 60)) end

    if not services.charge(src, CFG.IntelPayWith, price, 'trapphone-intel') then
        return false, locale('contacts.cant_afford', price)
    end

    phone.data.tipped[def.key] = os.time()
    phones.touch(phone)

    -- The tip is about the family this phone is best at (ties go to the first by name).
    local families = {}

    for family in pairs(config.Drugs.Families) do families[#families + 1] = family end
    table.sort(families)

    local best = families[1]

    for i = 2, #families do
        if progress.level(phone, families[i]) > progress.level(phone, best) then best = families[i] end
    end

    local zone = best and turf.hotZone(best)
    local text = zone and line(LINES.intel.tip, zone.label, config.Drugs.Families[best].label:lower()) or line(LINES.intel.none)

    -- A beat later, like someone typing it out.
    SetTimeout(math.random(2000, 4000), function()
        textFrom(phone, def, text)
    end)

    return true, { price = price, sent = true }
end

---Mark the laundry on the map.
function actions.wash(src)
    local coords = services.nearest(src, 'wash')
    if not coords then return false, locale('contacts.not_available') end

    return true, { label = config.Services.MoneyWash.Blip.label, coords = vec3(coords.x, coords.y, coords.z) }
end

---Mark the back room on the map.
function actions.market(src)
    local coords = services.nearest(src, 'market')
    if not coords then return false, locale('contacts.not_available') end

    return true, { label = config.Services.BlackMarket.Blip.label, coords = vec3(coords.x, coords.y, coords.z) }
end

---Point the map at this contact's pending meet.
function actions.route(_, phone, contact, def)
    def = def or byNumber[contact.number]
    sweep(phone)

    local meet = def and phone.data.pending[def.key]
    if not meet then return false, locale('contacts.no_meet') end

    local spawn = def.meetups[meet.meetup].spawn

    return true, { label = placeOf(def, meet.meetup), coords = vec3(spawn.x, spawn.y, spawn.z), left = meet.expires - os.time() }
end

---Hand this number to the nearest player who carries a trap phone.
function actions.share(src, phone, contact, def)
    if not CFG.CanPassNumbers then return false, locale('contacts.share_off') end
    if contact.type == 'regular' then return false, locale('contacts.share_regular') end

    local now = os.time()

    if now - (lastShare[src] or 0) < 5 then return false, locale('contacts.slow_down') end
    lastShare[src] = now

    local here = coordsOf(src)
    if not here then return false, locale('contacts.share_nobody') end

    local otherSrc, otherPhone, nearest

    for _, id in ipairs(GetPlayers()) do
        local candidate = tonumber(id) --[[@as integer]]
        local there = candidate ~= src and coordsOf(candidate)
        local distance = there and #(here - there)

        if distance and distance <= SHARE_RANGE and (not nearest or distance < nearest) then
            local theirs = phones.current(candidate) or phones.active(candidate)

            if theirs and theirs.id ~= phone.id then otherSrc, otherPhone, nearest = candidate, theirs, distance end
        end
    end

    if not otherPhone then return false, locale('contacts.share_nobody') end

    local existing = phones.getContact(otherPhone, contact.number)

    if existing and (not def or otherPhone.data.met[def.key]) then return false, locale('contacts.share_has') end

    if def then
        -- A vouched-for introduction: the contact is met without the walk.
        otherPhone.data.met[def.key] = true

        if otherPhone.data.pending[def.key] then
            otherPhone.data.pending[def.key] = nil
            pushMeets(otherPhone)
        end

        phones.addContact(otherPhone, { number = def.number, name = def.name, type = def.type, key = def.key, gang = def.gang })
        textFrom(otherPhone, def, line(LINES.share.received, def.name))
        audit.log('contact_met', otherSrc, ('was handed %s by player %d'):format(def.key, src), { contact = def.key, from = src, phone = otherPhone.id })

        if def.type == 'launderer' or def.type == 'fixer' then services.sync(otherSrc) end
    else
        phones.addContact(otherPhone, { number = contact.number, name = contact.name, type = contact.type == 'player' and 'player' or 'custom' })
    end

    notify.to(otherSrc, locale('contacts.share_received', contact.name), 'success')

    return true, { shared = true, name = contact.name }
end

---Whether an action is one this contact's type offers (plus the two every contact has).
---@param contact table saved contact
---@param action string
---@return boolean allowed
local function offers(contact, action)
    if action == 'share' or action == 'route' then return true end

    local info = CFG.Types[contact.type]

    return info ~= nil and lib.table.contains(info.actions, action)
end

-- Everything a contact's screen on the phone can do. One entry point so every action gets the
-- same checks: a real phone in their pocket, a contact saved on it, an action that contact
-- type offers, and for special contacts, one that was actually met.
lib.callback.register('sd-trapphone:server:contactAction', function(src, number, action, args)
    local now = GetGameTimer()

    if now - (pace[src] or -PACE_MS) < PACE_MS then return { ok = false, error = locale('contacts.slow_down') } end
    pace[src] = now

    if type(number) ~= 'string' or #number > 16 or type(action) ~= 'string' or not actions[action] then
        return { ok = false, error = locale('contacts.not_available') }
    end
    if args ~= nil and type(args) ~= 'table' then return { ok = false, error = locale('contacts.not_available') } end

    local phone = phones.active(src)
    if not phone then return { ok = false, error = locale('contacts.no_phone') } end

    local contact = phones.getContact(phone, number)
    if not contact then return { ok = false, error = locale('contacts.unknown') } end

    if not offers(contact, action) then
        audit.log('suspect', src, 'asked a contact for something its type does not do', { number = number, type = contact.type, action = action })
        return { ok = false, error = locale('contacts.not_available') }
    end

    -- A special contact only answers on a phone that met them. A number typed in cold, or a
    -- type set by another resource, gets the plain actions and nothing else.
    local def = contact.key and byKey[contact.key] or nil

    if def and (def.number ~= number or def.type ~= contact.type or not phone.data.met[def.key] or not usable(def)) then def = nil end

    if not def and action ~= 'message' and action ~= 'share' and action ~= 'route' then
        return { ok = false, error = locale('contacts.not_available') }
    end

    local ok, okAction, result = pcall(actions[action], src, phone, contact, def, args or {})

    if not ok then
        log.error('contacts', 'action %s failed: %s', action, okAction)
        return { ok = false, error = locale('contacts.not_available') }
    end

    if not okAction then return { ok = false, error = result } end

    return { ok = true, data = result }
end)

lib.callback.register('sd-trapphone:server:meets', function(src)
    local phone = phones.current(src) or phones.active(src)

    return phone and contacts.meetsFor(phone) or {}
end)

-- Meeting a contact at the place they named: a first introduction, or collecting an order.
-- The player's real position decides whether they are actually there.
lib.callback.register('sd-trapphone:server:meetContact', function(src, key)
    local now = GetGameTimer()

    if now - (pace[src] or -PACE_MS) < PACE_MS then return { ok = false, error = locale('contacts.slow_down') } end
    pace[src] = now

    local def = type(key) == 'string' and byKey[key] or nil
    local phone = phones.active(src)

    if not phone then return { ok = false, error = locale('contacts.no_phone') } end
    if not def then return { ok = false, error = locale('contacts.no_meet') } end

    if sweep(phone) then pushMeets(phone) end

    local meet = phone.data.pending[def.key]
    if not meet then return { ok = false, error = locale('contacts.no_meet') } end

    local here = coordsOf(src)
    local spawn = def.meetups[meet.meetup].spawn
    local distance = here and #(here - vec3(spawn.x, spawn.y, spawn.z)) or math.huge

    if distance > MEET_RANGE then
        audit.log('suspect', src, 'tried to meet a contact from far away', { contact = def.key, distance = distance })
        return { ok = false, error = locale('contacts.too_far') }
    end

    if meet.kind == 'order' then
        local ok, result = collectOrder(src, phone, def, meet)

        if not ok then return { ok = false, error = result } end

        return { ok = true, data = result }
    end

    phone.data.met[def.key] = true
    phone.data.pending[def.key] = nil
    phones.touch(phone)

    -- The cold text that set this up sits in a thread with no name; it becomes theirs now.
    local thread = phone.data.threads[def.number]
    if thread then thread.kind = 'contact' end

    phones.addContact(phone, { number = def.number, name = def.name, type = def.type, key = def.key, gang = def.gang })
    pushMeets(phone)
    textFrom(phone, def, line(LINES.met[def.type]))

    audit.log('contact_met', src, ('met %s (%s)'):format(def.name, def.key), { contact = def.key, type = def.type, phone = phone.id })

    if def.type == 'launderer' or def.type == 'fixer' then services.sync(src) end

    return { ok = true, data = { kind = 'intro', name = def.name, type = def.type } }
end)

-- The client export meetNewContact asking for an introduction. It gets the same odds and the
-- same unlock rules as a level-up, and only now and then, so it is no shortcut.
lib.callback.register('sd-trapphone:server:requestIntro', function(src)
    local now = os.time()

    if now - (lastIntroRequest[src] or 0) < INTRO_REQUEST_COOLDOWN then return false end
    lastIntroRequest[src] = now

    local phone = phones.active(src)
    if not phone or math.random(100) > CFG.IntroChance then return false end

    return (contacts.introduce(phone, src))
end)

-- A level gained is the moment someone hears about you.
progress.onLevelUp(function(phone, _, _, src)
    if math.random(100) > CFG.IntroChance then return end

    contacts.introduce(phone, src)
end)

-- A text typed at a contact's number. Met contacts answer in character; a number that was
-- never met answers like a stranger would.
phones.onMessage(function(_, phone, number, text)
    local def = byNumber[number]
    if not def then return end

    local tag = phone.id .. '|' .. number

    if replying[tag] then return end
    replying[tag] = true

    SetTimeout(math.random(2000, 5000), function()
        replying[tag] = nil

        local met = phone.data.met[def.key] == true
        local meet = phone.data.pending[def.key]
        local asked = text:lower()
        local reply

        if meet and def.meetups[meet.meetup] and (asked:find('where', 1, true) or asked:find('meet', 1, true) or asked:find('wya', 1, true)) then
            reply = line(LINES.reply.where, placeOf(def, meet.meetup))
        elseif met then
            reply = line(LINES.reply[def.type])
        else
            reply = line(LINES.reply.unknown)
        end

        if not reply then return end

        phones.message(phone, number, { from = 'them', text = reply }, { name = met and def.name or nil, kind = 'contact' })
    end)
end)

-- Contacts stop waiting whether or not anyone is looking at the phone.
CreateThread(function()
    while true do
        Wait(20000)

        for _, id in ipairs(GetPlayers()) do
            local phone = phones.current(tonumber(id) --[[@as integer]])

            if phone then
                local ok, changed = pcall(sweep, phone)

                if not ok then
                    log.error('contacts', 'sweeping phone %s failed: %s', phone.id, changed)
                elseif changed then
                    pushMeets(phone)
                end
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    local src = source

    pace[src] = nil
    lastShare[src] = nil
    lastIntroRequest[src] = nil
end)

---A configured contact by key (nil for an unknown one). Read-only.
---@param key string
---@return table|nil def
function contacts.get(key)
    return byKey[key]
end

return contacts
