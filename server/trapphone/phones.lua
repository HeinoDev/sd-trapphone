---@type table sd-trapphone config root (configs/config.lua).
local config = require 'configs.config'
---@type table Console log helper (shared.log): tagged color-coded prints.
local log = require 'shared.log'
---@type table Audit-log helper (server.trapphone.audit).
local audit = require 'server.trapphone.audit'
---@type table Server-side persistence module (server.trapphone.store).
local store = require 'server.trapphone.store'
---@type table Player bridge (bridge.server.player): identifier lookups.
local playerBridge = require 'bridge.server.player'
---@type table Inventory bridge (bridge.server.inventory): slot + metadata access.
local inventory = require 'bridge.server.inventory'

---@type table Handset items and colours (shared.handsets).
local handsets = require 'shared.handsets'

---@type table Handset config (config.Phone).
local CFG = config.Phone

---@class TrapMessage
---@field id integer per-thread running id
---@field from 'me'|'them'
---@field text string
---@field ts integer os.time() when it was sent
---@field offer? table an open sale offer riding on this message (see docs/design.md)

---@class TrapThread
---@field name string who the conversation is with, as shown
---@field kind 'customer'|'contact'|'player'|'system'
---@field unread integer
---@field ts integer os.time() of the last message
---@field seq integer last message id handed out
---@field msgs TrapMessage[]

---@class TrapPhone
---@field id string
---@field number string
---@field owner string|nil character id of whoever last held it
---@field data table persisted state: xp, contacts, threads, settings, stats, scores, spot, met, pending
---@field holder integer|nil server id of the player currently carrying it
---@field shell string|nil faceplate id of the item it was last used from
---@field dirty boolean needs saving

---@type table Phones module; the table returned at end of file. Owns every live phone: which
---one a player is carrying, its messages and contacts, and getting changes to the handset.
local phones = {}

---@type table<string, TrapPhone> Loaded phones by id.
local cache = {}
---@type table<integer, string> The phone each online player last used, by server id.
local held = {}
---@type table<string, fun(src: integer, phone: TrapPhone): any> Extra snapshot sections
---contributed by the gameplay modules (hustle, turf, ...).
local parts = {}
---@type fun(src: integer, phone: TrapPhone, number: string, text: string)[] Listeners for a
---text the player typed to a number that is not another player's phone.
local messageListeners = {}

---@type integer Milliseconds a player must leave between two typed texts.
local TEXT_GAP_MS = 1000
---@type table<integer, integer> GetGameTimer() of each player's last typed text.
local lastText = {}

---A fresh phone's stored state.
---@return table data
local function blankData()
    return {
        xp = {},
        contacts = {},
        threads = {},
        settings = {
            wallpaper = CFG.DefaultWallpaper,
            ringtone = CFG.DefaultRingtone,
            volume = CFG.DefaultVolume,
        },
        stats = { sales = 0, earned = 0, drops = 0 },
        scores = {},
        met = {},
        pending = {},
    }
end

---Fill in any section an older save is missing, so readers never nil-check.
---@param data table stored phone state
---@return table data the same table, completed
local function normalise(data)
    local blank = blankData()

    for key, value in pairs(blank) do
        if data[key] == nil then data[key] = value end
    end
    for key, value in pairs(blank.settings) do
        if data.settings[key] == nil then data.settings[key] = value end
    end

    return data
end

---A burner number nobody holds yet.
---@return string number e.g. '555-0193'
local function freshNumber()
    for _ = 1, 50 do
        local number = ('%s-%04d'):format(CFG.NumberPrefix, math.random(0, 9999))
        if not store.numberTaken(number) and not phones.isReservedNumber(number) then return number end
    end

    return ('%s-%06d'):format(CFG.NumberPrefix, math.random(0, 999999))
end

---Whether a number belongs to a configured special contact (so a phone never rolls it).
---@param number string
---@return boolean reserved
function phones.isReservedNumber(number)
    for _, contact in ipairs(config.Contacts.List or {}) do
        if contact.number == number then return true end
    end

    return false
end

---Load a phone into the cache, creating it when the id is new.
---@param id string phone id
---@param owner string|nil character id to stamp on a new phone
---@return TrapPhone phone
local function load(id, owner)
    local phone = cache[id]
    if phone then return phone end

    local row = store.loadPhone(id)
    if row then
        phone = { id = row.id, number = row.number, owner = row.owner, data = normalise(row.data), dirty = false }
    else
        phone = { id = id, number = freshNumber(), owner = owner, data = blankData(), dirty = true }
        store.savePhone(phone.id, phone.number, phone.owner, phone.data)
        phone.dirty = false
        audit.log('phone_created', 'system', ('phone %s created with number %s'):format(id, phone.number), { id = id, owner = owner })
    end

    cache[id] = phone

    return phone
