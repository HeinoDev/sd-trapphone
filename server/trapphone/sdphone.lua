---@type table sd-trapphone config root (configs/config.lua).
local config = require 'configs.config'
---@type table Console log helper (shared.log).
local log = require 'shared.log'
---@type table Live phones (server.trapphone.phones).
local phones = require 'server.trapphone.phones'

---@type table sd-phone link config (config.Phone.SdPhone).
local CFG = config.Phone.SdPhone or {}

---@type table Sd-phone module; the table returned at end of file. The two-way text link between
---burners and sd-phone smartphones. Nothing in sd-phone is changed for it: texts to a smartphone
---go in through its `sendSystemMessage` export, and texts from one are picked up from the
---`sd-phone:server:messages:sent` event it already announces every send with.
local sdphone = {}

---@type string The smartphone resource.
local RESOURCE = 'sd-phone'

---@type table<string, string> What a non-text message from a smartphone reads as on a keypad
---phone, which can show none of them.
local PLACEHOLDER = {
    image = '[picture]',
    gif = '[picture]',
    voice = '[voice note]',
    location = '[location]',
    money = '[payment]',
    contact = '[contact card]',
}

---@return boolean linked whether texts cross over to sd-phone right now
function sdphone.linked()
    return CFG.Enabled ~= false and CFG.Messages ~= false and GetResourceState(RESOURCE) == 'started'
end

---Keep only the digits of a number, the form sd-phone files every number under.
---@param number string
---@return string digits
local function digitsOf(number)
    return (tostring(number or ''):gsub('%D', ''))
end

---Send a burner text to a smartphone number. It arrives in that phone under the burner number
---as a normal conversation, and a reply there comes back here.
---@param phone table TrapPhone the text is from
---@param number string the number as typed on the burner
---@param text string
---@return boolean delivered false when the number is not a smartphone in service, or it blocks us
function sdphone.send(phone, number, text)
    if not sdphone.linked() then return false end

    local target = digitsOf(number)
    local mine = digitsOf(phone.number)
    if target == '' or target == mine then return false end

    local ok, delivered = pcall(function()
        local holder = exports[RESOURCE]:getSourceByNumber(target)

        -- The export skips the block list of the person receiving, so honour it here.
        if holder and exports[RESOURCE]:isNumberBlocked(holder, mine) then return false end

        return exports[RESOURCE]:sendSystemMessage(mine, phone.number, target, text)
    end)

    if not ok then
        log.debug('sdphone', 'sending to %s failed: %s', target, delivered)
        return false
    end

    return delivered == true
end

-- A text typed on a burner to a number that is not another burner. Special contacts have
-- their own listener and their own numbers; anything else is tried as a smartphone.
phones.onMessage(function(_, phone, number, text)
    if phones.isReservedNumber(number) then return end

    sdphone.send(phone, number, text)
end)

-- Every text a smartphone sends is announced on this server-side event. One aimed at a number
-- sd-phone does not know, which belongs to a burner, is delivered to that burner.
-- AddEventHandler, not a net event: a client cannot fire it.
AddEventHandler('sd-phone:server:messages:sent', function(sent)
    if type(sent) ~= 'table' or sent.system or sent.group or sent.targetCitizenid then return end
    if not sdphone.linked() then return end

    local target = digitsOf(sent.targetNumber)
    local sender = digitsOf(sent.senderNumber)
    if target == '' or sender == '' then return end

    local phone = phones.byDigits(target)
    if not phone then return end

    local text = type(sent.body) == 'string' and sent.body or ''
    if text == '' then text = PLACEHOLDER[sent.kind] or '[message]' end

    text = phones.cleanText(text, 160)
    if not text then return end

    phones.message(phone, sender, { from = 'them', text = text }, { kind = 'player' })
end)

return sdphone
