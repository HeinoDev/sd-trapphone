---@type table The handset (client.trapphone.phone).
local phone = require 'client.trapphone.phone'
---@type table Shared world helpers (client.trapphone.world).
local world = require 'client.trapphone.world'
---@type table Special contacts (client.trapphone.contacts): pending meets.
local contacts = require 'client.trapphone.contacts'

-- The public client exports (docs/design.md "Exports"), except the three the handset
-- registers itself (getActivePhone, isOpen, usePhone). Anything that changes state goes to
-- the server, which checks and paces it like any other client request.

---What the player is doing on the street, from the last state the server sent.
---@return string mode 'idle' | 'corner' | 'drops'
local function hustleMode()
    local state = phone.state()

    return state and state.hustle and state.hustle.mode or 'idle'
end

---Whether the player is corner selling.
---@return boolean selling
exports('isCornerSelling', function()
    return hustleMode() == 'corner'
end)

---Whether the player is on a drop-off run.
---@return boolean running
exports('isDoingDropOffs', function()
    return hustleMode() == 'drops'
end)

---Whether the player is in the middle of a sale, a meeting, bagging up or anything else
---this resource runs.
---@return boolean busy
exports('isBusy', function()
    return world.isBusy()
end)

---Put a text on the player's own trap phone.
---@param text string
---@param sender? string who it is shown as coming from
---@return boolean sent
exports('sendMessage', function(text, sender)
    if type(text) ~= 'string' or text == '' then return false end

    return lib.callback.await('sd-trapphone:server:exportMessage', false, text, type(sender) == 'string' and sender or nil) == true
end)

---Save a plain contact on the player's own trap phone.
---@param contact { number: string, name: string }
---@return boolean added
exports('addContact', function(contact)
    if type(contact) ~= 'table' or type(contact.number) ~= 'string' or type(contact.name) ~= 'string' then return false end

    return lib.callback.await('sd-trapphone:server:addContact', false, contact.number, contact.name) == true
end)

---Point the map at an introduction that is waiting, or ask for one. Asking gets the same
---odds and unlock rules as a level-up, and the server only listens now and then.
---@return boolean meeting true when there is (now) an introduction to go to
exports('meetNewContact', function()
    if contacts.route() then return true end

    return lib.callback.await('sd-trapphone:server:requestIntro', false) == true
end)

---The player's relationship with a ped look (see world.pedKey), -100..100.
---@param pedKey string
---@return integer relationship
exports('getPedRelationship', function(pedKey)
    if type(pedKey) ~= 'string' then return 0 end

    return lib.callback.await('sd-trapphone:server:pedRelationship', false, pedKey) or 0
end)

---Move the player's relationship with a ped look. Souring one is free; sweetening one is
---capped at a sale's worth and paced by the server.
---@param pedKey string
---@param amount number
---@return integer|false relationship the value afterwards, false when the server refused
exports('updatePedRelationship', function(pedKey, amount)
    if type(pedKey) ~= 'string' or type(amount) ~= 'number' then return false end

    return lib.callback.await('sd-trapphone:server:movePedRelationship', false, pedKey, amount) or false
end)
