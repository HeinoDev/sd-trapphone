---@type table sd-trapphone config root (configs/config.lua).
local config = require 'configs.config'
---@type table The handset (client.trapphone.phone).
local phone = require 'client.trapphone.phone'
---@type table Shared world helpers (client.trapphone.world): owns every entity we create.
local world = require 'client.trapphone.world'
---@type table Notify bridge (bridge.client.notify).
local notify = require 'bridge.client.notify'
---@type table Inventory bridge (bridge.client.inventory).
local inventory = require 'bridge.client.inventory'

---@type table Bagging config (config.Scales).
local CFG = config.Scales

---@type table Scales module; the table returned at end of file. Bagging up as the player
---does it: pick a split, weigh it out at the scales, get the bags.
local scales = {}

---@type boolean Whether the player is weighing right now.
local working = false

---Where the scales go: on whatever is in front of the player at about waist height (a table,
---a counter, a car bonnet), or on the ground when there is nothing.
---@return vector3 spot
local function restingSpot()
    local ped = cache.ped
    local top = GetOffsetFromEntityInWorldCoords(ped, 0.0, 0.6, 0.5)
    local bottom = GetOffsetFromEntityInWorldCoords(ped, 0.0, 0.6, -1.3)
    local ray = StartExpensiveSynchronousShapeTestLosProbe(top.x, top.y, top.z, bottom.x, bottom.y, bottom.z, 1 | 16, ped, 7)
    local _, hit, at = GetShapeTestResult(ray)

    if hit == 1 or hit == true then return at end

    return vec3(bottom.x, bottom.y, world.groundAt(bottom.x, bottom.y, top.z))
end

---Put the scales prop in front of the player.
---@return integer|nil prop tracked object, nil when the model won't load
local function placeScales()
    if not world.loadModel(CFG.Prop) then return nil end

    local spot = restingSpot()
    local prop = CreateObject(CFG.Prop, spot.x, spot.y, spot.z, false, false, false)

    SetModelAsNoLongerNeeded(CFG.Prop)

    if not prop or prop == 0 then return nil end

    SetEntityHeading(prop, GetEntityHeading(cache.ped))
    SetEntityCollision(prop, false, false)
    FreezeEntityPosition(prop, true)

    return world.track('object', prop)
end

---Weigh one split out: the prop, the animation and the wait, then the server does the swap.
---Stopping early changes nothing.
---@param slot integer|nil the scales' inventory slot
---@param split table one entry of the server's split list
local function bag(slot, split)
    local qty = 1

    if split.max > 1 then
        local input = lib.inputDialog(locale('scales.qty_title', split.fromLabel), {
            {
                type = 'slider',
                label = locale('scales.qty_label'),
                min = 1,
                max = split.max,
                default = 1,
                required = true,
            },
        })

        if not input then return end

        qty = math.floor(tonumber(input[1]) or 0)
    end

    if qty < 1 or working or world.isBusy() or cache.vehicle or IsEntityDead(cache.ped) then return end

    local start = lib.callback.await('sd-trapphone:server:scalesStart', false, slot, split.from, split.to, qty)

    if not start or not start.ok then
        notify.show((start and start.error) or locale('scales.no_answer'), 'error')
        return
    end

    working = true
    world.setBusy('scales', true)

    local prop = placeScales()
    local done = lib.progressBar({
        duration = start.data.seconds * 1000,
        label = locale('scales.progress', split.toLabel),
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = { dict = CFG.Anim.Dict, clip = CFG.Anim.Clip, flag = CFG.Anim.Flag },
    })

    world.release(prop)
    ClearPedTasks(cache.ped)
    world.setBusy('scales', false)
    working = false

    if not done then
        lib.callback.await('sd-trapphone:server:scalesCancel', false)
        notify.show(locale('scales.cancelled'), 'error')
        return
    end

    local res = lib.callback.await('sd-trapphone:server:scalesFinish', false)

    if not res or not res.ok then
        notify.show((res and res.error) or locale('scales.no_answer'), 'error')
        return
    end

    if res.data.rest > 0 then
        notify.show(locale('scales.done_rest', res.data.out, res.data.toLabel, res.data.rest), 'success')
    else
        notify.show(locale('scales.done', res.data.out, res.data.toLabel), 'success')
    end
end

---Use the scales: show every split the player can do with what they hold.
---@param slot? integer the scales' inventory slot, when known
function scales.open(slot)
    if not CFG.Enabled or working then return end

    if cache.vehicle or IsEntityDead(cache.ped) or world.isBusy() or lib.progressActive() then
        notify.show(locale('scales.not_now'), 'error')
        return
    end

    -- The handset and an ox_lib menu can't both hold the cursor.
    phone.close()

    local res = lib.callback.await('sd-trapphone:server:scalesOptions', false, slot)

    if not res or not res.ok then
        notify.show((res and res.error) or locale('scales.no_answer'), 'error')
        return
    end

    local options = {}

    if res.data.battery then
        options[#options + 1] = {
            title = locale('scales.battery', res.data.battery),
            icon = 'battery-half',
            progress = res.data.battery,
            colorScheme = res.data.battery > 20 and 'green' or 'red',
            readOnly = true,
        }
    end

    for _, split in ipairs(res.data.splits) do
        local description = split.rest > 0
            and locale('scales.split_desc_rest', split.per, split.rest, split.seconds)
            or locale('scales.split_desc', split.per, split.seconds)

        options[#options + 1] = {
            title = locale('scales.split_title', split.fromLabel, split.toLabel),
            description = description,
            icon = 'scale-balanced',
            metadata = {
                { label = locale('scales.meta_have'), value = split.have },
                split.drain > 0 and { label = locale('scales.meta_drain'), value = ('%d%%'):format(split.drain) } or nil,
            },
            onSelect = function() bag(slot, split) end,
        }
    end

    if #res.data.splits == 0 then
        options[#options + 1] = { title = locale('scales.nothing'), readOnly = true }
    end

    lib.registerContext({ id = 'trapphone_scales', title = locale('scales.title'), options = options })
    lib.showContext('trapphone_scales')
end

---Put a fresh battery in the scales. The server takes the battery and sets the charge.
function scales.replaceBattery()
    local res = lib.callback.await('sd-trapphone:server:scalesBattery', false)

    if res and res.ok then
        notify.show(res.data.message, 'success')
    else
        notify.show((res and res.error) or locale('scales.no_answer'), 'error')
    end
end

-- Inventories other than ox_inventory: the server registers the item as usable and sends this.
RegisterNetEvent('sd-trapphone:client:useScales', function(slot)
    scales.open(slot)
end)

-- ox_inventory uses both items through these exports (items.md: client.export).
exports('useScales', function(_, slot)
    scales.open(type(slot) == 'table' and slot.slot or nil)
end)

exports('useBatteries', function()
    scales.replaceBattery()
end)

-- Show the charge in the item's tooltip, on inventories that draw metadata.
CreateThread(function()
    pcall(inventory.registerDisplayMetadata, { battery = locale('scales.battery_label') })
end)

return scales
