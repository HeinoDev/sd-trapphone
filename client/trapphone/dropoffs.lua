---@type table sd-trapphone config root (configs/config.lua).
local config = require 'configs.config'
---@type table Console log helper (shared.log).
local log = require 'shared.log'
---@type table Shared world helpers (client.trapphone.world): owns every entity we create.
local world = require 'client.trapphone.world'
---@type table Corner selling (client.trapphone.selling): the toast helper.
local selling = require 'client.trapphone.selling'
---@type table Target bridge (bridge.client.target).
local target = require 'bridge.client.target'

---@type table Street selling config (config.Selling, shared half): serve distance, hand-off, models.
local CFG = config.Selling

---@type string Target option name for handing a delivery over.
local SERVE_NAME = 'sd-trapphone:drop'
---@type number Metres from the door at which the customer is created.
local SPAWN_DISTANCE = 70.0
---@type number Metres from the door past which a created customer is removed again.
local DESPAWN_DISTANCE = 110.0

---@class TrapDrop
---@field ticketId string
---@field number string the number the order came from
---@field coords vector4 the door
---@field model integer|nil configured ped model, a random customer when nil
---@field item string
---@field qty integer
---@field price integer
---@field place string|nil
---@field blip integer
---@field ped integer|nil the customer once the player is close
---@field serving boolean the hand-off is running

---@type table Dropoffs module; the table returned at end of file. The client side of a
---delivery: the route to the door, the customer waiting there, and the hand-over. The server
---sends a door only once its order is accepted, and checks the distance itself.
local dropoffs = {}

---@type table<string, TrapDrop> Accepted deliveries by ticket id.
local drops = {}
---@type boolean Whether the watcher thread is running.
local watching = false

---Take the serve option off a delivery customer.
---@param drop TrapDrop
local function removeTarget(drop)
    if drop.ped and DoesEntityExist(drop.ped) then
        pcall(target.removeLocalEntity, drop.ped, target.system == 'ox_target' and SERVE_NAME or locale('dropoffs.target_serve'))
    end
end

---Point the GPS at the nearest delivery still to make, and only that one.
local function reroute()
    local me = GetEntityCoords(cache.ped)
    local nearest, best

    for _, drop in pairs(drops) do
        local distance = #(me - drop.coords.xyz)
        if not best or distance < best then nearest, best = drop, distance end
    end

    for _, drop in pairs(drops) do
        if DoesBlipExist(drop.blip) then SetBlipRoute(drop.blip, drop == nearest) end
    end

    if nearest then SetNewWaypoint(nearest.coords.x, nearest.coords.y) end
end

---Forget a delivery and remove what it put in the world.
---@param ticketId string
---@param walkOff boolean|nil let the customer walk away before they are removed
local function clear(ticketId, walkOff)
    local drop = drops[ticketId]
    if not drop then return end

    drops[ticketId] = nil
    removeTarget(drop)
    world.release(drop.blip)

    local ped = drop.ped

    if ped and DoesEntityExist(ped) and walkOff then
        ClearPedTasks(ped)
        TaskWanderStandard(ped, 10.0, 10)

        SetTimeout(15000, function()
            world.release(ped)
        end)
    else
        world.release(ped)
    end

    reroute()
end

---Hand a delivery over and ask the server to complete it.
---@param drop TrapDrop
local function serve(drop)
    if drops[drop.ticketId] ~= drop or drop.serving or world.isBusy() then return end

    if cache.vehicle then
        selling.toast(locale('dropoffs.get_out'), 'bad')
        return
    end

    local ped = drop.ped
    if not ped or not DoesEntityExist(ped) then return end

    if #(GetEntityCoords(cache.ped) - GetEntityCoords(ped)) > (CFG.ServeDistance or 2.2) + 0.8 then
        selling.toast(locale('selling.too_far'), 'bad')
        return
    end

    drop.serving = true
    world.setBusy('drop', true)

    local info = config.Drugs.Items[drop.item] or {}
    local cash

    for _, row in ipairs(CFG.MoneyProps or {}) do
        if drop.price <= row.upTo then
            cash = row
            break
        end
    end

    cash = cash or {}

    ClearPedTasks(ped)
    world.cinematic(ped, (CFG.HandOff.Ms or 1800) + 900, (CFG.Cinematics or {}).Sales)
    world.handOff(ped, { give = info.prop, take = cash.model, large = info.largePackage or cash.largePackage })

    local res = lib.callback.await('sd-trapphone:server:completeDrop', false, drop.ticketId)

    world.setBusy('drop', false)
    drop.serving = false

    if res and res.ok and res.data then
        local tip = res.data.tip or 0

        if tip > 0 then
            selling.toast(locale('selling.sold_tip', res.data.total, tip), 'good')
        else
            selling.toast(locale('dropoffs.delivered', res.data.total), 'good')
        end

        clear(drop.ticketId, true)
    else
        selling.toast(res and res.error or locale('selling.failed'), 'bad')

        -- The order ended on the server while we were handing over (out of product, too late,
        -- hustle stopped): it no longer exists, so neither does the route.
        if drop.closed or selling.mode() == 'idle' then clear(drop.ticketId, false) end
    end
