---@type table sd-trapphone config root (configs/config.lua).
local config = require 'configs.config'

---@type table Side-appropriate inventory bridge (bridge.server.inventory or bridge.client.inventory).
local inventory = IsDuplicityVersion() and require 'bridge.server.inventory' or require 'bridge.client.inventory'

---@type table Handset config (config.Phone).
local CFG = config.Phone

---@type table Handsets module; the table returned at end of file. The trap phone comes in
---several colours, each its own item with its own model. Everything that asks "is this a trap
---phone" or "does this player carry one" goes through here, so no file names an item itself.
local handsets = {}

---@type string[] Every handset item name, in a stable order.
local names = {}

for item in pairs(CFG.Items) do
    names[#names + 1] = item
end

table.sort(names)

---Every handset item name.
---@return string[] items
function handsets.items()
    return names
end

---The colour a handset item is (nil when the item is not a trap phone).
---@param item string|nil item name
---@return string|nil shell a faceplate id the page and the prop both know
function handsets.shell(item)
    return item and CFG.Items[item] or nil
end

---The streamed model a colour uses in the hand.
---@param shell string|nil faceplate id
---@return integer model hash
function handsets.model(shell)
    return joaat(CFG.Prop.Prefix .. (shell or CFG.Items[CFG.Item]))
end

if IsDuplicityVersion() then
    ---How many trap phones, of any colour, a player carries.
    ---@param src integer player server id
    ---@return integer count
    function handsets.count(src)
        local total = 0

        for i = 1, #names do
            total += inventory.count(src, names[i]) or 0
        end

        return total
    end

    ---Every trap phone stack a player carries, each tagged with its item name.
    ---@param src integer player server id
    ---@return { slot: any, count: integer, metadata: table, item: string }[] stacks
    function handsets.slots(src)
        local all = {}

        for i = 1, #names do
            local stacks = inventory.getSlots(src, names[i])

            for j = 1, #stacks do
                stacks[j].item = names[i]
                all[#all + 1] = stacks[j]
            end
        end

        return all
    end
else
    ---Whether the local player carries a trap phone of any colour.
    ---@return boolean carried
    function handsets.carried()
        for i = 1, #names do
            if inventory.has(names[i]) then return true end
        end

        return false
    end
end

return handsets
