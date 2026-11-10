---@type table sd-trapphone config root (configs/config.lua).
local config = require 'configs.config'
---@type table Handset items and colours (shared.handsets).
local handsets = require 'shared.handsets'
---@type table Audit-log helper (server.trapphone.audit).
local audit = require 'server.trapphone.audit'
---@type table Server-side persistence module (server.trapphone.store).
local store = require 'server.trapphone.store'
---@type table Live phones (server.trapphone.phones).
local phones = require 'server.trapphone.phones'
---@type table XP and levels (server.trapphone.progress).
local progress = require 'server.trapphone.progress'
---@type table Signed standing values (server.trapphone.relations).
local relations = require 'server.trapphone.relations'
---@type table Turf and gang standing (server.trapphone.turf).
local turf = require 'server.trapphone.turf'
---@type table Player bridge (bridge.server.player): identifier lookups.
local playerBridge = require 'bridge.server.player'
---@type table Inventory bridge (bridge.server.inventory).
local inventory = require 'bridge.server.inventory'

-- The public server exports (docs/design.md "Exports"). Other resources are trusted callers,
-- but every argument is still checked so a typo returns false instead of corrupting a phone.
-- The three callbacks at the bottom back client exports and trust nothing.

---@type integer Seconds between two export-driven messages or relationship changes from one client.
local CLIENT_PACE = 2
---@type integer Seconds between two relationship gains a client may ask for on the same ped.
local GAIN_PACE = 60

---@type table<integer, integer> os.time() of each player's last client-export request.
local pace = {}
---@type table<integer, integer> os.time() of each player's last client-asked relationship gain.
local lastGain = {}

---A phone by id or number, loading it from storage when it is not in memory.
---@param ref any phone id ('tp_...', 'cid_...') or burner number
---@return table|nil phone TrapPhone
local function resolve(ref)
    if type(ref) ~= 'string' or ref == '' or #ref > 48 then return nil end

    local phone = phones.get(ref) or phones.byNumber(ref)
    if phone then return phone end

    local ok, row = pcall(store.loadPhone, ref)

    return ok and row and phones.byNumber(row.number) or nil
end

---The phone a player carries.
---@param src any player server id
---@return table|nil phone TrapPhone
local function phoneOf(src)
    if type(src) ~= 'number' or not GetPlayerName(src) then return nil end

    return phones.current(src) or phones.active(src)
end

---A whole, positive amount, or nil.
---@param amount any
---@return integer|nil amount
local function positive(amount)
    amount = tonumber(amount)
    if not amount or amount <= 0 then return nil end

    return math.floor(amount)
end

---Text a phone. `from` is the number (or name) the message is shown under; `to` is the
---receiving phone's number or id.
---@param from string sender number or name
---@param to string receiving phone's number or id
---@param text string
---@return boolean sent
exports('sendMessageToPhone', function(from, to, text)
    local phone = resolve(to)

    from = phones.cleanText(from, 24)
    text = phones.cleanText(text, 160)
    if not phone or not from or not text then return false end

    local sender = phones.byNumber(from)

    phones.message(phone, from, { from = 'them', text = text }, { kind = sender and 'player' or 'system' })

    return true
end)

---Save a contact on a phone.
---@param phoneId string phone id or number
---@param contact { number: string, name: string, type?: string }
---@return boolean added
exports('addContactToPhone', function(phoneId, contact)
    local phone = resolve(phoneId)
    if not phone or type(contact) ~= 'table' then return false end

    local number = phones.cleanText(contact.number, 16)
    local name = phones.cleanText(contact.name, 24)
    if not number or not name then return false end

    local contactType = config.Contacts.Types[contact.type] and contact.type or 'custom'

    phones.addContact(phone, { number = number, name = name, type = contactType })

    return true
end)

---One saved contact on a phone.
---@param phoneId string phone id or number
---@param number string
---@return table|nil contact { number, name, type, key?, gang? }
exports('getContact', function(phoneId, number)
    local phone = resolve(phoneId)
    if not phone or type(number) ~= 'string' then return nil end

    local contact = phones.getContact(phone, number)

    return contact and lib.table.deepclone(contact) or nil
end)

---Every saved contact on a phone.
---@param phoneId string phone id or number
---@return table[] contacts
exports('getAllContacts', function(phoneId)
    local phone = resolve(phoneId)

    return phone and lib.table.deepclone(phone.data.contacts) or {}
end)

---Whether a player is carrying the phone with this id right now.
---@param src integer player server id
---@param phoneId string phone id
---@return boolean carries
exports('verifyPhoneOwnership', function(src, phoneId)
    if type(src) ~= 'number' or type(phoneId) ~= 'string' or not GetPlayerName(src) then return false end

    local cid = playerBridge.getIdentifier(src)
    if not cid then return false end

    local stacks = handsets.slots(src)

    for i = 1, #stacks do
        local id = stacks[i].metadata and stacks[i].metadata.trapId

        -- A phone with no id of its own is the character's shared one.
        if id == phoneId or (not id and phoneId == 'cid_' .. cid) then return true end
    end

    return false
end)