end

---Create the customer at a door and give them the serve option.
---@param drop TrapDrop
local function createCustomer(drop)
    local model = drop.model

    if not model or not IsModelInCdimage(model) then
        local list = CFG.PedModels or {}
        model = list[math.random(math.max(1, #list))]
    end

    local ped = model and world.spawnPed(model, drop.coords, { scenario = 'WORLD_HUMAN_STAND_IMPATIENT' })
    if not ped then return end

    drop.ped = ped

    target.addLocalEntity(ped, {
        {
            name = SERVE_NAME,
            label = locale('dropoffs.target_serve'),
            icon = 'fa-solid fa-box-open',
            distance = (CFG.ServeDistance or 2.2) + 0.5,
            canInteract = function()
                return drops[drop.ticketId] == drop and not drop.serving and not world.isBusy()
            end,
            onSelect = function()
                CreateThread(function()
                    serve(drop)
                end)
            end,
        },
    })
end

---Watch the accepted deliveries: the customer appears when the player gets close to a door
---and is removed again if they drive off without delivering.
local function watch()
    if watching then return end

    watching = true

    CreateThread(function()
        while next(drops) do
            local me = GetEntityCoords(cache.ped)

            for _, drop in pairs(drops) do
                local distance = #(me - drop.coords.xyz)

                if not drop.ped and distance <= SPAWN_DISTANCE then
                    createCustomer(drop)
                elseif drop.ped and not drop.serving then
                    if not DoesEntityExist(drop.ped) or distance > DESPAWN_DISTANCE then
                        removeTarget(drop)
                        world.release(drop.ped)
                        drop.ped = nil
                    end
                end
            end

            Wait(1000)
        end

        watching = false
    end)
end

---Start tracking an accepted delivery.
---@param data table the route the server sent (ticketId, number, coords, model, item, qty, price, place)
local function add(data)
    if type(data) ~= 'table' or type(data.ticketId) ~= 'string' or type(data.coords) ~= 'table' then return end
    if drops[data.ticketId] then return end

    local coords = vec4(data.coords.x, data.coords.y, data.coords.z, data.coords.w or 0.0)

    drops[data.ticketId] = {
        ticketId = data.ticketId,
        number = data.number,
        coords = coords,
        model = data.model,
        item = data.item,
        qty = data.qty or 1,
        price = data.price or 0,
        place = data.place,
        blip = world.blip(coords, { sprite = 514, colour = 2, scale = 0.9, label = locale('dropoffs.blip') }),
        serving = false,
    }

    reroute()
    watch()

    log.debug('dropoffs', 'route added for %s', data.ticketId)
end

---Call an accepted delivery off. The server lets the customer know and the route is removed
---when its answer comes back as a closed ticket.
---@param ticketId string
---@return boolean ok
function dropoffs.cancel(ticketId)
    local drop = drops[ticketId]
    if not drop then return false end

    local res = lib.callback.await('sd-trapphone:server:offerRespond', false, drop.number, ticketId, 'decline')

    return res ~= nil and res.ok == true
end

---How many deliveries are accepted and still to make.
---@return integer count
function dropoffs.count()
    local count = 0

    for _ in pairs(drops) do
        count += 1
    end

    return count
end

RegisterNetEvent('sd-trapphone:client:dropAccepted', add)

-- A delivery ended on the server (delivered, called off, too late, hustle stopped).
RegisterNetEvent('sd-trapphone:client:ticketClosed', function(data)
    if type(data) ~= 'table' or data.kind ~= 'drop' then return end

    local drop = drops[data.ticketId]
    if not drop then return end

    if drop.serving then
        drop.closed = true
        return
    end

    clear(data.ticketId, false)

    if data.state == 'expired' then selling.toast(locale('dropoffs.too_late'), 'bad') end
end)

-- Going idle ends every delivery; the server closes its tickets too, this just makes sure no
-- route is left on the map if one of those messages is lost.
AddEventHandler('sd-trapphone:client:hustleMode', function(mode)
    if mode ~= 'idle' then return end

    for ticketId, drop in pairs(drops) do
        if not drop.serving then clear(ticketId, false) end
    end
end)

return dropoffs
