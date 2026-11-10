---@type table sd-trapphone config root (configs/config.lua).
local config = require 'configs.config'
---@type table Console log helper (shared.log).
local log = require 'shared.log'
---@type table Audit-log helper (server.trapphone.audit).
local audit = require 'server.trapphone.audit'
---@type table Live phones (server.trapphone.phones).
local phones = require 'server.trapphone.phones'
---@type table XP and levels (server.trapphone.progress).
local progress = require 'server.trapphone.progress'
---@type table Signed standing values (server.trapphone.relations).
local relations = require 'server.trapphone.relations'
---@type table Turf and gang standing (server.trapphone.turf).
local turf = require 'server.trapphone.turf'
---@type table Special contacts (server.trapphone.contacts).
local contacts = require 'server.trapphone.contacts'
---@type table Back-room services (server.trapphone.services).
local services = require 'server.trapphone.services'
---@type table Inventory bridge (bridge.server.inventory).
local inventory = require 'bridge.server.inventory'
---@type table Notify bridge (bridge.server.notify).
local notify = require 'bridge.server.notify'

-- Admin commands, all under one name:
--   /trapadmin give <id>
--   /trapadmin xp <id> <family> <set|add> <amount>
--   /trapadmin intro <id> [contact key]
--   /trapadmin gangrep <id> <gang> <value>
--   /trapadmin reset <id>
-- Allowed from the server console, or for anyone holding config.AdminAce.

---Whether a command source may run the admin commands. IsPlayerAceAllowed answers with the
---number 1 on some server builds and with true on others, so both count and nothing else does.
---@param src integer command source (0 = server console)
---@return boolean allowed
local function allowed(src)
    if src == 0 then return true end

    local answer = IsPlayerAceAllowed(src, config.AdminAce)

    return answer == true or answer == 1
end

---Answer whoever ran a command: a console line, or a notification.
---@param src integer command source
---@param text string
---@param ok? boolean false marks it as an error
local function reply(src, text, ok)
    if src == 0 then
        log.info('admin', text)
    else
        notify.to(src, text, ok == false and 'error' or 'success')
    end
end

---An online player's server id from a command argument.
---@param arg string|nil
---@return integer|nil target
local function targetOf(arg)
    local id = tonumber(arg)
    if not id or id ~= math.floor(id) or id < 1 or not GetPlayerName(id) then return nil end

    return id
end

---The phone a target carries.
---@param target integer player server id
---@return table|nil phone TrapPhone
local function phoneOf(target)
    return phones.current(target) or phones.active(target)
end

---@type table<string, fun(src: integer, args: string[]): boolean, string> Sub-commands.
---Each returns whether it worked and the line to answer with.
local commands = {}

---Give a player a trap phone.
function commands.give(_, args)
    local target = targetOf(args[2])
    if not target then return false, locale('admin.no_player') end

    local item = config.Phone.Item

    -- An optional colour: /trapadmin give <id> cherry
    for name, shell in pairs(config.Phone.Items) do
        if shell == args[3] then item = name end
    end

    if not inventory.canCarry(target, item, 1) or not inventory.add(target, item, 1) then
        return false, locale('admin.give_failed')
    end

    return true, locale('admin.gave_phone', target)
end

---Set or add XP in a family on the phone a player carries.
function commands.xp(_, args)
    local target = targetOf(args[2])
    local family, mode, amount = args[3], args[4], tonumber(args[5])

    if not target then return false, locale('admin.no_player') end
    if not config.Drugs.Families[family] or (mode ~= 'set' and mode ~= 'add') or not amount then
        return false, locale('admin.usage_xp')
    end

    local phone = phoneOf(target)
    if not phone then return false, locale('admin.no_phone') end

    amount = math.floor(amount)

    if mode == 'add' and amount >= 0 then
        progress.add(phone, family, amount)
    elseif mode == 'add' then
        progress.remove(phone, family, -amount)
    else
        phone.data.xp[family] = math.max(0, amount)
        phones.touch(phone)
        phones.refresh(phone, 'rep')
    end

    return true, locale('admin.xp_done', target, family, phone.data.xp[family] or 0, progress.level(phone, family))
end

---Make a contact reach out to a player now, skipping the odds and the unlock rule.
function commands.intro(_, args)
    local target = targetOf(args[2])
    if not target then return false, locale('admin.no_player') end

    local phone = phoneOf(target)
    if not phone then return false, locale('admin.no_phone') end

    local ok, reason = contacts.introduce(phone, target, { key = args[3], force = true })
    if not ok then return false, locale('admin.intro_failed', reason or '?') end

    return true, locale('admin.intro_done', target)
end

