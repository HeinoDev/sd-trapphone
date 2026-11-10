---@type table sd-trapphone config root (configs/config.lua).
local config = require 'configs.config'
---@type table Console log helper (shared.log).
local log = require 'shared.log'
---@type table Item label lookups (shared.items).
local items = require 'shared.items'
---@type table Audit-log helper (server.trapphone.audit).
local audit = require 'server.trapphone.audit'
---@type table Inventory bridge (bridge.server.inventory).
local inventory = require 'bridge.server.inventory'
---@type table Notify bridge (bridge.server.notify).
local notify = require 'bridge.server.notify'

---@type table Bagging config (config.Scales).
local CFG = config.Scales
---@type table<string, number> Grams in one of each unit (config.Scales.Weights).
local WEIGHTS = CFG.Weights

---@class TrapBagging
---@field from string source item
---@field to string item being bagged up
---@field qty integer source units on the scales
---@field out integer bags it makes
---@field rest integer grams left over, handed back as gram bags
---@field restItem string|nil the family's gram item, when the leftover is handed back
---@field drain integer battery percent it uses
---@field seconds integer how long the weighing takes
---@field slot any|nil the scales' inventory slot, when the backend has slots
---@field ends integer os.time() the weighing is done

---@type table Scales module; the table returned at end of file. Bagging up: breaking a bigger
---unit of a product into smaller ones, on scales that run on batteries.
local scales = {}

---@type integer Most source units weighed in one go.
local MAX_PER_RUN = 20
---@type integer Milliseconds between two scales requests from one player.
local PACE_MS = 400

---@type table<string, table<string, string>> Item name by family then unit, from config.Drugs.Items.
local itemOf = {}

for item, info in pairs(config.Drugs.Items) do
    itemOf[info.family] = itemOf[info.family] or {}
    itemOf[info.family][info.unit] = item
end

---@type table<integer, TrapBagging> The weighing each player has running, by server id.
local jobs = {}
---@type table<integer, integer> GetGameTimer() of each player's last scales request.
local pace = {}

---Whether a request arrives too soon after the player's last one.
---@param src integer player server id
---@return boolean tooSoon
local function tooSoon(src)
    local now = GetGameTimer()

    if now - (pace[src] or -PACE_MS) < PACE_MS then return true end

    pace[src] = now

    return false
end

---The charge stored on a scales item (a fresh set is full).
---@param stack table { slot, count, metadata }
---@return number battery 0..100
local function batteryOf(stack)
    local value = stack.metadata and tonumber(stack.metadata.battery)

    return value and math.max(0, math.min(100, value)) or 100
end

---The scales a player means: the slot they used when it holds scales, else the fullest set.
---@param src integer player server id
---@param slot any|nil slot the client says was used
---@return table|nil stack { slot, count, metadata }
local function findScales(src, slot)
    local stacks = inventory.getSlots(src, CFG.Item)
    local best

    for i = 1, #stacks do
        if slot ~= nil and stacks[i].slot == slot then return stacks[i] end
        if not best or batteryOf(stacks[i]) > batteryOf(best) then best = stacks[i] end
    end

    return best
end

---The baggie item a unit is packed in.
---@param unit string a key of config.Scales.Weights
---@return string item
local function baggieFor(unit)
    return unit == 'ounce' and CFG.LargeBaggiesItem or CFG.SmallBaggiesItem
end

---Work out one split: what `qty` units of `from` make when bagged as `to`.
---@param from string source item
---@param to string target item
---@param qty integer source units
---@return TrapBagging|nil plan nil when the two items are not a configured split
local function plan(from, to, qty)
    local source, target = config.Drugs.Items[from], config.Drugs.Items[to]

    if not source or not target or source.family ~= target.family then return nil end

    local seconds = CFG.Splits[source.unit] and CFG.Splits[source.unit][target.unit]
    local fromGrams, toGrams = WEIGHTS[source.unit], WEIGHTS[target.unit]

    if not seconds or not fromGrams or not toGrams or toGrams >= fromGrams then return nil end

    local grams = fromGrams * qty
    local out = grams // toGrams
    local rest = grams - out * toGrams
    local restItem = itemOf[source.family].gram

    if not CFG.ReturnRemainderAsGrams or not restItem or target.unit == 'gram' then rest, restItem = 0, nil end

    return {
        from = from,
        to = to,
        qty = qty,
        out = math.floor(out),
        rest = math.floor(rest),
        restItem = rest > 0 and restItem or nil,
        drain = CFG.Battery.Enabled and (CFG.Battery.DrainPerSourceUnit[source.unit] or 0) * qty or 0,
        seconds = seconds * qty,
        ends = 0,
    }
