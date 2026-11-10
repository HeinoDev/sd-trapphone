---@type table Detected framework descriptor (bridge.shared.framework).
local framework = require 'bridge.shared.framework'

---@type table Tagged debug logger for this file (bridge.shared.debug).
local dprint = require('bridge.shared.debug').tag('bridge:vehicles')

---@type table Vehicle registry bridge — plate-ownership lookups.
local vehicles = {}

---Looks a plate up in the framework's vehicle registry and returns the owning
---character's identifier (citizenid on qb/qbox, identifier on ESX), or nil
---when the plate isn't registered to anyone. Compare against
---`bridge.server.player.getIdentifier(src)` to answer "is this the caller's
---own car?". On Qbox the qbx_vehicles exports are preferred; everywhere else
---this falls back to the framework's own DB table (player_vehicles /
---owned_vehicles) via oxmysql — plates are TRIM-matched because frameworks
---disagree on padding. Yields (DB await), so call it from a callback/thread.
---@param plate string Plate as read off the entity (GetVehicleNumberPlateText).
---@return string|nil ownerIdentifier
function vehicles.ownerIdentifier(plate)
    if type(plate) ~= 'string' then return nil end
    local trimmed = plate:match('^%s*(.-)%s*$')
    if trimmed == '' then return nil end

    if framework.isQbx and GetResourceState('qbx_vehicles') == 'started' then
        local ok, owner = pcall(function()
            local vid = exports.qbx_vehicles:GetVehicleIdByPlate(plate)
            local row = vid and exports.qbx_vehicles:GetPlayerVehicle(vid)
            return row and row.citizenid or nil
        end)
        if ok then
            dprint('ownerIdentifier: plate=%s via qbx_vehicles → %s', trimmed, tostring(owner))
            return owner
        end
        dprint('ownerIdentifier: qbx_vehicles lookup failed for plate=%s — falling back to DB', trimmed)
    end

    local query
    if framework.name == 'qb' then
        query = 'SELECT citizenid FROM player_vehicles WHERE TRIM(plate) = ? LIMIT 1'
    elseif framework.name == 'esx' then
        query = 'SELECT owner FROM owned_vehicles WHERE TRIM(plate) = ? LIMIT 1'
    else
        dprint('ownerIdentifier: unsupported framework %s — returning nil', tostring(framework.name))
        return nil
    end

    local ok, owner = pcall(MySQL.scalar.await, query, { trimmed })
    if not ok then
        dprint('ownerIdentifier: DB lookup failed for plate=%s — returning nil', trimmed)
        return nil
    end
    dprint('ownerIdentifier: plate=%s via DB → %s', trimmed, tostring(owner))
    return owner
end

return vehicles