---Set a player's standing with a crew (their job's, when the job shares one).
function commands.gangrep(_, args)
    local target = targetOf(args[2])
    local gang, value = args[3], tonumber(args[4])

    if not target then return false, locale('admin.no_player') end
    if not config.Gangs.List[gang] or not value then return false, locale('admin.usage_gangrep') end

    local owner = turf.ownerOf(target)
    if not owner then return false, locale('admin.no_player') end

    value = relations.set(owner, 'gang', gang, math.max(-100, math.min(100, value)))

    local phone = phones.current(target)
    if phone then phones.refresh(phone, 'turf') end

    return true, locale('admin.gangrep_done', owner, value, gang)
end

---Wipe the phone a player carries back to a fresh one. The number and the look are kept.
function commands.reset(_, args)
    local target = targetOf(args[2])
    if not target then return false, locale('admin.no_player') end

    local phone = phoneOf(target)
    if not phone then return false, locale('admin.no_phone') end

    local data = phone.data

    data.xp, data.contacts, data.threads, data.scores = {}, {}, {}, {}
    data.met, data.pending, data.ordered, data.tipped = {}, {}, nil, nil
    data.stats = { sales = 0, earned = 0, drops = 0 }
    data.spot = nil

    phones.touch(phone)
    phones.push(phone, phones.snapshot(target, phone))
    TriggerClientEvent('sd-trapphone:client:meets', target, {})
    services.sync(target)

    return true, locale('admin.reset_done', phone.id, target)
end

RegisterCommand('trapadmin', function(src, args, raw)
    if not allowed(src) then
        reply(src, locale('admin.denied'), false)
        return
    end

    local handler = commands[args[1] or '']

    if not handler then
        reply(src, locale('admin.usage'), false)
        return
    end

    local ok, worked, text = pcall(handler, src, args)

    if not ok then
        log.error('admin', '/%s failed: %s', raw, worked)
        reply(src, locale('admin.failed'), false)
        return
    end

    audit.log('admin_command', src == 0 and 'system' or src, ('ran /%s (%s)'):format(raw, worked and 'ok' or 'refused'),
        { command = args[1], args = args, ok = worked })
    reply(src, text, worked)
end, false)

-- Test commands, registered only while config.Debug is on and still behind the admin ace.
-- They act on whoever runs them, so they do nothing from the console.
if config.Debug then
    ---Register one debug command behind the same gate as the admin commands.
    ---@param name string command name
    ---@param fn fun(src: integer, args: string[]): string|nil returns the line to answer with
    local function debugCommand(name, fn)
        RegisterCommand(name, function(src, args, raw)
            if src == 0 or not allowed(src) then return end

            local ok, text = pcall(fn, src, args)

            if not ok then
                log.error('admin', '/%s failed: %s', raw, text)
                return
            end

            audit.log('admin_command', src, ('ran /%s'):format(raw), { command = name, args = args, debug = true })
            if text then reply(src, text) end
        end, false)
    end

    -- Where the server thinks you are standing, and what the crew there thinks of you.
    debugCommand('trap_zone', function(src)
        local snapshot = turf.snapshot(src)

        return ('%s (wealth %d) gang=%s standing=%s heat=%d'):format(snapshot.zone.label, snapshot.zone.wealth,
            snapshot.gang and snapshot.gang.id or 'none', snapshot.gang and snapshot.gang.standing or '-', snapshot.heat)
    end)

    -- /trap_encounter [tax|attack] [gang]: send a crew at yourself.
    debugCommand('trap_encounter', function(src, args)
        local kind = args[1] == 'attack' and 'attack' or 'tax'
        local gang = config.Gangs.List[args[2]] and args[2] or turf.zoneOf(src).gang or next(config.Gangs.List)

        return turf.startEncounter(src, gang, kind) and ('%s %s started'):format(gang, kind) or 'an encounter is already running'
    end)

    -- /trap_riot [gang]: one riot wave at yourself, without touching anyone's standing.
    debugCommand('trap_riot', function(src, args)
        local gang = config.Gangs.List[args[1]] and args[1] or turf.zoneOf(src).gang or next(config.Gangs.List)
        local wave = config.Gangs.Riot.MembersPerWave

        TriggerClientEvent('sd-trapphone:client:riotWave', src, { gang = gang, wave = 1, waves = 1, members = math.random(wave.min, wave.max) })

        return ('%s riot wave sent'):format(gang)
    end)

    -- /trap_level <family> <level>: put your phone at the start of a level.
    debugCommand('trap_level', function(src, args)
        local phone = phoneOf(src)
        local level = tonumber(args[2])

        if not phone or not config.Drugs.Families[args[1]] or not level then return 'usage: /trap_level <family> <level>' end

        local target = require('shared.levels').xpFor(math.max(1, math.min(config.Economy.XP.MaxLevel, math.floor(level))), config.Economy.XP)
        local have = phone.data.xp[args[1]] or 0

        if target > have then progress.add(phone, args[1], target - have) else progress.remove(phone, args[1], have - target) end

        return ('%s is now level %d'):format(args[1], progress.level(phone, args[1]))
    end)
end
