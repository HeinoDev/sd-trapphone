---@type table sd-trapphone config root (configs/config.lua).
local config = require 'configs.config'

---@class TrapZone
---@field id string
---@field label string
---@field wealth integer 0..5
---@field gang string|nil key of config.Gangs.List

---@type table Zones module; the table returned at end of file. Pure (no natives), so both
---sides and the offline tests can resolve a position the same way.
local zones = {}

---@type table Turf map config (config.Zones).
local CFG = config.Zones

---The turf a position falls in: the smallest configured circle containing it, or the default
---"open ground" zone when it is in none.
---@param x number world x
---@param y number world y
---@return TrapZone zone
function zones.at(x, y)
    local best, bestRadius

    for i = 1, #CFG.Areas do
        local area = CFG.Areas[i]
        local dx, dy = x - area.center.x, y - area.center.y

        if dx * dx + dy * dy <= area.radius * area.radius and (not bestRadius or area.radius < bestRadius) then
            best, bestRadius = area, area.radius
        end
    end

    return best or CFG.Default
end

---A zone by id (the default zone for its own id, nil for an unknown one).
---@param id string zone id
---@return TrapZone|nil zone
function zones.get(id)
    if id == CFG.Default.id then return CFG.Default end

    for i = 1, #CFG.Areas do
        if CFG.Areas[i].id == id then return CFG.Areas[i] end
    end

    return nil
end

---How a wealth tier reads on the phone.
---@param wealth integer 0..5
---@return string label
function zones.wealthLabel(wealth)
    return CFG.WealthLabels[wealth] or tostring(wealth)
end

return zones