end

---The trap phone slot a player means: the given slot when it holds one, else the phone they
---last used if they still carry it, else the first one in their pockets.
---@param src integer player server id
---@param slot any|nil slot the item was used from
---@return table|nil stack { slot, count, metadata }
local function pickSlot(src, slot)
    local stacks = handsets.slots(src)
    if #stacks == 0 then return nil end

    if slot ~= nil then
        for i = 1, #stacks do
            if stacks[i].slot == slot then return stacks[i] end
        end
    end

    local last = held[src]
    if last then
        for i = 1, #stacks do
            if stacks[i].metadata and stacks[i].metadata.trapId == last then return stacks[i] end
        end
    end

    return stacks[1]
end

---The phone a player is carrying, loading (and on first use, creating) it. With unique phones
---the id lives in the item's metadata; a backend that can't write metadata, or the shared mode,
---falls back to one phone per character.
---@param src integer player server id
---@param slot any|nil inventory slot the phone was used from, when known
---@return TrapPhone|nil phone nil when the player has no trap phone
function phones.active(src, slot)
    local cid = playerBridge.getIdentifier(src)
    if not cid then return nil end

    local stack = pickSlot(src, slot)
    if not stack then
        held[src] = nil
        return nil
    end

    local id

    if CFG.UniqueMetadataPhones then
        local meta = stack.metadata or {}
        id = meta.trapId

        if not id and stack.slot ~= nil then
            local newId = ('tp_%s%04d'):format(os.time(), math.random(0, 9999))
            local phone = load(newId, cid)

            meta.trapId = newId
            meta.description = ('No. %s'):format(phone.number)

            if inventory.setMetadata(src, stack.slot, meta, stack.item) then
                id = newId
            else
                cache[newId] = nil
                log.debug('phones', 'inventory cannot write metadata; using a per-character phone for %s', cid)
            end
        end
    end

    id = id or ('cid_' .. cid)

    local phone = load(id, cid)

    if phone.owner ~= cid then
        phone.owner = cid
        phone.dirty = true
    end

    if phone.holder and phone.holder ~= src and held[phone.holder] == id then held[phone.holder] = nil end

    phone.holder = src
    phone.shell = handsets.shell(stack.item) -- the colour of the item in their hand, not stored
    held[src] = id

    return phone
end

---The phone a player last had out, without touching their inventory. Cheap; use it inside
---gameplay loops where phones.active already ran when the session started.
---@param src integer player server id
---@return TrapPhone|nil phone
function phones.current(src)
    local id = held[src]

    return id and cache[id] or nil
end

