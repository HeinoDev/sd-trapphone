---@type table sd-trapphone config root (configs/config.lua).
local config = require 'configs.config'
---@type table Handset items and colours (shared.handsets).
local handsets = require 'shared.handsets'
---@type table Console log helper (shared.log).
local log = require 'shared.log'
---@type table Notify bridge (bridge.client.notify).
local notify = require 'bridge.client.notify'
---@type table Inventory bridge (bridge.client.inventory).
local inventory = require 'bridge.client.inventory'

---@type table Handset config (config.Phone).
local CFG = config.Phone

---@type table Phone module; the table returned at end of file. The handset in the player's
---hand: opening and closing it, the prop and animation, and carrying messages between the
---server, the gameplay modules and the page.
local phone = {}

---@type boolean Whether the handset is out.
local open = false
---@type boolean Whether an open is waiting on the server (a second open in that gap is ignored).
local opening = false
---@type boolean Whether the page has a text field focused (movement keys go to the page).
local typing = false
---@type integer|nil The prop in the player's hand.
local prop
---@type table|nil Last full state the server sent (PhoneState, docs/design.md).
local mirror
---@type fun()[] Run whenever the handset closes.
local closeListeners = {}

---Send one message to the page.
---@param action string NUI action name ('trap:...')
---@param data any payload
function phone.send(action, data)
    SendNUIMessage({ action = action, data = data })
end

---@return boolean open whether the handset is out
function phone.isOpen()
    return open
end

---The last state the server sent for this phone (nil before it was ever opened). Read-only.
---@return table|nil state
function phone.state()
    return mirror
end