---Add XP in a product family to the phone a player carries.
---@param src integer player server id
---@param family string a key of config.Drugs.Families
---@param amount integer
---@return integer|false level the level afterwards, false when it could not be done
exports('addXP', function(src, family, amount)
    local phone = phoneOf(src)
    amount = positive(amount)
    if not phone or not amount or not config.Drugs.Families[family] then return false end

    return progress.add(phone, family, amount)
end)

---Take XP in a product family from the phone a player carries.
---@param src integer player server id
---@param family string a key of config.Drugs.Families
---@param amount integer
---@return integer|false level the level afterwards, false when it could not be done
exports('removeXP', function(src, family, amount)
    local phone = phoneOf(src)
    amount = positive(amount)
    if not phone or not amount or not config.Drugs.Families[family] then return false end

    return progress.remove(phone, family, amount)
end)

---Move a player's standing with a crew (their job's, when the job shares one).
---@param src any player server id
---@param gang any key of config.Gangs.List
---@param amount any
---@param sign integer 1 or -1
---@return integer|false rep the standing afterwards
local function movePlayerRep(src, gang, amount, sign)
    amount = positive(amount)
    if type(src) ~= 'number' or not GetPlayerName(src) or not amount or not config.Gangs.List[gang] then return false end

    local owner = turf.ownerOf(src)
    if not owner then return false end

    local rep = turf.addRep(owner, gang, sign * amount)
    local phone = phones.current(src)

    if phone then phones.refresh(phone, 'turf') end

    return rep
end

---Move a shared-rep job's standing with a crew.
---@param job any job name
---@param gang any key of config.Gangs.List
---@param amount any
---@param sign integer 1 or -1
---@return integer|false rep the standing afterwards
local function moveJobRep(job, gang, amount, sign)
    amount = positive(amount)
    if type(job) ~= 'string' or job == '' or not amount or not config.Gangs.List[gang] then return false end
    if not lib.table.contains(config.Gangs.SharedJobRep or {}, job) then return false end

    return turf.addRep(job, gang, sign * amount)
end

exports('increaseGangRep', function(src, gang, amount) return movePlayerRep(src, gang, amount, 1) end)
exports('decreaseGangRep', function(src, gang, amount) return movePlayerRep(src, gang, amount, -1) end)
exports('increaseJobGangRep', function(job, gang, amount) return moveJobRep(job, gang, amount, 1) end)
exports('decreaseJobGangRep', function(job, gang, amount) return moveJobRep(job, gang, amount, -1) end)

---Whether a client-export request arrives too soon after the player's last one.
---@param src integer player server id
---@return boolean tooSoon
local function tooSoon(src)
    local now = os.time()

    if now - (pace[src] or 0) < CLIENT_PACE then return true end

    pace[src] = now

    return false
end

-- Backs the client export sendMessage: a text another client-side resource puts on the
-- player's own phone. It can only ever reach the phone of the player who sent it.
lib.callback.register('sd-trapphone:server:exportMessage', function(src, text, sender)
    if tooSoon(src) then return false end

    local phone = phones.current(src) or phones.active(src)

    text = phones.cleanText(text, 160)
    sender = phones.cleanText(sender, 24) or locale('contacts.unknown_sender')
    if not phone or not text then return false end

    -- Never under a real number: a client must not be able to fake a text from a contact or
    -- from another player's phone.
    if phones.isReservedNumber(sender) or phones.getContact(phone, sender) or phones.byNumber(sender) then return false end

    phones.message(phone, sender, { from = 'them', text = text }, { kind = 'system' })

    return true
end)

-- Backs the client export getPedRelationship.
lib.callback.register('sd-trapphone:server:pedRelationship', function(src, pedKey)
    local cid = playerBridge.getIdentifier(src)
    if not cid or type(pedKey) ~= 'string' or pedKey == '' or #pedKey > 64 then return 0 end

    return relations.get(cid, 'ped', pedKey)
end)

-- Backs the client export updatePedRelationship. A relationship is worth money (better
-- offers, easier haggles), so a client may sour one freely but can only sweeten one by a
-- sale's worth, and only once in a while.
lib.callback.register('sd-trapphone:server:movePedRelationship', function(src, pedKey, amount)
    local cid = playerBridge.getIdentifier(src)

    if not cid or type(pedKey) ~= 'string' or pedKey == '' or #pedKey > 64 or type(amount) ~= 'number' or amount ~= amount then
        return false
    end
    if tooSoon(src) then return false end

    local cap = config.Selling.Relationship.PerSale
    local delta = math.floor(math.max(-100, math.min(cap, amount)))

    if delta > 0 then
        local now = os.time()

        if now - (lastGain[src] or 0) < GAIN_PACE then
            audit.log('suspect', src, 'asked for ped relationship gains faster than sales happen', { pedKey = pedKey, amount = amount })
            return false
        end

        lastGain[src] = now
    end

    if delta == 0 then return relations.get(cid, 'ped', pedKey) end

    return relations.add(cid, 'ped', pedKey, delta)
end)

AddEventHandler('playerDropped', function()
    local src = source

    pace[src] = nil
    lastGain[src] = nil
end)
