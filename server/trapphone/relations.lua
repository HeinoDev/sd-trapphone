---@type table Console log helper (shared.log).
local log = require 'shared.log'
---@type table Server-side persistence module (server.trapphone.store).
local store = require 'server.trapphone.store'

---@type table Relations module; the table returned at end of file. Small signed numbers an
---owner holds with something: a customer's look ('ped'), a crew ('gang'), or a protection
---expiry ('protect'). The owner is a character id, or a job name for shared job standing.
local relations = {}

---@type table<string, table<string, table<string, integer>>> Loaded values: [owner][kind][key].
local cache = {}

---An owner's values of one kind, loaded on first use.
---@param owner string character id or job name
---@param kind string relation kind
---@return table<string, integer> values
local function bucket(owner, kind)
    local byOwner = cache[owner]
    if not byOwner then
        byOwner = {}
        cache[owner] = byOwner
    end

    local values = byOwner[kind]
    if not values then
        local ok, loaded = pcall(store.loadRelations, owner, kind)
        if not ok then log.error('relations', 'loading %s/%s failed: %s', owner, kind, loaded) end

        values = ok and loaded or {}
        byOwner[kind] = values
    end

    return values
end

---One relation value.
---@param owner string character id or job name
---@param kind string relation kind
---@param key string what the relation is with
---@param default? integer returned when nothing is stored (0 when omitted)
---@return integer value
function relations.get(owner, kind, key, default)
    return bucket(owner, kind)[key] or default or 0
end

---Every value of one kind an owner holds. Treat as read-only.
---@param owner string character id or job name
---@param kind string relation kind
---@return table<string, integer> values
function relations.all(owner, kind)
    return bucket(owner, kind)
end

---Set a relation value and persist it.
---@param owner string character id or job name
---@param kind string relation kind
---@param key string what the relation is with
---@param value integer
---@return integer value
function relations.set(owner, kind, key, value)
    value = math.floor(value)
    bucket(owner, kind)[key] = value

    local ok, err = pcall(store.saveRelation, owner, kind, key, value)
    if not ok then log.error('relations', 'saving %s/%s/%s failed: %s', owner, kind, key, err) end

    return value
end

---Move a relation value by a delta, clamped to a range, and persist it.
---@param owner string character id or job name
---@param kind string relation kind
---@param key string what the relation is with
---@param delta integer
---@param min? integer lower clamp (-100 when omitted)
---@param max? integer upper clamp (100 when omitted)
---@param default? integer starting value when nothing is stored
---@return integer value the value after the change
function relations.add(owner, kind, key, delta, min, max, default)
    local value = relations.get(owner, kind, key, default) + delta

    value = math.max(min or -100, math.min(max or 100, value))

    return relations.set(owner, kind, key, value)
end

---Forget an owner's loaded values (they are reloaded on next use). Call when a character logs out.
---@param owner string character id or job name
function relations.unload(owner)
    cache[owner] = nil
end

return relations