end

---The baggies a plan uses up, by baggie item (empty when baggies are off).
---@param job TrapBagging
---@return table<string, integer> needed
local function baggiesFor(job)
    local needed = {}
    if not CFG.UseBaggies then return needed end

    local item = baggieFor(config.Drugs.Items[job.to].unit)

    needed[item] = job.out

    if job.rest > 0 then
        local small = baggieFor('gram')
        needed[small] = (needed[small] or 0) + job.rest
    end

    return needed
end

---Check a plan against what the player has right now: the product, the charge, the baggies.
---@param src integer player server id
---@param job TrapBagging
---@param stack table the scales stack
---@return string|nil error localized reason it can't go ahead, nil when it can
local function shortOf(src, job, stack)
    if inventory.count(src, job.from) < job.qty then return locale('scales.not_enough', items.label(job.from)) end
    if job.drain > 0 and batteryOf(stack) < job.drain then return locale('scales.battery_low') end

    for item, count in pairs(baggiesFor(job)) do
        if inventory.count(src, item) < count then return locale('scales.no_baggies', count, items.label(item)) end
    end

    return nil
end

---Every split a player could do with what they hold, for the picker.
---@param src integer player server id
---@return table[] list { from, fromLabel, to, toLabel, have, max, per, rest, seconds, drain }
local function options(src)
    local list = {}

    for from, source in pairs(config.Drugs.Items) do
        local splits = CFG.Splits[source.unit]
        local have = splits and inventory.count(src, from) or 0

        if have > 0 then
            for unit in pairs(splits) do
                local to = itemOf[source.family][unit]
                local one = to and plan(from, to, 1)

                if one then
                    list[#list + 1] = {
                        from = from,
                        fromLabel = items.label(from),
                        to = to,
                        toLabel = items.label(to),
                        have = have,
                        max = math.min(have, MAX_PER_RUN),
                        per = one.out,
                        rest = one.rest,
                        seconds = one.seconds,
                        drain = one.drain,
                    }
                end
            end
        end
    end

    table.sort(list, function(a, b)
        if a.fromLabel ~= b.fromLabel then return a.fromLabel < b.fromLabel end
        return a.per < b.per
    end)

    return list
end

---Put a fresh battery in a player's flattest scales.
---@param src integer player server id
---@return boolean replaced
---@return string message localized outcome
function scales.replaceBattery(src)
    if not CFG.Enabled or not CFG.Battery.Enabled then return false, locale('scales.battery_off') end
    if jobs[src] then return false, locale('scales.busy') end

    local stacks = inventory.getSlots(src, CFG.Item)
    local flattest

    for i = 1, #stacks do
        if stacks[i].slot ~= nil and (not flattest or batteryOf(stacks[i]) < batteryOf(flattest)) then flattest = stacks[i] end
    end

    if not flattest then return false, locale('scales.no_scales') end
    if batteryOf(flattest) >= CFG.Battery.ReplaceTo then return false, locale('scales.battery_full') end
    if not inventory.remove(src, CFG.BatteryItem, 1) then return false, locale('scales.no_batteries') end

    local meta = flattest.metadata or {}

    meta.battery = CFG.Battery.ReplaceTo

    if not inventory.setMetadata(src, flattest.slot, meta, CFG.Item) then
        -- This inventory can't store a charge on an item, so the scales never run down either.
        inventory.add(src, CFG.BatteryItem, 1)
        return false, locale('scales.battery_full')
    end

    return true, locale('scales.battery_replaced')
end

-- The picker: what this player can split right now and how much charge the scales have.
lib.callback.register('sd-trapphone:server:scalesOptions', function(src, slot)
    if not CFG.Enabled then return { ok = false, error = locale('scales.disabled') } end
    if tooSoon(src) then return { ok = false, error = locale('scales.slow_down') } end

    local stack = findScales(src, slot)
    if not stack then return { ok = false, error = locale('scales.no_scales') } end

    return { ok = true, data = { battery = CFG.Battery.Enabled and math.floor(batteryOf(stack)) or nil, splits = options(src), baggies = CFG.UseBaggies } }
end)

