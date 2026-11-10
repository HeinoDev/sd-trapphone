---@type table sd-trapphone config root (configs/config.lua).
local config = require 'configs.config'
---@type table Console log helper (shared.log): the boot-time misconfig warning.
local log = require 'shared.log'

---@type table Player bridge (bridge.server.player): name + identifier lookups.
local playerBridge = require 'bridge.server.player'

---@type table Audit-logging config (config.Logs): master toggle + per-event switches.
local CFG = config.Logs or {}
---@type function|nil ox_lib server logger, or nil when no ox:logger backend is configured.
local logger = lib.logger

---@type table Audit module; the table returned at end of file.
local audit = {}

---Resolve a player's audit identity through the bridge: their character full name, character id
---(citizenid on qb/qbox, identifier on ESX), and the account username (GetPlayerName). Falls back
---to the username when the character can't be read. Self-contained (audit can't require
---reputation - that would cycle - so it does its own lookup).
---@param src integer player server id
---@return string character character full name, or the username as a fallback
---@return string|nil cid character id, or nil if no character
---@return string username the account display name
local function actorOf(src)
    local username = GetPlayerName(src) or ('src ' .. src)
    local okName, character = pcall(playerBridge.getName, src)
    if not okName or not character or character == 'Unknown' then character = username end
    local okId, cid = pcall(playerBridge.getIdentifier, src)
    return character, okId and cid or nil, username
end

---Public actor resolver, so a caller building a multi-player line (e.g. a whole crew) can format each
---member itself. Returns character full name, citizenid (or nil), and account username.
---@param src integer player server id
---@return string character, string|nil cid, string username
audit.actor = actorOf

---Ship one audit event to the external log backend, subject to the master toggle and the
---per-event switch. A no-op when logging is disabled, this event is switched off, or no
---ox:logger backend is configured - so it never errors on an unconfigured server. For a player
---source the line is enriched with a readable actor - "Character Name (Username) [cid ... | id ...]" -
---both in the message and as queryable metadata; system events (nil/'system' source) pass through unchanged.
---@param event string event key (matches configs/server/logs.lua Events)
---@param source integer|string|nil acting player server id, or nil/'system' for server events
---@param message string human-readable one-line summary
---@param data table? structured fields attached to the log
function audit.log(event, source, message, data)
    if not CFG.Enabled then return end
    if CFG.Events and CFG.Events[event] == false then return end
    if not logger then return end
    if type(source) == 'number' and source > 0 then
        local character, cid, username = actorOf(source)
        cid = cid or 'unknown'
        ---@type table enriched metadata: the call's own data plus the readable actor fields.
        local meta = {}
        if data then for k, v in pairs(data) do meta[k] = v end end
        meta.character, meta.username, meta.cid, meta.sid = character, username, cid, source
        logger(source, event, ('%s (%s) [cid %s | id %d]: %s'):format(character, username, cid, source, message), meta)
        return
    end
    logger(source or 'system', event, message, data)
end

-- One-time boot warning: logging is on but there is no backend to receive it, so audit is silently
-- off. Better the owner sees this than wonders why their sink is empty.
CreateThread(function()
    if CFG.Enabled and not logger then
        log.warn('audit', 'audit logging enabled but no ox:logger backend configured (set the ox:logger convar + service key); audit logs are OFF')
    end
end)

return audit
