---@type table sd-trapphone config root (configs/config.lua).
local config = require 'configs.config'
---@type table Handset items and colours (shared.handsets).
local handsets = require 'shared.handsets'
---@type table Console log helper (shared.log).
local log = require 'shared.log'
---@type table The handset (client.trapphone.phone): page messages + open state.
local phone = require 'client.trapphone.phone'
---@type table Shared world helpers (client.trapphone.world): owns every entity we create.
local world = require 'client.trapphone.world'
---@type table Target bridge (bridge.client.target).
local target = require 'bridge.client.target'
---@type table Notify bridge (bridge.client.notify).
local notify = require 'bridge.client.notify'
---@type table Inventory bridge (bridge.client.inventory).
local inventory = require 'bridge.client.inventory'

---@type table Street selling config as the client plays it (config.Selling, shared half).
local CFG = config.Selling
---@type table Which moments get a camera cut (config.Selling.Cinematics).
local CIN = CFG.Cinematics or {}

---@type string Target option name for handing over to a customer.
local SERVE_NAME = 'sd-trapphone:serve'
---@type string Target option name for pitching an ambient ped.
local PITCH_NAME = 'sd-trapphone:pitch'
---@type number Metres from a parked buyer's driver at which you count as "at the window".
local WINDOW_DISTANCE = 3.2
---@type integer Milliseconds a ped look is skipped after it was a customer (the server refuses it too).
local KEY_REUSE_MS = 150000
---@type integer Driving style for buyers: obey lights, avoid traffic, stop for peds.
local DRIVE_STYLE = 786603

---@type table<integer, boolean> Ped types that are never customers.
local IGNORED_TYPES = {}
for _, pedType in ipairs(CFG.IgnorePedTypes or {}) do
    IGNORED_TYPES[pedType] = true
end

---@class TrapCustomer
---@field ticketId string
---@field kind 'corner'|'car'|'pitch'
---@field ped integer
---@field vehicle integer|nil a car buyer's vehicle
---@field borrowed boolean an ambient ped we took control of (handed back, never deleted)
---@field offer table the Offer the server texted
---@field number string the number it came from
---@field serveAt integer GetGameTimer() before which the server refuses the sale
---@field accepted boolean the offer was accepted on the phone
---@field arrived boolean close enough to serve
---@field serving boolean the hand-off is running
---@field deadline integer GetGameTimer() at which a customer still on the way is given up on
---@field started integer GetGameTimer() the customer was set going
---@field waitUntil integer|nil GetGameTimer() at which a parked buyer leaves
---@field stop vector3|nil where a car buyer parks

---@type table Selling module; the table returned at end of file. The client side of the
---corner: fetching a customer, walking or driving them over, the serve and its hand-off, and
---pitching to people on the street. The server decides everything that is worth money.
local selling = {}

---@type 'idle'|'corner'|'drops' What the Hustle app is doing.
local mode = 'idle'
---@type TrapCustomer|nil The customer being dealt with (one at a time).
local customer
---@type integer GetGameTimer() before which the server is not asked for a customer.
local nextAsk = 0
---@type integer Bumped whenever the corner loop is restarted, so an old loop stops.
local loopRun = 0
---@type table<string, integer> Ped looks used lately, by GetGameTimer().
local recentKeys = {}
---@type table<integer, integer> Ped handles pitched lately, by GetGameTimer().
local pitchedPeds = {}
---@type { vehicle: integer, at: integer }[] Buyers' cars driving off, waiting to be cleaned up.
local leaving = {}
---@type boolean Whether the pitch option is on ambient peds right now.
local pitchOn = false

---Tell the player something: on the phone screen when it is out, as a notification otherwise.
---@param text string|nil
---@param tone? 'info'|'good'|'bad'
local function toast(text, tone)
    if not text or text == '' then return end

    if phone.isOpen() then
        phone.send('trap:toast', { text = text, tone = tone or 'info' })
    else
        notify.show(text, tone == 'bad' and 'error' or tone == 'good' and 'success' or 'info')
    end
end

selling.toast = toast

