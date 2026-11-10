---@type table sd-trapphone config root (configs/config.lua).
local config = require 'configs.config'
---@type table Console log helper (shared.log).
local log = require 'shared.log'

---@type table Hand-off animation config (config.Selling.HandOff).
local HAND = config.Selling.HandOff
---@type integer Bone the hand-off props sit in (right hand).
local HAND_BONE = 28422

---@type table World module; the table returned at end of file. Owns every ped, vehicle, prop
---and blip this resource puts in the world, so one call removes them all, and holds the small
---helpers every gameplay module shares (creating a ped, the hand-to-hand, the deal camera).
local world = {}

---@type table<integer, string> Everything tracked: handle -> kind. A 'borrowed' ped is an
---ambient ped we took control of; releasing it gives it back to the street, never deletes it.
local tracked = {}
---@type table<string, boolean> What the player is in the middle of, by name.
local busyWith = {}
---@type integer|nil The scripted deal camera while it is up.
local dealCam
---@type integer Bumped whenever a camera starts or is torn down, so an old timer can't end a newer one.
local camRun = 0

---Remember something we created so it is removed with everything else. Kinds: 'ped',
---'vehicle', 'object', 'blip', and 'borrowed' for an ambient ped that must be handed back
---rather than deleted.
---@param kind 'ped'|'vehicle'|'object'|'blip'|'borrowed'
---@param handle integer entity or blip handle
---@return integer handle the same handle, so a create call can be wrapped
function world.track(kind, handle)
    if handle and handle ~= 0 then tracked[handle] = kind end

    return handle
end

---Give a borrowed ambient ped back to the street: no task of ours, not frozen, free to be
---cleaned up by the game like any other pedestrian.
---@param ped integer
local function handBack(ped)
    if not DoesEntityExist(ped) then return end

    FreezeEntityPosition(ped, false)
    SetEntityInvincible(ped, false)
    SetBlockingOfNonTemporaryEvents(ped, false)
    SetPedKeepTask(ped, false)

    if not IsPedDeadOrDying(ped, true) and not IsPedFleeing(ped) and not IsPedInCombat(ped, cache.ped) then
        ClearPedTasks(ped)
        TaskWanderStandard(ped, 10.0, 10)
    end

    SetEntityAsMissionEntity(ped, false, false)
    SetPedAsNoLongerNeeded(ped)
end

---Remove one thing by kind.
---@param handle integer
---@param kind string
local function remove(handle, kind)
    if kind == 'blip' then
        if DoesBlipExist(handle) then
            SetBlipRoute(handle, false)
            RemoveBlip(handle)
        end
    elseif kind == 'borrowed' then
        handBack(handle)
    elseif DoesEntityExist(handle) then
        if kind == 'vehicle' then
            -- A driver we put in it goes with it.
            local driver = GetPedInVehicleSeat(handle, -1)
            if driver ~= 0 and tracked[driver] then
                tracked[driver] = nil
                DeleteEntity(driver)
            end
        end

        SetEntityAsMissionEntity(handle, true, true)
        DeleteEntity(handle)
    end
end

---Remove one tracked thing now (a borrowed ped is handed back instead).
---@param handle integer|nil
function world.release(handle)
    if not handle then return end

    local kind = tracked[handle]
    if not kind then return end

    tracked[handle] = nil
    remove(handle, kind)
end

---Stop tracking something without removing it, leaving it to the game (a buyer's car driving
---off when automatic clean-up is turned off).
---@param handle integer|nil
function world.forget(handle)
    if not handle or not tracked[handle] then return end

    local kind = tracked[handle]
    tracked[handle] = nil

    if kind ~= 'blip' and DoesEntityExist(handle) then SetEntityAsNoLongerNeeded(handle) end
end

---Whether a handle is one of ours.
---@param handle integer
---@return boolean tracked
function world.isTracked(handle)
    return tracked[handle] ~= nil
end

---Remove everything this resource put in the world and drop every busy flag. Safe to call at
---any time, including on resource stop.
function world.cleanupAll()
    world.cinematic(nil, 0, false)

    for handle, kind in pairs(tracked) do
        tracked[handle] = nil
        pcall(remove, handle, kind)
    end

    busyWith = {}