-- Start weighing. Nothing moves yet: the swap happens when the wait is over.
lib.callback.register('sd-trapphone:server:scalesStart', function(src, slot, from, to, qty)
    if not CFG.Enabled then return { ok = false, error = locale('scales.disabled') } end
    if tooSoon(src) then return { ok = false, error = locale('scales.slow_down') } end
    if jobs[src] then return { ok = false, error = locale('scales.busy') } end

    if type(from) ~= 'string' or type(to) ~= 'string' or type(qty) ~= 'number' or qty ~= math.floor(qty)
        or qty < 1 or qty > MAX_PER_RUN then
        return { ok = false, error = locale('scales.invalid') }
    end

    local job = plan(from, to, qty)

    if not job then
        audit.log('suspect', src, 'asked the scales for a split that does not exist', { from = from, to = to, qty = qty })
        return { ok = false, error = locale('scales.invalid') }
    end

    local stack = findScales(src, slot)
    if not stack then return { ok = false, error = locale('scales.no_scales') } end

    local short = shortOf(src, job, stack)
    if short then return { ok = false, error = short } end

    job.slot = stack.slot
    job.ends = os.time() + job.seconds
    jobs[src] = job

    return { ok = true, data = { seconds = job.seconds, out = job.out, rest = job.rest } }
end)

-- The weighing is done: take the big unit, hand over the bags, drain the battery.
lib.callback.register('sd-trapphone:server:scalesFinish', function(src)
    local job = jobs[src]
    if not job then return { ok = false, error = locale('scales.invalid') } end

    jobs[src] = nil

    if os.time() < job.ends - 1 then
        audit.log('suspect', src, 'finished bagging before the scales were done', { left = job.ends - os.time(), from = job.from, qty = job.qty })
        return { ok = false, error = locale('scales.invalid') }
    end

    local stack = findScales(src, job.slot)
    if not stack then return { ok = false, error = locale('scales.no_scales') } end

    local short = shortOf(src, job, stack)
    if short then return { ok = false, error = short } end

    if not inventory.canCarry(src, job.to, job.out) then return { ok = false, error = locale('scales.cant_carry') } end
    if not inventory.remove(src, job.from, job.qty) then return { ok = false, error = locale('scales.not_enough', items.label(job.from)) } end

    local ok, given = pcall(inventory.add, src, job.to, job.out)

    if not ok or not given then
        inventory.add(src, job.from, job.qty)
        return { ok = false, error = locale('scales.cant_carry') }
    end

    -- The leftover is a bonus: if it won't fit it is lost as shake, like the config says.
    if job.rest > 0 and job.restItem then
        local fits, added = pcall(inventory.add, src, job.restItem, job.rest)
        if not fits or not added then job.rest = 0 end
    end

    for item, count in pairs(baggiesFor(job)) do
        inventory.remove(src, item, count)
    end

    local battery

    if job.drain > 0 and stack.slot ~= nil then
        local meta = stack.metadata or {}

        battery = math.max(0, math.floor(batteryOf(stack) - job.drain))
        meta.battery = battery

        if not inventory.setMetadata(src, stack.slot, meta, CFG.Item) then
            battery = nil
            log.debug('scales', 'inventory cannot store the charge; scales never run down here')
        end
    end

    audit.log('bagging', src, ('bagged %d x %s into %d x %s'):format(job.qty, items.display(job.from), job.out, items.display(job.to)),
        { from = job.from, to = job.to, qty = job.qty, out = job.out, rest = job.rest })

    return { ok = true, data = { out = job.out, rest = job.rest, toLabel = items.label(job.to), battery = battery } }
end)

-- Stopped early: nothing was taken, so there is nothing to give back.
lib.callback.register('sd-trapphone:server:scalesCancel', function(src)
    jobs[src] = nil

    return { ok = true }
end)

-- ox_inventory uses batteries through the client export (items.md); this is what it calls.
lib.callback.register('sd-trapphone:server:scalesBattery', function(src)
    if tooSoon(src) then return { ok = false, error = locale('scales.slow_down') } end

    local ok, message = scales.replaceBattery(src)

    return { ok = ok, error = not ok and message or nil, data = ok and { message = message } or nil }
end)

-- ox_inventory runs both items through their client exports (items.md). Every other inventory
-- registers them as usable here: the scales open the picker on the client, the batteries are
-- swapped straight away.
if CFG.Enabled and inventory.system ~= 'ox_inventory' then
    local ok, err = pcall(function()
        inventory.registerUsable(CFG.Item, function(src, item)
            TriggerClientEvent('sd-trapphone:client:useScales', src, type(item) == 'table' and item.slot or nil)
        end)

        if CFG.Battery.Enabled then
            inventory.registerUsable(CFG.BatteryItem, function(src)
                local replaced, message = scales.replaceBattery(src)

                notify.to(src, message, replaced and 'success' or 'error')
            end)
        end
    end)

    if not ok then log.warn('scales', 'could not register the scales as usable: %s', err) end
end

AddEventHandler('playerDropped', function()
    local src = source

    jobs[src] = nil
    pace[src] = nil
end)

return scales