---Whether an ambient ped could be a customer at all: a living pedestrian on foot who is not a
---player, not a service worker or animal, not busy running or fighting, and not owned by a
---script (ours included).
---@param ped integer
---@return boolean eligible
local function eligible(ped)
    if not DoesEntityExist(ped) or ped == cache.ped then return false end
    if IsPedAPlayer(ped) or not IsPedHuman(ped) then return false end
    if IGNORED_TYPES[GetPedType(ped)] then return false end
    if IsPedDeadOrDying(ped, true) or IsPedInAnyVehicle(ped, true) then return false end
    if IsPedFleeing(ped) or IsPedInMeleeCombat(ped) or IsPedRagdoll(ped) or IsPedShooting(ped) then return false end
    if IsEntityAMissionEntity(ped) or world.isTracked(ped) then return false end

    return true
end

---Get network control of a ped so our tasks stick. A ped that isn't networked is already ours.
---@param ped integer
---@return boolean controlled
local function takeControl(ped)
    if not NetworkGetEntityIsNetworked(ped) then return true end

    for _ = 1, 12 do
        if NetworkHasControlOfEntity(ped) then return true end

        NetworkRequestControlOfEntity(ped)
        Wait(50)
    end

    return NetworkHasControlOfEntity(ped)
end

---Take an ambient ped out of its routine so it does what we ask. It is tracked as borrowed,
---so every way out of this module hands it back.
---@param ped integer
local function borrow(ped)
    SetEntityAsMissionEntity(ped, true, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    ClearPedTasks(ped)
    SetPedKeepTask(ped, true)
    world.track('borrowed', ped)
end

---The nearest few ambient peds that could walk over, one picked at random and taken control of.
---@return integer|nil ped
local function findAmbient()
    local me = GetEntityCoords(cache.ped)
    local now = GetGameTimer()
    local radius = CFG.CustomerSearchRadius or 45.0
    local found = {}

    for _, ped in ipairs(GetGamePool('CPed')) do
        if eligible(ped) then
            local distance = #(me - GetEntityCoords(ped))

            if distance <= radius then
                local seen = recentKeys[world.pedKey(ped)]
                if not seen or now - seen > KEY_REUSE_MS then found[#found + 1] = { ped = ped, distance = distance } end
            end
        end
    end

    table.sort(found, function(a, b) return a.distance < b.distance end)

    -- Try a random one of the closest handful first, then whoever is left, nearest first.
    local first = #found > 0 and math.random(math.min(4, #found)) or 0

    if first > 1 then found[1], found[first] = found[first], found[1] end

    for i = 1, math.min(#found, 6) do
        local ped = found[i].ped
        if eligible(ped) and takeControl(ped) then return ped end
    end

    return nil
end

---A random model from a config list that this game build actually has.
---@param list (integer|string)[]
---@return integer|string|nil model
local function randomModel(list)
    if not list or #list == 0 then return nil end

    for _ = 1, 6 do
        local model = list[math.random(#list)]
        if IsModelInCdimage(model) then return model end
    end

    return nil
end

---Create a customer a little way off, for servers with no ambient population.
---@return integer|nil ped
local function createWalker()
    local range = (CFG.NoPedsServer or {}).SpawnDistance or { min = 25.0, max = 50.0 }
    local me = GetEntityCoords(cache.ped)
    local model = randomModel(CFG.PedModels)
    if not model then return nil end

    for _ = 1, 6 do
        local angle = math.random() * math.pi * 2
        local distance = range.min + math.random() * (range.max - range.min)
        local x, y = me.x + math.cos(angle) * distance, me.y + math.sin(angle) * distance
        local found, safe = GetSafeCoordForPed(x, y, me.z, true, 16)

        if found then
            local heading = GetHeadingFromVector_2d(me.x - safe.x, me.y - safe.y)
            return world.spawnPed(model, vec4(safe.x, safe.y, safe.z, heading))
        end
    end

    return nil
end

---Create a buyer's car on a road some way from the pull-up spot and send it there.
---@param spot { x: number, y: number, z: number, w: number } the stored pull-up spot
---@return integer|nil ped the driver
---@return integer|nil vehicle
---@return vector3|nil stop where it will park
local function createCar(spot)
    local at = vec3(spot.x, spot.y, spot.z)
    local radius = CFG.VehicleSpawnRadius or 80.0
    local vehicleModel, pedModel = randomModel(CFG.VehicleModels), randomModel(CFG.PedModels)
    if not vehicleModel or not pedModel then return nil end

    local start, heading

    for _ = 1, 8 do
        local angle = math.random() * math.pi * 2
        local found, node, nodeHeading = GetClosestVehicleNodeWithHeading(
            at.x + math.cos(angle) * radius, at.y + math.sin(angle) * radius, at.z, 1, 3.0, 0)

        if found and #(node - at) > radius * 0.5 and not IsSphereVisible(node.x, node.y, node.z, 3.0) then
            start, heading = node, nodeHeading
            break
        end

        if found and not start and #(node - at) > radius * 0.4 then start, heading = node, nodeHeading end
    end

    if not start then return nil end

    local sideFound, side = GetPointOnRoadSide(at.x, at.y, at.z, 0)
    local nodeFound, node = GetClosestVehicleNode(at.x, at.y, at.z, 1, 3.0, 0)
    local stop = sideFound and side or nodeFound and node or at

    if not world.loadModel(vehicleModel) or not world.loadModel(pedModel) then return nil end

    local vehicle = CreateVehicle(vehicleModel, start.x, start.y, start.z, heading, false, false)
    SetModelAsNoLongerNeeded(vehicleModel)

    if not vehicle or vehicle == 0 then
        SetModelAsNoLongerNeeded(pedModel)
        return nil
    end

    world.track('vehicle', vehicle)
    SetEntityAsMissionEntity(vehicle, true, true)
    SetVehicleOnGroundProperly(vehicle)
    SetVehicleEngineOn(vehicle, true, true, false)
    SetVehicleDoorsLocked(vehicle, 2)

    local ped = CreatePedInsideVehicle(vehicle, 4, pedModel, -1, false, true)
    SetModelAsNoLongerNeeded(pedModel)

    if not ped or ped == 0 then
        world.release(vehicle)
        return nil
    end

    world.track('ped', ped)
    SetEntityAsMissionEntity(ped, true, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedKeepTask(ped, true)
    SetPedCanBeDraggedOut(ped, false)
    TaskVehicleDriveToCoordLongrange(ped, vehicle, stop.x, stop.y, stop.z, 11.0, DRIVE_STYLE, 5.0)

    return ped, vehicle, stop
end

---Take the serve option off a customer.
---@param c TrapCustomer
local function removeServeTarget(c)
    local entity = c.vehicle or c.ped

    if DoesEntityExist(entity) then
        pcall(target.removeLocalEntity, entity, target.system == 'ox_target' and SERVE_NAME or locale('selling.target_serve'))
    end
end

---Delete buyers' cars that have driven far enough away or been around too long.
local function sweepLeaving()
    CreateThread(function()
        local maxAge = (CFG.VehicleCleanUpMinutes or 5) * 60000

        while #leaving > 0 do
            Wait(5000)

            local me = GetEntityCoords(cache.ped)
            local now = GetGameTimer()

            for i = #leaving, 1, -1 do
                local entry = leaving[i]
                local gone = not DoesEntityExist(entry.vehicle)

                if gone or now - entry.at > maxAge or #(me - GetEntityCoords(entry.vehicle)) > 160.0 then
                    world.release(entry.vehicle)
                    table.remove(leaving, i)
                end
            end
        end
    end)
end

---Send a buyer's car on its way and arrange for it to be cleaned up.
---@param c TrapCustomer
---@param fast boolean|nil tear off rather than pull away
local function driveOff(c, fast)
    local vehicle, ped = c.vehicle, c.ped
    if not vehicle or not DoesEntityExist(vehicle) then return end

    SetVehicleHandbrake(vehicle, false)

    if DoesEntityExist(ped) then
        TaskVehicleDriveWander(ped, vehicle, fast and 32.0 or 14.0, fast and 786468 or DRIVE_STYLE)
        SetPedKeepTask(ped, true)
    end

    if CFG.VehiclesAutoCleanUp then
        local sweeping = #leaving > 0

        leaving[#leaving + 1] = { vehicle = vehicle, at = GetGameTimer() }
        if not sweeping then sweepLeaving() end
    else
        world.forget(ped)
        world.forget(vehicle)
    end
end

---Let a customer go about their day: a borrowed ped is handed back to the street, a created
---one walks off and is removed shortly after, a car drives away.
---@param c TrapCustomer
local function letGo(c)
    removeServeTarget(c)

    if c.vehicle then
        driveOff(c)
        return
    end

    local ped = c.ped
    if not DoesEntityExist(ped) then
        world.release(ped)
        return
    end

    if c.borrowed then
        world.release(ped)
        return
    end

    ClearPedTasks(ped)
    TaskWanderStandard(ped, 10.0, 10)

    SetTimeout(20000, function()
        world.release(ped)
    end)
end

---Drop the current customer because they can't be served (never arrived, died, wandered
---off), and tell the server so its ticket doesn't linger.
---@param c TrapCustomer
local function lose(c)
    if customer ~= c then return end

    customer = nil
    TriggerServerEvent('sd-trapphone:server:customerLost', c.ticketId)
    letGo(c)
    nextAsk = GetGameTimer() + 4000
end

---The cash prop a sale of this size is paid with.
---@param total integer
---@return table row one config.Selling.MoneyProps row
local function moneyProp(total)
    local props = CFG.MoneyProps or {}

    for i = 1, #props do
        if total <= props[i].upTo then return props[i] end
    end

    return props[#props] or {}
end

---The customer pulled a weapon instead of paying: a moment of threat, then they run for it.
---@param c TrapCustomer
local function robbery(c)
    toast(locale('selling.robbed'), 'bad')
    removeServeTarget(c)

    local ped = c.ped
    if not DoesEntityExist(ped) then return end

    world.cinematic(ped, 2600, CIN.Robbery)

    if c.vehicle then
        driveOff(c, true)
        return
    end

    GiveWeaponToPed(ped, `WEAPON_PISTOL`, 12, false, true)
    TaskAimGunAtEntity(ped, cache.ped, 1300, false)
    PlayPedAmbientSpeechNative(ped, 'GENERIC_INSULT_HIGH', 'SPEECH_PARAMS_FORCE_SHOUTED')

    SetTimeout(1300, function()
        if not DoesEntityExist(ped) then return end

        TaskSmartFleePed(ped, cache.ped, 200.0, -1, false, false)
        SetPedKeepTask(ped, true)
    end)

    -- Once they are well away they stop being ours: a borrowed ped goes back to the game
    -- (unarmed, reacting to the world again), a created one is removed.
    SetTimeout(20000, function()
        if not c.borrowed then
            world.release(ped)
            return
        end

        if DoesEntityExist(ped) then
            RemoveAllPedWeapons(ped, true)
            SetBlockingOfNonTemporaryEvents(ped, false)
            SetPedKeepTask(ped, false)
        end

        world.forget(ped)
    end)
end

---Hand over to the current customer and ask the server to complete the sale. Everything that
---can go wrong ends with the customer let go and the busy flag cleared.
---@param c TrapCustomer
local function serve(c)
    if customer ~= c or c.serving or world.isBusy() then return end

    if cache.vehicle then
        toast(locale('selling.on_foot'), 'bad')
        return
    end

    local reach = c.vehicle and WINDOW_DISTANCE or (CFG.ServeDistance or 2.2) + 0.8

    if not DoesEntityExist(c.ped) or #(GetEntityCoords(cache.ped) - GetEntityCoords(c.ped)) > reach then
        toast(locale('selling.too_far'), 'bad')
        return
    end

    c.serving = true
    world.setBusy('sale', true)

    -- The server won't take a sale sooner than MinServeSeconds after the offer; a customer
    -- found two steps away has to be talked to for a moment first.
    local early = c.serveAt - GetGameTimer()
    if early > 0 then
        world.faceEachOther(cache.ped, c.ped)
        Wait(early)
    end

    local still = customer == c and DoesEntityExist(c.ped) and not IsPedDeadOrDying(c.ped, true)
        and #(GetEntityCoords(cache.ped) - GetEntityCoords(c.ped)) <= reach + 1.0

    if not still then
        c.serving = false
        world.setBusy('sale', false)
        if customer == c then lose(c) end
        return
    end

    local offer = c.offer
    local info = config.Drugs.Items[offer.item] or {}
    local cash = moneyProp(offer.price)

    world.cinematic(c.ped, (CFG.HandOff.Ms or 1800) + 900, c.vehicle and CIN.VehicleSales or CIN.Sales)
    world.handOff(c.ped, { give = info.prop, take = cash.model, large = info.largePackage or cash.largePackage })

    local res = lib.callback.await('sd-trapphone:server:completeSale', false, c.ticketId)

    world.setBusy('sale', false)
    c.serving = false
    recentKeys[world.pedKey(c.ped)] = GetGameTimer()

    -- A stop or cleanup that ran during the hand-off already dealt with this customer.
    if customer ~= c then return end

    customer = nil
    nextAsk = GetGameTimer() + 3000

    if res and res.ok and res.data and res.data.robbed then
        robbery(c)
        return
    end

    if res and res.ok and res.data then
        local tip = res.data.tip or 0

        if tip > 0 then
            toast(locale('selling.sold_tip', res.data.total, tip), 'good')
        else
            toast(locale('selling.sold', res.data.total), 'good')
        end
    else
        toast(res and res.error or locale('selling.failed'), 'bad')
        TriggerServerEvent('sd-trapphone:server:customerLost', c.ticketId)
    end

    letGo(c)
end

---Put the serve option on a customer (the ped, or the car for a buyer who drove).
---@param c TrapCustomer
local function addServeTarget(c)
    target.addLocalEntity(c.vehicle or c.ped, {
        {
            name = SERVE_NAME,
            label = locale('selling.target_serve'),
            icon = 'fa-solid fa-handshake',
            distance = c.vehicle and WINDOW_DISTANCE or (CFG.ServeDistance or 2.2) + 0.5,
            canInteract = function()
                return customer == c and not c.serving and not world.isBusy()
            end,
            onSelect = function()
                CreateThread(function()
                    if customer == c then serve(c) end
                end)
            end,
        },
    })
end

---Send a walking customer towards the player.
---@param c TrapCustomer
local function walkOver(c)
    TaskGoToEntity(c.ped, cache.ped, -1, math.max(1.0, (CFG.ServeDistance or 2.2) - 0.6), 1.2, 1073741824, 0)
    SetPedKeepTask(c.ped, true)
end

---One look at a buyer in a car: still driving, just arrived, or waiting at the kerb.
---@param c TrapCustomer
---@param now integer GetGameTimer()
---@return boolean keep false when the customer was lost
local function carStep(c, now)
    local vehicle = c.vehicle

    if not DoesEntityExist(vehicle) then
        lose(c)
        return false
    end

    if not c.arrived then
        local away = #(GetEntityCoords(vehicle) - c.stop)

        -- Close enough, or stopped nearby on a road that won't let it get closer.
        if away <= 7.5 or (away <= 22.0 and now - c.started > 6000 and GetEntitySpeed(vehicle) < 0.3) then
            c.arrived = true
            c.waitUntil = now + (CFG.VehicleCustomerWaitTime or 30) * 1000

            TaskVehicleTempAction(c.ped, vehicle, 27, 2500)
            RollDownWindow(vehicle, 0)
            StartVehicleHorn(vehicle, 450, `HELDDOWN`, false)

            SetTimeout(2500, function()
                if customer == c and DoesEntityExist(vehicle) then SetVehicleHandbrake(vehicle, true) end
            end)

            toast(locale('selling.car_here'), 'info')
        elseif now > c.deadline then
            lose(c)
            return false
        end
    elseif now > c.waitUntil and not c.serving then
        lose(c)
        return false
    end

    return true
end

---One look at a customer on foot: still walking, just arrived, or left behind by the player.
---@param c TrapCustomer
---@param now integer GetGameTimer()
---@param distance number metres between the player and the customer
---@return boolean keep false when the customer was lost
local function walkStep(c, now, distance)
    local reach = CFG.ServeDistance or 2.2

    if not c.arrived then
        if distance <= reach then
            c.arrived = true
            ClearPedTasks(c.ped)
            TaskTurnPedToFaceEntity(c.ped, cache.ped, 1500)
            toast(locale('selling.customer_here'), 'info')
        elseif now > c.deadline then
            lose(c)
            return false
        elseif GetScriptTaskStatus(c.ped, `SCRIPT_TASK_GO_TO_ENTITY`) == 7 then
            -- The walk was dropped (bumped into, startled): point them at the player again.
            walkOver(c)
        end
    elseif distance > reach + 2.0 then
        -- The player wandered off; the customer follows rather than standing there forever.
        c.arrived = false
        walkOver(c)
    end

    return true
end

---Watch the current customer until they are served, lost or let go.
---@param c TrapCustomer
local function watch(c)
    CreateThread(function()
        while customer == c do
            Wait(400)

            if customer ~= c then break end

            if not c.serving then
                local ped = c.ped

                if not DoesEntityExist(ped) or IsPedDeadOrDying(ped, true) or IsEntityDead(cache.ped) then
                    lose(c)
                    break
                end

                local now = GetGameTimer()
                local distance = #(GetEntityCoords(cache.ped) - GetEntityCoords(ped))
                local keep

                if c.vehicle then keep = carStep(c, now) else keep = walkStep(c, now, distance) end
                if not keep then break end

                -- An offer accepted on the phone completes itself once the customer is in reach.
                local reach = c.vehicle and WINDOW_DISTANCE or (CFG.ServeDistance or 2.2) + 0.5

                if c.arrived and c.accepted and distance <= reach and not world.isBusy() and not cache.vehicle then
                    serve(c)
                end
            end
        end
    end)
end

---Remove a ped or car that was lined up for a customer the server then did not confirm.
---@param ped integer|nil
---@param vehicle integer|nil
local function discard(ped, vehicle)
    if vehicle then world.release(vehicle) end
    if ped then world.release(ped) end
end

---The server has a customer for us: produce the ped (a buyer's car, a created walker, or an
---ambient ped borrowed from the street), report its look, and start it on its way.
---@param res { ticketId: string, kind: 'corner'|'car', spot?: table }
local function begin(res)
    local run = loopRun
    local ped, vehicle, stop
    local borrowed = false

    if res.kind == 'car' and type(res.spot) == 'table' then
        ped, vehicle, stop = createCar(res.spot)
    end

    if not ped then
        if (CFG.NoPedsServer or {}).Enabled then
            ped = createWalker()
        else
            ped = findAmbient()

            if ped then
                borrowed = true
                borrow(ped)
            end
        end
    end

    if not ped then
        TriggerServerEvent('sd-trapphone:server:customerLost', res.ticketId)
        nextAsk = GetGameTimer() + 8000
        return
    end

    local key = world.pedKey(ped)
    local look = lib.callback.await('sd-trapphone:server:customerLook', false, res.ticketId, key)

    if look and look.retry then recentKeys[key] = GetGameTimer() end

    if not look or not look.ok or mode ~= 'corner' or run ~= loopRun or customer then
        discard(ped, vehicle)
        if look and look.ok then TriggerServerEvent('sd-trapphone:server:customerLost', res.ticketId) end
        nextAsk = GetGameTimer() + 4000
        return
    end

    local now = GetGameTimer()

    ---@type TrapCustomer
    local c = {
        ticketId = res.ticketId,
        kind = vehicle and 'car' or 'corner',
        ped = ped,
        vehicle = vehicle,
        borrowed = borrowed,
        offer = look.offer,
        number = look.number,
        serveAt = now + (look.serveAfter or 0) * 1000 + 250,
        accepted = false,
        arrived = false,
        serving = false,
        deadline = now + (vehicle and (CFG.ParkUpTimeout or 30) or (CFG.CustomerOnRouteTimeout or 180)) * 1000,
        started = now,
        stop = stop,
    }

    customer = c
    addServeTarget(c)
    if not vehicle then walkOver(c) end
    watch(c)

    log.debug('selling', 'customer %s on the way (%s)', c.ticketId, c.kind)
end

---Change what the Hustle app is doing on this client and start or stop what follows from it.
---@param new 'idle'|'corner'|'drops'
local function setMode(new)
    if new ~= 'corner' and new ~= 'drops' then new = 'idle' end

    local old = mode

    mode = new
    loopRun += 1

    if new ~= 'corner' and customer then
        local c = customer

        customer = nil
        letGo(c)
    end

    if old ~= new then TriggerEvent('sd-trapphone:client:hustleMode', new) end
    if new ~= 'corner' then return end

    local run = loopRun

    nextAsk = GetGameTimer() + 3000

    CreateThread(function()
        while mode == 'corner' and run == loopRun do
            Wait(1500)

            if mode ~= 'corner' or run ~= loopRun then break end

            if IsEntityDead(cache.ped) then
                selling.stop(locale('selling.stopped_dead'))
                break
            end

            if not handsets.carried() then
                selling.stop(locale('selling.stopped_phone'))
                break
            end

            if not customer and not world.isBusy() and not cache.vehicle and GetGameTimer() >= nextAsk then
                local res = lib.callback.await('sd-trapphone:server:requestCustomer', false)

                if mode ~= 'corner' or run ~= loopRun then break end

                if not res then
                    nextAsk = GetGameTimer() + 5000
                elseif res.ok then
                    nextAsk = GetGameTimer() + 2000
                    begin(res)
                elseif res.stopped then
                    setMode('idle')
                    break
                else
                    nextAsk = GetGameTimer() + math.max(2, tonumber(res.wait) or 5) * 1000
                end
            end
        end
    end)
end

---Stop hustling from this side (death, phone gone) and say why.
---@param reason? string localized
function selling.stop(reason)
    if mode == 'idle' then return end

    setMode('idle')
    lib.callback.await('sd-trapphone:server:hustleStop', false)
    toast(reason, 'bad')
end

---@return 'idle'|'corner'|'drops' mode what the Hustle app is doing
function selling.mode()
    return mode
end

---@return boolean selling whether the player is serving a corner
function selling.isCornerSelling()
    return mode == 'corner'
end

---@return boolean driving whether the player is taking drop-off orders
function selling.isDoingDropOffs()
    return mode == 'drops'
end

---Whether a ped can be pitched right now.
---@param ped integer
---@return boolean can
local function canPitch(ped)
    if customer or world.isBusy() or cache.vehicle then return false end
    if pitchedPeds[ped] then return false end

    return eligible(ped)
end

---Walk up to someone and offer. The server decides whether they bite; if they do, the sale
---is served on the spot.
---@param ped integer
local function pitch(ped)
    if type(ped) ~= 'number' or not canPitch(ped) then return end

    world.setBusy('pitch', true)

    if not takeControl(ped) then
        world.setBusy('pitch', false)
        toast(locale('selling.pitch_ignored'), 'info')
        return
    end

    pitchedPeds[ped] = GetGameTimer()
    borrow(ped)
    world.faceEachOther(cache.ped, ped)

    local res = lib.callback.await('sd-trapphone:server:pitch', false, world.pedKey(ped))

    world.setBusy('pitch', false)

    if not res or not res.ok then
        if res and res.refused then
            if DoesEntityExist(ped) then
                PlayPedAmbientSpeechNative(ped, 'GENERIC_INSULT_MED', 'SPEECH_PARAMS_FORCE_NORMAL')
            end
            notify.show(res.error or locale('selling.pitch_refused'), 'error')
        else
            toast(res and res.error or locale('selling.failed'), 'bad')
        end

        world.release(ped)
        return
    end

    local offer = res.offer
    local now = GetGameTimer()

    ---@type TrapCustomer
    local c = {
        ticketId = res.ticketId,
        kind = 'pitch',
        ped = ped,
        borrowed = true,
        offer = offer,
        number = res.number,
        serveAt = now + (res.serveAfter or 0) * 1000 + 250,
        accepted = true,
        arrived = true,
        serving = false,
        deadline = now + 60000,
        started = now,
    }

    customer = c
    addServeTarget(c)
    notify.show(locale('selling.pitch_yes', offer.qty, offer.label, offer.price), 'success')
    watch(c)
    serve(c)
end

---Put the pitch option on ambient peds while the player carries a trap phone, and take it
---off when they don't.
local function refreshPitch()
    local want = CFG.ApproachEnabled == true and handsets.carried()

    if want and not pitchOn then
        pitchOn = true
        target.addGlobalPed({
            {
                name = PITCH_NAME,
                label = locale('selling.target_pitch'),
                icon = 'fa-solid fa-comment-dollar',
                distance = 2.0,
                canInteract = function(entity)
                    return canPitch(entity)
                end,
                onSelect = function(data)
                    -- ox_target hands over a table, qb-target the entity itself.
                    local entity = type(data) == 'table' and data.entity or data

                    CreateThread(function()
                        pitch(entity)
                    end)
                end,
            },
        })
    elseif not want and pitchOn then
        pitchOn = false
        pcall(target.removeGlobalPed, target.system == 'ox_target' and PITCH_NAME or locale('selling.target_pitch'))
    end
end

RegisterNUICallback('trap:hustle:start', function(data, cb)
    local res = lib.callback.await('sd-trapphone:server:hustleStart', false, data and data.mode, data and data.family)

    if res and res.ok and res.data then setMode(res.data.mode) end

    cb(res or { ok = false, error = locale('selling.failed') })
end)

RegisterNUICallback('trap:hustle:stop', function(_, cb)
    setMode('idle')

    cb(lib.callback.await('sd-trapphone:server:hustleStop', false) or { ok = true })
end)

RegisterNUICallback('trap:hustle:setSpot', function(_, cb)
    cb(lib.callback.await('sd-trapphone:server:setSpot', false) or { ok = false, error = locale('selling.failed') })
end)

RegisterNUICallback('trap:hustle:clearSpot', function(_, cb)
    cb(lib.callback.await('sd-trapphone:server:clearSpot', false) or { ok = false, error = locale('selling.failed') })
end)

-- Accept, decline or counter from the phone. The server answers for every kind of offer; a
-- corner customer in front of us is updated here, drop-offs follow the server's own events.
RegisterNUICallback('trap:offer:respond', function(data, cb)
    if type(data) ~= 'table' then
        cb({ ok = false, error = locale('selling.failed') })
        return
    end

    local res = lib.callback.await('sd-trapphone:server:offerRespond', false, data.number, data.ticketId, data.action,
        tonumber(data.price))

    local c = customer

    if res and res.ok and res.data and c and c.ticketId == data.ticketId then
        c.offer.price = res.data.price or c.offer.price
        c.offer.state = res.data.state
        if res.data.state == 'accepted' then c.accepted = true end
    end

    cb(res or { ok = false, error = locale('selling.failed') })
end)

-- The server stopped the hustle (phone gone, out of stock, not enough police).
RegisterNetEvent('sd-trapphone:client:hustleStopped', function(data)
    setMode('idle')
    toast(type(data) == 'table' and data.reason or nil, 'bad')
end)

-- A ticket ended on the server (declined, walked, ran out). If it is the customer in front
-- of us and no hand-off is running, they leave.
RegisterNetEvent('sd-trapphone:client:ticketClosed', function(data)
    local c = customer
    if type(data) ~= 'table' or not c or c.ticketId ~= data.ticketId or c.serving then return end

    customer = nil
    letGo(c)
    nextAsk = GetGameTimer() + 3000

    if data.state == 'expired' or data.state == 'walked' then toast(locale('selling.customer_left'), 'info') end
end)

-- Losing the phone ends the hustle and takes the pitch option away.
inventory.onUpdate(function()
    refreshPitch()

    if mode ~= 'idle' and not handsets.carried() then
        CreateThread(function()
            selling.stop(locale('selling.stopped_phone'))
        end)
    end
end)

-- Not every inventory announces changes, so the pitch option is also checked on a slow timer.
-- The same timer forgets who was pitched long ago.
CreateThread(function()
    Wait(3000)

    while true do
        refreshPitch()

        local now = GetGameTimer()

        for ped, at in pairs(pitchedPeds) do
            if now - at > 300000 or not DoesEntityExist(ped) then pitchedPeds[ped] = nil end
        end
        for key, at in pairs(recentKeys) do
            if now - at > KEY_REUSE_MS then recentKeys[key] = nil end
        end

        Wait(5000)
    end
end)

---On resource stop the tracked entities are removed by client/main.lua; the global pitch
---option has to be taken off here because not every target resource cleans up after us.
---@param resource string stopping resource name
AddEventHandler('onResourceStop', function(resource)
    if resource ~= cache.resource then return end

    if pitchOn then pcall(target.removeGlobalPed, target.system == 'ox_target' and PITCH_NAME or locale('selling.target_pitch')) end
end)

return selling