end

---The ground height under a point, waiting briefly for collision to load. Falls back to the
---given height when the ground can't be found.
---@param x number
---@param y number
---@param z number a height at or above the ground there
---@return number z
function world.groundAt(x, y, z)
    for _ = 1, 20 do
        local found, ground = GetGroundZFor_3dCoord(x, y, z + 2.0, false)
        if found then return ground end

        RequestCollisionAtCoord(x, y, z)
        Wait(25)
    end

    return z
end

---Load a model, giving up quietly when this game build doesn't have it.
---@param model integer|string model hash or name
---@return boolean loaded
local function loadModel(model)
    if not model or not IsModelInCdimage(model) then return false end

    return pcall(lib.requestModel, model, 5000)
end

world.loadModel = loadModel

---Create a local (not networked) ped standing on the ground at a spot. It ignores the world
---around it until told otherwise, and is tracked.
---@param model integer|string
---@param coords vector4 x, y, z, heading
---@param opts? { frozen?: boolean, invincible?: boolean, scenario?: string }
---@return integer|nil ped nil when the model could not be loaded
function world.spawnPed(model, coords, opts)
    opts = opts or {}

    if not loadModel(model) then
        log.debug('world', 'ped model %s could not be loaded', tostring(model))
        return nil
    end

    local z = world.groundAt(coords.x, coords.y, coords.z)
    local ped = CreatePed(4, model, coords.x, coords.y, z, coords.w or 0.0, false, true)

    SetModelAsNoLongerNeeded(model)

    if not ped or ped == 0 then return nil end

    SetEntityAsMissionEntity(ped, true, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedCanRagdollFromPlayerImpact(ped, false)
    SetPedDefaultComponentVariation(ped)
    SetPedRandomComponentVariation(ped, 0)

    if opts.invincible then SetEntityInvincible(ped, true) end
    if opts.scenario then TaskStartScenarioInPlace(ped, opts.scenario, 0, true) end
    if opts.frozen then FreezeEntityPosition(ped, true) end

    return world.track('ped', ped)
end

---A stable key for what a ped looks like: its model plus the head it was given. Two peds with
---the same key are the same "person" as far as relationships go.
---@param ped integer
---@return string key e.g. '9f2a01c4-1-0'
function world.pedKey(ped)
    return ('%08x-%d-%d'):format(GetEntityModel(ped) & 0xFFFFFFFF,
        math.max(0, GetPedDrawableVariation(ped, 0)), math.max(0, GetPedTextureVariation(ped, 0)))
end

---Turn two peds towards each other. A ped sitting in a vehicle is left alone.
---@param a integer
---@param b integer
function world.faceEachOther(a, b)
    if DoesEntityExist(a) and DoesEntityExist(b) then
        if not IsPedInAnyVehicle(a, false) then TaskTurnPedToFaceEntity(a, b, 800) end
        if not IsPedInAnyVehicle(b, false) then TaskTurnPedToFaceEntity(b, a, 800) end
    end
end

---Put a prop in a ped's hand.
---@param ped integer
---@param model integer|string|nil
---@param large boolean|nil carried in front with both hands
---@return integer|nil prop tracked object, nil when there is no model or it won't load
local function holdProp(ped, model, large)
    if not model or not loadModel(model) then return nil end

    local coords = GetEntityCoords(ped)
    local prop = CreateObject(model, coords.x, coords.y, coords.z - 5.0, false, false, false)

    SetModelAsNoLongerNeeded(model)

    if not prop or prop == 0 then return nil end

    SetEntityCollision(prop, false, false)

    if large then
        AttachEntityToEntity(prop, ped, GetPedBoneIndex(ped, HAND_BONE), 0.0, -0.12, -0.18, 0.0, 0.0, 0.0,
            true, true, false, true, 1, true)
    else
        AttachEntityToEntity(prop, ped, GetPedBoneIndex(ped, HAND_BONE), 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
            true, true, false, true, 1, true)
    end

    return world.track('object', prop)
end

---Play both sides of a hand-to-hand between the player and a ped: the player hands `give`
---over, the ped hands `take` back. Blocks until it is done. A ped in a vehicle keeps its
---seat and only the player animates.
---@param ped integer the other side
---@param opts { give?: integer|string, take?: integer|string, large?: boolean } prop models;
---large means the props are packages carried in front rather than held in the fingers
function world.handOff(ped, opts)
    opts = opts or {}

    local me = cache.ped
    local seated = not DoesEntityExist(ped) or IsPedInAnyVehicle(ped, false)
    local half = math.floor(HAND.Ms / 2)
    local loaded = pcall(lib.requestAnimDict, HAND.Dict, 3000)

    world.faceEachOther(me, ped)
    Wait(600)

    local given = holdProp(me, opts.give, opts.large)

    if loaded then
        TaskPlayAnim(me, HAND.Dict, HAND.GiveClip, 4.0, -4.0, HAND.Ms, 48, 0.0, false, false, false)
        if not seated then
            TaskPlayAnim(ped, HAND.Dict, HAND.TakeClip, 4.0, -4.0, HAND.Ms, 48, 0.0, false, false, false)
        end
    end

    Wait(half)

    -- Halfway through the product changes hands and the money comes back the other way.
    world.release(given)

    local taken = holdProp(me, opts.take, opts.large)

    Wait(HAND.Ms - half)

    world.release(taken)

    if loaded then
        StopAnimTask(me, HAND.Dict, HAND.GiveClip, 2.0)
        RemoveAnimDict(HAND.Dict)
    end
end

---A short scripted camera on a deal, off to the side of the entity and looking at it. Returns
---straight away; the camera ends by itself after `ms`. Does nothing when disabled, and calling
---it disabled takes down a camera that is up.
---@param entity integer|nil what to look at
---@param ms integer how long the camera stays
---@param enabled boolean|nil the config switch for this kind of moment
function world.cinematic(entity, ms, enabled)
    camRun += 1

    if dealCam then
        RenderScriptCams(false, true, 400, true, false)
        DestroyCam(dealCam, false)
        dealCam = nil
    end

    if not enabled or not entity or not DoesEntityExist(entity) or ms <= 0 then return end

    local run = camRun
    local from = GetOffsetFromEntityInWorldCoords(entity, 1.6, 1.4, 0.6)
    local at = GetEntityCoords(entity)

    dealCam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', from.x, from.y, from.z, 0.0, 0.0, 0.0, 45.0, false, 2)
    PointCamAtCoord(dealCam, at.x, at.y, at.z + 0.4)
    SetCamActive(dealCam, true)
    RenderScriptCams(true, true, 400, true, false)

    SetTimeout(ms, function()
        if run ~= camRun or not dealCam then return end

        RenderScriptCams(false, true, 400, true, false)
        DestroyCam(dealCam, false)
        dealCam = nil
    end)
end

---Add a tracked blip.
---@param coords vector3|vector4|table anything with x, y, z
---@param opts { sprite?: integer, colour?: integer, scale?: number, label?: string, route?: boolean }
---@return integer blip
function world.blip(coords, opts)
    opts = opts or {}

    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)

    SetBlipSprite(blip, opts.sprite or 1)
    SetBlipColour(blip, opts.colour or 0)
    SetBlipScale(blip, opts.scale or 0.8)
    SetBlipAsShortRange(blip, not opts.route)

    if opts.label then
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(opts.label)
        EndTextCommandSetBlipName(blip)
    end

    if opts.route then
        SetBlipRoute(blip, true)
        SetBlipRouteColour(blip, opts.colour or 0)
    end

    return world.track('blip', blip)
end

---Mark the player as in (or out of) the middle of something, by name, so two interactions
---never run over each other.
---@param name string what they are doing ('sale', 'pitch', 'drop', ...)
---@param on boolean
function world.setBusy(name, on)
    busyWith[name] = on and true or nil
end

---Whether the player is in the middle of anything.
---@return boolean busy
function world.isBusy()
    return next(busyWith) ~= nil
end

---Whether the player is in the middle of one named thing.
---@param name string
---@return boolean busy
function world.busy(name)
    return busyWith[name] == true
end

return world
