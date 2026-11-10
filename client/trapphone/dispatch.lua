---@type table Console log helper (shared.log).
local log = require 'shared.log'
---@type table Dispatch bridge (bridge.client.alert): routes to whichever dispatch resource runs.
local alert = require 'bridge.client.alert'

---@type table Dispatch module; the table returned at end of file. The police alert leaves
---from the suspect's own client because that is where every supported dispatch resource
---expects it. The Dispatch config is server-only, so the server sends what to show.
local dispatch = {}

---A number from an untrusted-looking payload, or a fallback.
---@param value any
---@param fallback number|nil
---@return number|nil number
local function num(value, fallback)
    return type(value) == 'number' and value or fallback
end

---Fire a police alert through the dispatch bridge.
---@param data { code?: string, title?: string, message?: string, sprite?: integer, colour?: integer, scale?: number, blipSeconds?: integer, jobs?: string[], coords?: { x: number, y: number, z: number } }
function dispatch.send(data)
    if type(data) ~= 'table' then return end

    local title = type(data.title) == 'string' and data.title or 'Suspected drug deal'
    local message = type(data.message) == 'string' and data.message or title
    local code = type(data.code) == 'string' and data.code or '10-66'
    local coords

    if type(data.coords) == 'table' and num(data.coords.x) and num(data.coords.y) and num(data.coords.z) then
        coords = vec3(data.coords.x, data.coords.y, data.coords.z)
    end

    local seconds = num(data.blipSeconds)

    alert.send({
        displayCode = code,
        code = code,
        title = title,
        message = message,
        description = message,
        sprite = num(data.sprite, 51),
        colour = num(data.colour, 1),
        scale = num(data.scale, 1.0),
        blipText = title,
        blipTime = seconds and seconds * 1000 or nil,
        jobs = type(data.jobs) == 'table' and data.jobs or nil,
        coords = coords,
        dispatchcodename = 'drugsale',
        priority = 2,
    })

    log.debug('dispatch', 'alert sent (%s)', message)
end

RegisterNetEvent('sd-trapphone:client:alert', dispatch.send)

return dispatch
