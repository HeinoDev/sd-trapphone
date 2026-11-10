---@type table Detected inventory resource descriptor (bridge.shared.inventory_id).
local inventoryId = require 'bridge.shared.inventory_id'

---@type table Tagged debug logger for this file (bridge.shared.debug).
local dprint = require('bridge.shared.debug').tag('bridge:stash')

---@type string ox_inventory resource name.
local OX = 'ox_inventory'

---@type string|nil Active inventory resource name for the current server.
local active = inventoryId.name

---Named/registered stashes addressed by string id — the mechanic behind the
---tablet's travelling USB storage. Only ox_inventory exposes the full set
---(register + force-open + read + per-slot metadata writes on a string id),
---so `supported` is the gate consumers check before leaning on any of it;
---every function below is a safe no-op when it's false. The tablet module
---falls back to reading USBs from the player's own pockets on other backends.
---@type table Stash bridge module.
local stash = { supported = active == OX }

dprint('module load — backend=%s supported=%s', tostring(active), tostring(stash.supported))

---(Re-)registers a stash id so it can be opened/read. Registrations are
---in-memory (repeat-safe); the stash CONTENTS persist under the id.
---@param id string Stash id.
---@param label string Display label.
---@param slots number Slot count.
---@param maxWeight number Weight cap.
---@param owner? string|boolean false/nil for an unowned stash that anyone with the id can open.
---@return boolean registered
function stash.register(id, label, slots, maxWeight, owner)
    if not stash.supported then
        dprint('register: unsupported backend %s — skipped id=%s', tostring(active), tostring(id))
        return false
    end
    exports[OX]:RegisterStash(id, label, slots, maxWeight, owner or false)
    return true
end

---Force-opens a registered stash for a player, replacing whatever inventory
---view they have up (the reason this runs server-side).
---@param source number
---@param id string Stash id.
---@return boolean opened
function stash.open(source, id)
    if not stash.supported then
        dprint('open: unsupported backend %s — skipped id=%s', tostring(active), tostring(id))
        return false
    end
    exports[OX]:forceOpenInventory(source, 'stash', id)
    return true
end

---Every item currently inside the stash, in the backend's own slot shape
---(`{ name, slot, count, metadata }` rows on ox). Empty when unsupported.
---@param id string Stash id.
---@return table[] items
function stash.getItems(id)
    if not stash.supported then return {} end
    return exports[OX]:GetInventoryItems(id) or {}
end

---Replaces the metadata table on one slot of the stash.
---@param id string Stash id.
---@param slot any Slot id.
---@param metadata table Full replacement metadata table.
---@return boolean written
function stash.setMetadata(id, slot, metadata)
    if not stash.supported then return false end
    exports[OX]:SetMetadata(id, slot, metadata)
    return true
end

---Removes `count` of `item` from a specific slot of the stash.
---@param id string Stash id.
---@param item string
---@param count number
---@param slot? any
---@return boolean removed
function stash.removeFromSlot(id, item, count, slot)
    if not stash.supported then return false end
    return exports[OX]:RemoveItem(id, item, count, nil, slot) and true or false
end

return stash
