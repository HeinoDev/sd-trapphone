---@type table sd-trapphone config root (configs/config.lua).
local config = require 'configs.config'
---@type table Handset items and colours (shared.handsets).
local handsets = require 'shared.handsets'
---@type table Console log helper (shared.log).
local log = require 'shared.log'
---@type table Shared world helpers (client.trapphone.world): owns every entity we create.
local world = require 'client.trapphone.world'
---@type table Target bridge (bridge.client.target).
local target = require 'bridge.client.target'
---@type table Notify bridge (bridge.client.notify).
local notify = require 'bridge.client.notify'
---@type table Inventory bridge (bridge.client.inventory).
local inventory = require 'bridge.client.inventory'

---@type table Contact config (config.Contacts), shared half.
local CFG = config.Contacts

---@class TrapMeet
---@field key string the contact's key
---@field kind 'intro'|'order'
---@field name string
---@field model integer
---@field spawn vector4 where the contact stands
---@field walkTo? vector3 where they stroll over from
---@field label string the area, as the contact named it
---@field deadline integer GetGameTimer() the contact stops waiting
---@field blip integer
---@field ped? integer the contact, once the player is close
---@field busy? boolean a meeting is being played out
---@field gone? boolean the server dropped it while it was busy

---@type table Contacts module; the table returned at end of file. Meeting the people who
---text the phone: marking where they wait, putting them there when the player gets close,
---and the contact screen's actions.
local contacts = {}

---@type table<string, TrapMeet> Pending meets by contact key.
local meets = {}
---@type boolean Whether the staging loop is running.
local looping = false

---@type table Blip a waiting contact is marked with.
local BLIP = { sprite = 280, colour = 5, scale = 0.8 }
---@type integer Cash the player visibly hands over when collecting an order.
local CASH_PROP = `prop_anim_cash_note`
---@type integer Milliseconds a contact takes to wander off before they are removed.
local LEAVE_MS = 20000

---Take a contact's ped out of the world.
---@param meet TrapMeet
local function unstage(meet)
    local ped = meet.ped
    if not ped then return end

    meet.ped = nil
    target.removeLocalEntity(ped)
    world.release(ped)
end

---Forget a meet entirely: its ped and its blip.
---@param key string contact key
local function clear(key)
    local meet = meets[key]
    if not meet then return end

    meets[key] = nil
    unstage(meet)
    world.release(meet.blip)
end

---Let a contact walk off after a meeting, then remove them.
---@param meet TrapMeet
local function walkOff(meet)
    local ped = meet.ped

    meets[meet.key] = nil
    meet.ped = nil
    world.release(meet.blip)

    if not ped then return end

    target.removeLocalEntity(ped)

    if DoesEntityExist(ped) then
        FreezeEntityPosition(ped, false)
        ClearPedTasks(ped)
        TaskWanderStandard(ped, 10.0, 10)
    end

    SetTimeout(LEAVE_MS, function()
        world.release(ped)
    end)
end

---Meet the contact the player is standing with: the server decides whether they are really
---there and what happens, then the hand-over is played out.
---@param key string contact key
local function meetNow(key)
    local meet = meets[key]
    if not meet or meet.busy or not meet.ped or world.isBusy() then return end

    meet.busy = true
    world.setBusy('meet', true)

    local res = lib.callback.await('sd-trapphone:server:meetContact', false, key)

    if not res or not res.ok then
        notify.show((res and res.error) or locale('contacts.no_answer'), 'error')
    else
        local ok, err = pcall(function()
            world.faceEachOther(cache.ped, meet.ped)
            world.cinematic(meet.ped, 3500, config.Selling.Cinematics.Interactions)

            if res.data.kind == 'order' then
                local first = res.data.items[1] and config.Drugs.Items[res.data.items[1].item]

                world.handOff(meet.ped, { give = CASH_PROP, take = first and first.prop or nil })
                notify.show(locale('contacts.order_collected', res.data.total), 'success')
            else
                Wait(1500)
                notify.show(locale('contacts.met', res.data.name), 'success')
            end
        end)

        if not ok then log.error('contacts', 'meeting scene failed: %s', err) end

        meet.gone = true
    end

    world.setBusy('meet', false)
    meet.busy = false

    -- The server dropped the meet while the scene played (it is done, or it ran out).
    if meet.gone and meets[key] == meet then walkOff(meet) end
end

---Put a contact at their meeting place, with the option to meet them.
---@param meet TrapMeet
local function stage(meet)
    local spawn, from = meet.spawn, meet.walkTo
    local start = from and vec4(from.x, from.y, from.z, spawn.w) or spawn
    local ped = world.spawnPed(meet.model, start, {
        invincible = true,
        frozen = from == nil,
        scenario = from == nil and 'WORLD_HUMAN_STAND_IMPATIENT' or nil,
    })

    if not ped then return end

    meet.ped = ped

    if from then TaskGoStraightToCoord(ped, spawn.x, spawn.y, spawn.z, 1.0, -1, spawn.w, 0.5) end

    local key = meet.key

    target.addLocalEntity(ped, {
        {
            name = 'trapphone_meet_' .. key,
            icon = meet.kind == 'order' and 'fa-solid fa-box' or 'fa-solid fa-handshake',
            label = meet.kind == 'order' and locale('contacts.target_collect') or locale('contacts.target_meet'),
            distance = 2.5,
            onSelect = function() CreateThread(function() meetNow(key) end) end,
        },
    })