---Run a function whenever the handset is put away.
---@param fn fun()
function phone.onClose(fn)
    closeListeners[#closeListeners + 1] = fn
end

---Load a model, giving up quietly when this game build doesn't have it.
---@param model integer model hash
---@return boolean loaded
local function loadModel(model)
    if not IsModelValid(model) then return false end

    return pcall(lib.requestModel, model, 5000)
end

---Put the handset prop in the player's hand and start the texting animation.
---@param shell string|nil faceplate id of the phone being taken out
local function raise(shell)
    local ped = cache.ped
    local model = handsets.model(shell)

    -- The streamed handset when it is there, a base-game phone when it is not.
    if not loadModel(model) then model = CFG.Prop.Fallback end

    if loadModel(model) then
        local coords = GetEntityCoords(ped)
        local offset, rotation = CFG.Prop.Offset, CFG.Prop.Rotation

        prop = CreateObject(model, coords.x, coords.y, coords.z, true, true, false)
        SetEntityCollision(prop, false, false)
        AttachEntityToEntity(prop, ped, GetPedBoneIndex(ped, CFG.Prop.Bone), offset.x, offset.y, offset.z,
            rotation.x, rotation.y, rotation.z, true, true, false, true, 1, true)
        SetModelAsNoLongerNeeded(model)
    end

    local dict = cache.vehicle and CFG.Anim.VehicleDict or CFG.Anim.Dict
    if pcall(lib.requestAnimDict, dict, 3000) then
        TaskPlayAnim(ped, dict, CFG.Anim.In, 4.0, -4.0, -1, 50, 0.0, false, false, false)
        RemoveAnimDict(dict)
    end
end

---Take the handset prop away and play the put-away animation.
local function lower()
    local ped = cache.ped
    local dict = cache.vehicle and CFG.Anim.VehicleDict or CFG.Anim.Dict

    if pcall(lib.requestAnimDict, dict, 3000) then
        TaskPlayAnim(ped, dict, CFG.Anim.Out, 4.0, -4.0, 800, 50, 0.0, false, false, false)
        RemoveAnimDict(dict)
    end

    local held = prop
    prop = nil

    if held then
        SetTimeout(500, function()
            if DoesEntityExist(held) then DeleteEntity(held) end
        end)
    end
end

---What the page needs once to draw the handset: the look lists and the display tables.
---@return table setup
local function setup()
    local families, units, types = {}, {}, {}

    for key, info in pairs(config.Drugs.Families) do
        families[key] = { label = info.label, color = info.color }
    end
    for key, info in pairs(config.Drugs.Units) do
        units[key] = { label = info.label, short = info.short }
    end
    for key, info in pairs(config.Contacts.Types) do
        types[key] = { label = info.label, actions = info.actions }
    end

    return {
        wallpapers = CFG.Wallpapers,
        ringtones = CFG.Ringtones,
        peek = CFG.PeekOnMessage,
        peekSeconds = CFG.PeekSeconds,
        families = families,
        units = units,
        contactTypes = types,
        canPassNumbers = config.Contacts.CanPassNumbers,
    }
end

---The in-game clock as the status bar shows it.
---@return { h: integer, m: integer } clock
local function clock()
    return { h = GetClockHours(), m = GetClockMinutes() }
end

---Give the page focus. With KeepInput the player keeps control of their character, except
---while a text field is focused, when every key has to reach the page.
local function focus()
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(CFG.KeepInput and not typing)
end

---While the handset is out with the game still taking input: stop the mouse steering the
---camera, stop clicks firing weapons, and keep Esc for the phone instead of the pause menu.
local function guardControls()
    CreateThread(function()
        local tick = 0

        while open do
            DisableControlAction(0, 1, true) -- look left/right
            DisableControlAction(0, 2, true) -- look up/down
            DisableControlAction(0, 24, true) -- attack
            DisableControlAction(0, 25, true) -- aim
            DisableControlAction(0, 37, true) -- weapon wheel
            DisableControlAction(0, 140, true) -- melee light
            DisableControlAction(0, 141, true) -- melee heavy
            DisableControlAction(0, 142, true) -- melee alternate
            DisableControlAction(0, 257, true) -- attack 2
            DisableControlAction(0, 199, true) -- pause
            DisableControlAction(0, 200, true) -- pause alternate
            DisablePlayerFiring(cache.playerId, true)

            -- The number row dials on the handset, so it must not also swap weapons.
            for control = 157, 165 do
                DisableControlAction(0, control, true)
            end

            tick += 1
            if tick % 120 == 0 then phone.send('trap:clock', clock()) end

            if IsEntityDead(cache.ped) or IsPedCuffed(cache.ped) then phone.close() end

            Wait(0)
        end
    end)
end

---Take the handset out. Asks the server which phone this is and for its whole state.
---@param slot? integer inventory slot the item was used from
function phone.open(slot)
    if open or opening then return end
    if IsEntityDead(cache.ped) or IsPedCuffed(cache.ped) or IsPauseMenuActive() then return end

    opening = true
    local state = lib.callback.await('sd-trapphone:server:open', false, slot)
    opening = false

    if not state then
        notify.show(locale('phone.none'), 'error')
        return
    end

    open = true
    typing = false
    mirror = state

    raise(state.phone.shell)
    focus()
    phone.send('trap:open', { state = state, setup = setup(), clock = clock() })
    guardControls()
    TriggerEvent('sd-trapphone:client:opened')

    log.debug('phone', 'opened %s', state.phone.id)
end

---Put the handset away.
function phone.close()
    if not open then return end

    open = false
    typing = false

    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    phone.send('trap:close')
    lower()

    for i = 1, #closeListeners do
        local ok, err = pcall(closeListeners[i])
        if not ok then log.error('phone', 'close listener failed: %s', err) end
    end

    TriggerEvent('sd-trapphone:client:closed')
end

---Take the handset out, or put it away if it is already out.
---@param slot? integer inventory slot the item was used from
function phone.toggle(slot)
    if open then phone.close() else phone.open(slot) end
end

---Merge a partial state from the server into the mirror and pass it to the page.
---@param patch table top-level PhoneState keys
local function applyPatch(patch)
    if type(patch) ~= 'table' then return end

    if mirror then
        for key, value in pairs(patch) do
            mirror[key] = value
        end
    end

    phone.send('trap:state', patch)
end

RegisterNetEvent('sd-trapphone:client:use', function(slot)
    phone.toggle(slot)
end)

RegisterNetEvent('sd-trapphone:client:state', applyPatch)

-- A new message. The page rings, and when the handset is away it slides a small preview in.
RegisterNetEvent('sd-trapphone:client:message', function(payload)
    phone.send('trap:message', payload)
end)

RegisterNetEvent('sd-trapphone:client:offer', function(payload)
    phone.send('trap:offer', payload)
end)

RegisterNUICallback('trap:close', function(_, cb)
    phone.close()
    cb({ ok = true })
end)

-- The page focused or left a text field: hand the keyboard over, or give it back.
RegisterNUICallback('trap:typing', function(data, cb)
    typing = data and data.on == true
    if open then SetNuiFocusKeepInput(CFG.KeepInput and not typing) end
    cb({ ok = true })
end)

---@type table|nil Cached decode of locales/<config.Locale>.json for the page.
local uiStrings

RegisterNUICallback('trap:ui:locale', function(_, cb)
    if not uiStrings then
        local raw = LoadResourceFile(cache.resource, ('locales/%s.json'):format(config.Locale or 'en'))
        uiStrings = raw and json.decode(raw) or {}
    end

    cb({ locale = config.Locale or 'en', strings = uiStrings })
end)

RegisterNUICallback('trap:settings:set', function(data, cb)
    local ok = lib.callback.await('sd-trapphone:server:setSetting', false, data.key, data.value)

    if ok and mirror then mirror.settings[data.key] = data.value end

    cb({ ok = ok == true })
end)

RegisterNUICallback('trap:thread:read', function(data, cb)
    cb({ ok = lib.callback.await('sd-trapphone:server:readThread', false, data.number) == true })
end)

RegisterNUICallback('trap:thread:delete', function(data, cb)
    cb({ ok = lib.callback.await('sd-trapphone:server:deleteThread', false, data.number) == true })
end)

RegisterNUICallback('trap:contact:add', function(data, cb)
    cb({ ok = lib.callback.await('sd-trapphone:server:addContact', false, data.number, data.name) == true })
end)

RegisterNUICallback('trap:contact:delete', function(data, cb)
    cb({ ok = lib.callback.await('sd-trapphone:server:deleteContact', false, data.number) == true })
end)

RegisterNUICallback('trap:message:send', function(data, cb)
    cb({ ok = lib.callback.await('sd-trapphone:server:sendMessage', false, data.number, data.text) == true })
end)

RegisterNUICallback('trap:score:submit', function(data, cb)
    cb({ best = lib.callback.await('sd-trapphone:server:submitScore', false, data.game, data.score) or 0 })
end)

-- Losing the item puts the handset away.
inventory.onUpdate(function()
    if open and not handsets.carried() then phone.close() end
end)

RegisterCommand(CFG.OpenCommand, function()
    if not open and not handsets.carried() then
        notify.show(locale('phone.none'), 'error')
        return
    end

    phone.toggle()
end, false)

if CFG.OpenKey ~= '' then
    RegisterKeyMapping(CFG.OpenCommand, locale('phone.keybind'), 'keyboard', CFG.OpenKey)
end

-- ox_inventory opens the phone through this export (items.md: client.export).
exports('usePhone', function(_, slot)
    phone.toggle(type(slot) == 'table' and slot.slot or nil)
end)

exports('isOpen', phone.isOpen)

---The phone the player last had out: { id, number }, or nil.
exports('getActivePhone', function()
    return mirror and mirror.phone or nil
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= cache.resource then return end

    if open then
        SetNuiFocus(false, false)
        SetNuiFocusKeepInput(false)
    end
    if prop and DoesEntityExist(prop) then DeleteEntity(prop) end
end)

return phone
