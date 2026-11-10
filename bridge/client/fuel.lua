---@type table Fuel bridge module; holds the detected fuel system name and gauge read/write helpers.
local fuel = { system = nil }

---@type { name: string, kind: string }[] Supported fuel resources probed in priority order; kind is 'state_bag' or 'export'.
local SUPPORTED = {
    { name = 'ox_fuel',          kind = 'state_bag' },
    { name = 'LegacyFuel',       kind = 'export'    },
    { name = 'cdn-fuel',         kind = 'export'    },
    { name = 'ps-fuel',          kind = 'export'    },
    { name = 'okokFuel',         kind = 'export'    },
    { name = 'stg-vanaheimfuel', kind = 'export'    },
}

---@type table Tagged debug logger for the fuel bridge; gated by
---config.DebugPrints / DebugCategories under 'bridge:fuel' (bridge.shared.debug).
local dprint = require('bridge.shared.debug').tag('bridge:fuel')

---Walks the SUPPORTED list, logs each probe, returns the first started match.
---@return string|nil name
---@return string|nil kind
local function detect()
    dprint('detecting installed fuel resource...')
    for i = 1, #SUPPORTED do
        local row = SUPPORTED[i]
        local state = GetResourceState(row.name)
        dprint('  probe: %-12s state=%s', row.name, tostring(state))
        if state == 'started' then
            return row.name, row.kind
        end
    end
    return nil, nil
end

---@type string|nil Detected fuel resource name, or nil if none is started.
---@type string|nil Detected backend kind ('state_bag' or 'export'), or nil if none is started.
local activeName, activeKind = detect()
fuel.system = activeName

if activeName then
    dprint('^2detected ^3%s^7 (%s) — gauge writes will route through this resource', activeName, activeKind)
else
    dprint('^3no recognised fuel resource started^7 — gauge writes will no-op (visible leak trail still works via tank-health)')
end

---Returns the vehicle's current fuel level (typically 0–100), or nil if
---no fuel resource is installed or the read failed.
---@param vehicle number
---@return number|nil
function fuel.getLevel(vehicle)
    if not activeName then return nil end

    if activeKind == 'state_bag' then
        local v = Entity(vehicle).state.fuel
        return v
    end

    local ok, level = pcall(exports[activeName].GetFuel, exports[activeName], vehicle)
    if ok then return level end
    dprint('getLevel: export call to %s:GetFuel failed', activeName)
    return nil
end

---Sets the vehicle's fuel level. Returns true on success, false if the
---write didn't go through.
---@param vehicle number
---@param level number 0–100 range (the common scale).
---@return boolean
function fuel.setLevel(vehicle, level)
    if not activeName then return false end

    if activeKind == 'state_bag' then
        Entity(vehicle).state:set('fuel', level, true)
        return true
    end

    local ok, err = pcall(exports[activeName].SetFuel, exports[activeName], vehicle, level)
    if not ok then
        dprint('setLevel: export call to %s:SetFuel failed — %s', activeName, tostring(err))
    end
    return ok == true
end

return fuel
