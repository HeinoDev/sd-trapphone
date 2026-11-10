---@type table Items module; the table returned at end of file. Shared (client + server)
---item-label lookups routed through the inventory bridge, which resolves them against
---whatever inventory/framework is running and caches per name on its side.
local items = {}

---@type table Side-appropriate inventory bridge (bridge.server.inventory or
---bridge.client.inventory) — both expose label(name).
local inventory = IsDuplicityVersion() and require 'bridge.server.inventory' or require 'bridge.client.inventory'

---Display label for an item, falling back to the raw item name.
---@param name string item name
---@return string label
function items.label(name)
    if not name then return '' end
    return inventory.label(name) or name
end

---An item's readable label followed by its id, e.g. "Gold Bar (goldbar)" - the audit-line format.
---@param name string item name
---@return string display label + id
function items.display(name)
    return ('%s (%s)'):format(items.label(name), name)
end

return items