---A loaded phone by id (nil when it isn't loaded).
---@param id string phone id
---@return TrapPhone|nil phone
function phones.get(id)
    return cache[id]
end

---A phone by its number, loading it from storage when needed.
---@param number string burner number
---@return TrapPhone|nil phone
function phones.byNumber(number)
    for _, phone in pairs(cache) do
        if phone.number == number then return phone end
    end

    local id = store.phoneIdByNumber(number)

    return id and load(id) or nil
end

---A phone by the digits of its number alone ('5550193' for '555-0193'), which is how other
---phone systems and hurried thumbs write it.
---@param digits string
---@return TrapPhone|nil phone
function phones.byDigits(digits)
    if type(digits) ~= 'string' or digits == '' then return nil end

    for _, phone in pairs(cache) do
        if phone.number:gsub('%D', '') == digits then return phone end
    end

    local prefix = CFG.NumberPrefix
    if digits:sub(1, #prefix) ~= prefix or #digits <= #prefix then return nil end

    local id = store.phoneIdByNumber(('%s-%s'):format(prefix, digits:sub(#prefix + 1)))

    return id and load(id) or nil
end

---The online player carrying a phone, if any.
---@param phone TrapPhone
---@return integer|nil src
function phones.holderOf(phone)
    local src = phone.holder
    if src and held[src] == phone.id and GetPlayerName(src) then return src end

    return nil
end

---Mark a phone as changed so the next flush saves it.
---@param phone TrapPhone
function phones.touch(phone)
    phone.dirty = true
end

---Send a partial state update to whoever is carrying the phone (no-op when nobody is).
---@param phone TrapPhone
---@param patch table top-level PhoneState keys to replace
function phones.push(phone, patch)
    local src = phones.holderOf(phone)
    if src then TriggerClientEvent('sd-trapphone:client:state', src, patch) end
end

---Register an extra snapshot section. The function's result is sent to the handset under
---`name` whenever the phone opens or the section is refreshed.
---@param name string PhoneState key (e.g. 'hustle', 'turf')
---@param fn fun(src: integer, phone: TrapPhone): any
function phones.addPart(name, fn)
    parts[name] = fn
end

---Recompute one registered section and push it to the handset.
---@param phone TrapPhone
---@param name string section name passed to phones.addPart
function phones.refresh(phone, name)
    local src = phones.holderOf(phone)
    local fn = parts[name]
    if not src or not fn then return end

    local ok, value = pcall(fn, src, phone)
    if not ok then
        log.error('phones', 'snapshot part %s failed: %s', name, value)
        return
    end

    TriggerClientEvent('sd-trapphone:client:state', src, { [name] = value })
end

---Threads as the handset lists them: an array, newest conversation first.
---@param phone TrapPhone
---@return table[] threads
local function threadList(phone)
    local list = {}

    for number, thread in pairs(phone.data.threads) do
        list[#list + 1] = {
            number = number,
            name = thread.name,
            kind = thread.kind,
            unread = thread.unread,
            ts = thread.ts,
            msgs = thread.msgs,
        }
    end

    table.sort(list, function(a, b) return a.ts > b.ts end)

    return list
end

---Everything the handset needs to draw itself.
---@param src integer player server id
---@param phone TrapPhone
---@return table state PhoneState (docs/design.md)
function phones.snapshot(src, phone)
    local state = {
        phone = { id = phone.id, number = phone.number, shell = phone.shell },
        settings = phone.data.settings,
        threads = threadList(phone),
        contacts = phone.data.contacts,
        scores = phone.data.scores,
        stats = phone.data.stats,
        now = os.time(),
    }

    for name, fn in pairs(parts) do
        local ok, value = pcall(fn, src, phone)
        if ok then
            state[name] = value
        else
            log.error('phones', 'snapshot part %s failed: %s', name, value)
        end
    end

    return state
end

---Drop the oldest customer conversations once a phone holds too many. Contacts and system
---threads are never dropped.
---@param phone TrapPhone
local function trimThreads(phone)
    local threads = phone.data.threads
    local customers = {}

    for number, thread in pairs(threads) do
        if thread.kind == 'customer' then customers[#customers + 1] = { number = number, ts = thread.ts } end
    end

    local over = #customers - CFG.MaxThreads
    if over <= 0 then return end

    table.sort(customers, function(a, b) return a.ts < b.ts end)

    for i = 1, over do
        threads[customers[i].number] = nil
    end
end

---Add a message to a conversation on a phone and deliver it to the handset.
---@param phone TrapPhone
---@param number string who the conversation is with
---@param msg { from: 'me'|'them', text: string, offer?: table }
---@param opts? { name?: string, kind?: string, silent?: boolean } name/kind are used when the
---conversation is new; silent skips the ring and the unread count
---@return TrapMessage message the stored message
function phones.message(phone, number, msg, opts)
    opts = opts or {}

    local threads = phone.data.threads
    local thread = threads[number]

    if not thread then
        local known = phones.getContact(phone, number)

        thread = {
            name = opts.name or (known and known.name) or number,
            kind = opts.kind or (known and 'contact') or 'customer',
            unread = 0,
            ts = os.time(), -- stamped now so the trim below never sees the new thread as the oldest
            seq = 0,
            msgs = {},
        }
        threads[number] = thread
        trimThreads(phone)
    elseif opts.name then
        thread.name = opts.name
    end

    thread.seq += 1
    thread.ts = os.time()

    local stored = { id = thread.seq, from = msg.from, text = msg.text, ts = thread.ts, offer = msg.offer }

    thread.msgs[#thread.msgs + 1] = stored
    while #thread.msgs > CFG.MaxMessagesPerThread do
        table.remove(thread.msgs, 1)
    end

    if msg.from == 'them' and not opts.silent then thread.unread += 1 end

    phone.dirty = true

    local src = phones.holderOf(phone)
    if src then
        TriggerClientEvent('sd-trapphone:client:message', src, {
            number = number,
            name = thread.name,
            kind = thread.kind,
            unread = thread.unread,
            msg = stored,
            silent = opts.silent or msg.from == 'me',
        })
    end

    return stored
end

---Change the offer riding on a message (accepted, countered, done, expired...) and tell the
---handset.
---@param phone TrapPhone
---@param number string conversation the offer is in
---@param ticketId string|integer the offer's ticket id
---@param patch table fields to merge into the offer (state, price, ...)
---@return boolean found
function phones.updateOffer(phone, number, ticketId, patch)
    local thread = phone.data.threads[number]
    if not thread then return false end

    for i = #thread.msgs, 1, -1 do
        local offer = thread.msgs[i].offer

        if offer and offer.ticketId == ticketId then
            for key, value in pairs(patch) do
                offer[key] = value
            end

            phone.dirty = true

            local src = phones.holderOf(phone)
            if src then
                TriggerClientEvent('sd-trapphone:client:offer', src, { number = number, ticketId = ticketId, offer = offer })
            end

            return true
        end
    end

    return false
end

---A saved contact by number.
---@param phone TrapPhone
---@param number string
---@return table|nil contact { number, name, type, key? }
---@return integer|nil index position in the contact list
function phones.getContact(phone, number)
    local contacts = phone.data.contacts

    for i = 1, #contacts do
        if contacts[i].number == number then return contacts[i], i end
    end

    return nil
end

---Whether a phone holds at least one contact of a type (e.g. 'launderer').
---@param phone TrapPhone
---@param contactType string a key of config.Contacts.Types
---@return boolean has
function phones.hasContactType(phone, contactType)
    local contacts = phone.data.contacts

    for i = 1, #contacts do
        if contacts[i].type == contactType then return true end
    end

    return false
end

---Save (or update) a contact on a phone and refresh the handset's list.
---@param phone TrapPhone
---@param contact { number: string, name: string, type?: string, key?: string, gang?: string }
---@return table contact the stored contact
function phones.addContact(phone, contact)
    local existing = phones.getContact(phone, contact.number)

    if existing then
        existing.name = contact.name or existing.name
        existing.type = contact.type or existing.type
        existing.key = contact.key or existing.key
        existing.gang = contact.gang or existing.gang
    else
        existing = {
            number = contact.number,
            name = contact.name or contact.number,
            type = contact.type or 'custom',
            key = contact.key,
            gang = contact.gang,
        }
        phone.data.contacts[#phone.data.contacts + 1] = existing
    end

    local thread = phone.data.threads[contact.number]
    if thread then
        thread.name = existing.name
        if thread.kind == 'customer' then thread.kind = 'contact' end
    end

    phone.dirty = true
    phones.push(phone, { contacts = phone.data.contacts, threads = threadList(phone) })

    return existing
end

---Remove a contact from a phone.
---@param phone TrapPhone
---@param number string
---@return boolean removed
function phones.removeContact(phone, number)
    local _, index = phones.getContact(phone, number)
    if not index then return false end

    table.remove(phone.data.contacts, index)
    phone.dirty = true
    phones.push(phone, { contacts = phone.data.contacts })

    return true
end

---Listen for texts a player types to a number that isn't another player's phone, so the
---module that owns that kind of number can answer.
---@param fn fun(src: integer, phone: TrapPhone, number: string, text: string)
function phones.onMessage(fn)
    messageListeners[#messageListeners + 1] = fn
end

---Save one phone if it changed.
---@param phone TrapPhone
---@param now? boolean true fires the query without waiting for it (resource stop: a wait there
---would never resume, and only the first phone would be saved)
local function flush(phone, now)
    if not phone.dirty then return end

    phone.dirty = false

    local ok, err = pcall(now and store.savePhoneNow or store.savePhone, phone.id, phone.number, phone.owner, phone.data)
    if not ok then
        phone.dirty = true
        log.error('phones', 'saving %s failed: %s', phone.id, err)
    end
end

---Save every changed phone.
---@param now? boolean true when the resource is stopping (see flush)
function phones.flushAll(now)
    for _, phone in pairs(cache) do
        flush(phone, now)
    end
end

---Validate a slot argument a client sent: a positive integer, or nothing.
---@param slot any
---@return integer|nil slot
local function cleanSlot(slot)
    if type(slot) == 'number' and slot == math.floor(slot) and slot > 0 and slot < 1000 then return slot end

    return nil
end

---Trim a typed string to a safe length, or nil when it isn't usable text.
---@param value any
---@param max integer
---@return string|nil text
local function cleanText(value, max)
    if type(value) ~= 'string' then return nil end

    value = value:gsub('[%c]', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if value == '' then return nil end

    return value:sub(1, max)
end

phones.cleanText = cleanText

---@type table<string, string> Which config list validates each setting the handset can change.
local SETTING_LISTS = { wallpaper = 'Wallpapers', ringtone = 'Ringtones' }

-- The handset opening: resolve the phone the player means and hand back its full state.
lib.callback.register('sd-trapphone:server:open', function(src, slot)
    local phone = phones.active(src, cleanSlot(slot))
    if not phone then return nil end

    return phones.snapshot(src, phone)
end)

lib.callback.register('sd-trapphone:server:setSetting', function(src, key, value)
    local phone = phones.current(src)
    if not phone then return false end

    if key == 'volume' then
        if type(value) ~= 'number' then return false end
        value = math.max(0.0, math.min(1.0, value))
    else
        local list = SETTING_LISTS[key] and CFG[SETTING_LISTS[key]]
        if not list or not lib.table.contains(list, value) then return false end
    end

    phone.data.settings[key] = value
    phone.dirty = true

    return true
end)

lib.callback.register('sd-trapphone:server:readThread', function(src, number)
    local phone = phones.current(src)
    local thread = phone and type(number) == 'string' and phone.data.threads[number]
    if not thread then return false end

    if thread.unread ~= 0 then
        thread.unread = 0
        phone.dirty = true
    end

    return true
end)

lib.callback.register('sd-trapphone:server:deleteThread', function(src, number)
    local phone = phones.current(src)
    if not phone or type(number) ~= 'string' or not phone.data.threads[number] then return false end

    phone.data.threads[number] = nil
    phone.dirty = true

    return true
end)

-- Saving a number by hand. A special contact's number only works once they have been met
-- (their module adds them); typed in cold it is just a dead number saved as 'custom'.
lib.callback.register('sd-trapphone:server:addContact', function(src, number, name)
    local phone = phones.current(src)
    number = cleanText(number, 16)
    name = cleanText(name, 24)
    if not phone or not number or not name then return false end
    if not number:match('^[%d%-]+$') then return false end
    if #phone.data.contacts >= 60 then return false end

    local existing = phones.getContact(phone, number)
    local contactType = existing and existing.type or 'custom'
    local key, gang

    if not existing then
        -- A special contact this phone has already met comes back as themselves, so deleting
        -- one by mistake never locks their services away for good.
        for _, special in ipairs(config.Contacts.List or {}) do
            if special.number == number and phone.data.met[special.key] then
                contactType, key, gang = special.type, special.key, special.gang
            end
        end

        if not key and number ~= phone.number and phones.byNumber(number) then contactType = 'player' end
    end

    phones.addContact(phone, { number = number, name = name, type = contactType, key = key, gang = gang })

    return true
end)

lib.callback.register('sd-trapphone:server:deleteContact', function(src, number)
    local phone = phones.current(src)
    if not phone or type(number) ~= 'string' then return false end

    return phones.removeContact(phone, number)
end)

-- A typed text. To another trap phone it is delivered there; to anything else it is stored and
-- offered to the listeners (special contacts answer through theirs).
lib.callback.register('sd-trapphone:server:sendMessage', function(src, number, text)
    local phone = phones.current(src)
    number = cleanText(number, 16)
    text = cleanText(text, 160)
    if not phone or not number or not text then return false end

    local now = GetGameTimer()
    if now - (lastText[src] or -TEXT_GAP_MS) < TEXT_GAP_MS then return false end
    lastText[src] = now

    phones.message(phone, number, { from = 'me', text = text })

    local other = number ~= phone.number and (phones.byNumber(number) or phones.byDigits((number:gsub('%D', '')))) or nil
    if other == phone then other = nil end
    if other then
        phones.message(other, phone.number, { from = 'them', text = text }, { kind = 'player' })
        return true
    end

    for i = 1, #messageListeners do
        local ok, err = pcall(messageListeners[i], src, phone, number, text)
        if not ok then log.error('phones', 'message listener failed: %s', err) end
    end

    return true
end)

lib.callback.register('sd-trapphone:server:submitScore', function(src, game, score)
    local phone = phones.current(src)
    if not phone or game ~= 'worm' or type(score) ~= 'number' or score ~= score then return false end

    score = math.floor(math.max(0, math.min(999999, score)))

    if score > (phone.data.scores[game] or 0) then
        phone.data.scores[game] = score
        phone.dirty = true
    end

    return phone.data.scores[game]
end)

AddEventHandler('playerDropped', function()
    local src = source
    local id = held[src]
    held[src] = nil
    lastText[src] = nil

    local phone = id and cache[id]
    if not phone then return end

    if phone.holder == src then phone.holder = nil end
    flush(phone)
end)

CreateThread(function()
    while true do
        Wait(60000)
        phones.flushAll()
    end
end)

return phones