end

---Stage contacts as the player comes near, take them away when the player leaves, and drop
---a meet whose time ran out. Runs only while there is a meet pending.
local function loop()
    if looping then return end
    looping = true

    CreateThread(function()
        while next(meets) do
            local here = GetEntityCoords(cache.ped)
            local now = GetGameTimer()

            for key, meet in pairs(meets) do
                local distance = #(here - vec3(meet.spawn.x, meet.spawn.y, meet.spawn.z))

                if not meet.busy then
                    if now >= meet.deadline then
                        clear(key)
                    elseif not meet.ped and distance <= CFG.MeetRadius then
                        stage(meet)
                    elseif meet.ped and (distance > CFG.MeetRadius + 30.0 or not DoesEntityExist(meet.ped)) then
                        unstage(meet)
                    end
                end
            end

            Wait(1000)
        end

        looping = false
    end)
end

---Bring the staged meets in line with the list the server sent.
---@param list table[] { key, kind, name, model, spawn, walkTo?, left, label }
local function apply(list)
    if type(list) ~= 'table' then return end

    local wanted = {}

    for i = 1, #list do
        local info = list[i]
        local meet = meets[info.key]

        wanted[info.key] = true

        -- An order after an intro reuses the key with a new place: start that one over.
        if meet and not meet.busy and (meet.kind ~= info.kind or #(vec3(meet.spawn.x, meet.spawn.y, meet.spawn.z) - vec3(info.spawn.x, info.spawn.y, info.spawn.z)) > 1.0) then
            clear(info.key)
            meet = nil
        end

        if meet then
            meet.deadline = GetGameTimer() + info.left * 1000
        else
            meets[info.key] = {
                key = info.key,
                kind = info.kind,
                name = info.name,
                model = info.model,
                spawn = info.spawn,
                walkTo = info.walkTo,
                label = info.label,
                deadline = GetGameTimer() + info.left * 1000,
                blip = world.blip(info.spawn, {
                    sprite = BLIP.sprite,
                    colour = BLIP.colour,
                    scale = BLIP.scale,
                    label = info.kind == 'order' and locale('contacts.blip_order') or locale('contacts.blip_meet'),
                }),
            }
        end
    end

    for key, meet in pairs(meets) do
        if not wanted[key] then
            if meet.busy then meet.gone = true else clear(key) end
        end
    end

    loop()
end

---Ask the server which meets the phone in the player's pocket has pending.
local function sync()
    apply(lib.callback.await('sd-trapphone:server:meets', false))
end

---The meets currently pending. Read-only.
---@return table<string, TrapMeet> meets
function contacts.pending()
    return meets
end

---Set the map waypoint to a pending meet.
---@param key? string contact key; the first pending introduction when omitted
---@return boolean set
function contacts.route(key)
    local meet = key and meets[key]

    if not key then
        for _, candidate in pairs(meets) do
            if candidate.kind == 'intro' then meet = candidate break end
        end
    end

    if not meet then return false end

    SetNewWaypoint(meet.spawn.x, meet.spawn.y)

    return true
end

RegisterNetEvent('sd-trapphone:client:meets', apply)

-- Opening the handset is when the server learns which phone this is, so ask again then.
AddEventHandler('sd-trapphone:client:opened', function()
    CreateThread(sync)
end)

CreateThread(function()
    Wait(5000)
    sync()
end)

-- The phone is gone (dropped, sold, taken): its meets go with it.
inventory.onUpdate(function()
    if next(meets) and not handsets.carried() then
        for key, meet in pairs(meets) do
            if meet.busy then meet.gone = true else clear(key) end
        end
    end
end)

-- Everything a contact's screen does goes to the server as one call. The three actions that
-- point at a place come back with coordinates: those set the waypoint here and stay out of
-- the page.
RegisterNUICallback('trap:contact:action', function(data, cb)
    if type(data) ~= 'table' or type(data.number) ~= 'string' or type(data.action) ~= 'string' then
        cb({ ok = false, error = locale('contacts.not_available') })
        return
    end

    local res = lib.callback.await('sd-trapphone:server:contactAction', false, data.number, data.action,
        type(data.args) == 'table' and data.args or nil)

    if type(res) ~= 'table' then
        cb({ ok = false, error = locale('contacts.no_answer') })
        return
    end

    if res.ok and type(res.data) == 'table' and res.data.coords then
        SetNewWaypoint(res.data.coords.x, res.data.coords.y)
        res.data.coords = nil
    end

    cb(res)
end)

return contacts
