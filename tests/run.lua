-- sd-trapphone offline harness. Runs under stock Lua 5.4, no game and no server needed:
--   lua tests/run.lua        PASS/FAIL per test, exit code 0 only when everything passes
--   lua tests/run.lua -v     also print the resource's own console lines
-- It checks three things: that every Lua file of the street slice compiles once the CfxLua
-- syntax is rewritten, that the pure modules (pricing, levels, zones) hold their promises, and
-- that the server side of selling, drop-offs and dispatch behaves in a fake FiveM environment.
local here = (arg and arg[0] or 'run.lua'):gsub('\\', '/'):match('^(.*)/[^/]*$') or '.'
package.path = here .. '/?.lua;' .. package.path

local verbose = false
for _, a in ipairs(arg or {}) do
    if a == '-v' or a == '--verbose' then verbose = true end
end

local realPrint = print
print = function(...)
    if verbose then realPrint(...) end
end

local L = require 'loader'
local S = require 'stubs'

local passed, failed = 0, 0

local function test(name, fn)
    local ok, err = xpcall(fn, debug.traceback)

    if ok then
        passed = passed + 1
        realPrint('PASS  ' .. name)
    else
        failed = failed + 1
        realPrint('FAIL  ' .. name .. '\n      ' .. tostring(err):gsub('\n', '\n      '))
    end
end

local function check(cond, msg)
    if not cond then error('ASSERT: ' .. tostring(msg), 2) end
end

local function eq(got, want, msg)
    if got ~= want then
        error(('ASSERT: %s: expected %s, got %s'):format(msg, tostring(want), tostring(got)), 2)
    end
end

---A random source that walks a fixed list, for the pure functions.
local function seq(values)
    local i = 0
    return function()
        i = i % #values + 1
        return values[i]
    end
end

local function fixed(value)
    return function() return value end
end

-- ---------------------------------------------------------------------------------------------
-- 1. Every file compiles.
-- ---------------------------------------------------------------------------------------------

local FILES = {
    'shared/pricing.lua', 'shared/levels.lua', 'shared/zones.lua', 'shared/log.lua', 'shared/items.lua',
    'configs/config.lua', 'configs/server/dialogue.lua', 'configs/server/selling.lua',
    'configs/server/economy.lua', 'configs/server/dispatch.lua', 'configs/server/deliveries.lua',
    'configs/shared/selling.lua', 'configs/shared/zones.lua', 'configs/shared/drugs.lua',
    'server/trapphone/dispatch.lua', 'server/trapphone/selling.lua', 'server/trapphone/dropoffs.lua',
    'server/trapphone/phones.lua', 'server/trapphone/progress.lua', 'server/trapphone/relations.lua',
    'client/trapphone/world.lua', 'client/trapphone/selling.lua', 'client/trapphone/dropoffs.lua',
    'client/trapphone/dispatch.lua', 'client/trapphone/phone.lua',
}

test('syntax: every street-slice file compiles after desugaring', function()
    for _, rel in ipairs(FILES) do
        local chunk, err = L.compile(rel)
        check(chunk, ('%s: %s'):format(rel, tostring(err)))
    end
end)

test('loader: compound assignment is rewritten only where it is one', function()
    local out = L.preprocess('a += 1\nif x then t.n -= 2 end\nlocal s = "a <= b"\nq *= r + 1 -- note\nif a ~= b then end')
    local lines = {}
    for line in (out .. '\n'):gmatch('(.-)\n') do lines[#lines + 1] = line end

    eq(lines[1], 'a = a + (1)', 'plain statement')
    eq(lines[2], 'if x then t.n = t.n - (2) end', 'inside a one-line if')
    eq(lines[3], 'local s = "a <= b"', 'comparison in a string untouched')
    eq(lines[4], 'q = q * (r + 1) -- note', 'trailing comment kept outside')
    eq(lines[5], 'if a ~= b then end', 'inequality untouched')
    eq(L.preprocess('x = `prop_weed_bottle`'), 'x = joaat("prop_weed_bottle")', 'backtick hash')
end)

-- ---------------------------------------------------------------------------------------------
-- 2. Pure modules.
-- ---------------------------------------------------------------------------------------------

local config = require 'configs.config'
local pricing = require 'shared.pricing'
local levels = require 'shared.levels'
local zones = require 'shared.zones'

local ECON = config.Economy
local PERSONALITIES = config.Selling.Personalities

test('config: every priced item is a real product with sane bounds', function()
    local count = 0

    for item, entry in pairs(ECON.Prices) do
        count = count + 1

        local info = config.Drugs.Items[item]
        check(info, item .. ' is priced but not in config.Drugs.Items')
        check(config.Drugs.Families[info.family], item .. ' has an unknown family')
        check(config.Drugs.Units[info.unit], item .. ' has an unknown unit')
        check(entry.min <= entry.price and entry.price <= entry.max, item .. ' price outside its own min/max')
        check(entry.maxSale >= 1, item .. ' maxSale below 1')
    end

    check(count > 0, 'no prices configured')
end)

test('pricing.hash: stable, 32-bit, salt changes the answer', function()
    eq(pricing.hash('abc'), pricing.hash('abc'), 'same key twice')
    check(pricing.hash('abc') ~= pricing.hash('abd'), 'different keys collide')
    check(pricing.hash('abc', 'x') ~= pricing.hash('abc', 'y'), 'salt ignored')

    for i = 1, 500 do
        local h = pricing.hash('key' .. i)
        check(math.type(h) == 'integer' and h >= 0 and h <= 0xFFFFFFFF, 'hash out of range')
    end
end)

test('pricing.offer: always inside min/max, whole numbers, total = unit x qty', function()
    local rolls = { 0, 0.000001, 0.25, 0.5, 0.75, 0.999999 }
    local checked = 0

    for item, entry in pairs(ECON.Prices) do
        for wealth = 0, 5 do
            for _, relationship in ipairs({ -100, -40, 0, 40, 100, 250, -250 }) do
                for _, level in ipairs({ 1, 2, 7, 20, 99 }) do
                    for _, bonus in ipairs({ 1, config.Deliveries.PriceBonus, 5 }) do
                        for _, roll in ipairs(rolls) do
                            for qty = 1, entry.maxSale + 1 do
                                local offer = pricing.offer({
                                    entry = entry, qty = qty, economy = ECON, wealth = wealth,
                                    relationship = relationship, level = level, bonus = bonus,
                                }, fixed(roll))

                                check(math.type(offer.unit) == 'integer', item .. ' unit is not an integer')
                                check(math.type(offer.total) == 'integer', item .. ' total is not an integer')
                                check(offer.unit >= entry.min and offer.unit <= entry.max,
                                    ('%s unit %d outside %d..%d'):format(item, offer.unit, entry.min, entry.max))
                                eq(offer.total, offer.unit * qty, item .. ' total')
                                checked = checked + 1
                            end
                        end
                    end
                end
            end
        end
    end

    check(checked > 10000, 'too few combinations checked')
end)

test('pricing.offer: demand, relationship, level and bonus all push the right way', function()
    -- A wide clamp so the modifiers are visible rather than flattened by min/max.
    local entry = { price = 1000, min = 1, max = 100000, maxSale = 5, demand = { 3 } }
    local mid = fixed(0.5)
    local function unit(opts)
        opts.entry, opts.qty, opts.economy = entry, 1, ECON
        return pricing.offer(opts, mid).unit
    end

    eq(unit({ wealth = 0 }), 1000, 'neutral offer at the middle of the spread is the base price')
    eq(unit({ wealth = 3 }), math.floor(1000 * ECON.DemandBonus + 0.5), 'demand zone')
    check(pricing.offer({ entry = entry, qty = 1, economy = ECON, wealth = 3 }, mid).demand == true, 'demand flag')
    check(unit({ relationship = 100 }) > unit({ relationship = 0 }), 'good relationship pays more')
    check(unit({ relationship = -100 }) < unit({ relationship = 0 }), 'bad relationship pays less')
    eq(unit({ relationship = 100 }), math.floor(1000 * (1 + ECON.RelationshipBonus) + 0.5), 'relationship bonus size')
    check(unit({ level = 5 }) > unit({ level = 1 }), 'level pays')
    eq(unit({ level = 500 }), math.floor(1000 * (1 + ECON.LevelBonusCap) + 0.5), 'level bonus is capped')
    check(unit({ bonus = 1.15 }) > unit({}), 'flat bonus pays')

    local low = pricing.offer({ entry = entry, qty = 1, economy = ECON }, fixed(0)).unit
    local high = pricing.offer({ entry = entry, qty = 1, economy = ECON }, fixed(0.999999)).unit
    eq(low, math.floor(1000 * (1 - ECON.OfferSpread) + 0.5), 'bottom of the spread')
    check(high > 1000 and high <= math.floor(1000 * (1 + ECON.OfferSpread) + 0.5), 'top of the spread')
end)

test('pricing.quantity: 1..maxSale, never more than held, multiplier rounds up', function()
    local entry = { maxSale = 5 }

    eq(pricing.quantity(entry, 0, fixed(0.5)), 0, 'nothing held')
    eq(pricing.quantity(entry, 99, fixed(0)), 1, 'lowest roll')
    eq(pricing.quantity(entry, 99, fixed(0.999999)), 5, 'highest roll')
    eq(pricing.quantity(entry, 2, fixed(0.999999)), 2, 'capped by stock')
    eq(pricing.quantity(entry, 99, fixed(0.999999), 1.5), 8, 'ceil(5 x 1.5)')

    for i = 0, 100 do
        local qty = pricing.quantity(entry, 3, fixed(i / 101))
        check(qty >= 1 and qty <= 3 and math.type(qty) == 'integer', 'quantity out of range')
    end
end)

test('pricing.personality: deterministic, order-independent, weighted', function()
    local names = {}
    for name in pairs(PERSONALITIES) do names[#names + 1] = name end
    table.sort(names)

    -- The same table built in the opposite insertion order must give the same answers.
    local reversed = {}
    for i = #names, 1, -1 do reversed[names[i]] = PERSONALITIES[names[i]] end

    local counts, total, n = {}, 0, 30000

    for _, name in ipairs(names) do
        counts[name] = 0
        total = total + PERSONALITIES[name].weight
    end

    for i = 1, n do
        local key = ('%08x-%d-%d'):format(i * 7919, i % 5, i % 3)
        local name, row = pricing.personality(key, PERSONALITIES)

        check(PERSONALITIES[name] == row, 'returned row does not match the name')
        eq(pricing.personality(key, PERSONALITIES), name, 'same key twice')
        eq(pricing.personality(key, reversed), name, 'insertion order changed the pick')
        counts[name] = counts[name] + 1
    end

    for _, name in ipairs(names) do
        local share, want = counts[name] / n, PERSONALITIES[name].weight / total
        check(math.abs(share - want) < 0.02, ('%s picked %.3f of the time, weight says %.3f'):format(name, share, want))
    end

    eq(pricing.personality('x', {}), nil, 'empty table')
    eq(pricing.personality('x', { only = { weight = 0 } }), 'only', 'zero weights still pick someone')
end)

test('pricing.customerName / customerNumber: stable, well-formed, off the burner prefix', function()
    local prefix = config.Phone.NumberPrefix
    local seen, distinct = {}, 0

    for i = 1, 2000 do
        local key = ('%08x-%d-%d'):format(i * 104729, i % 4, i % 2)
        local name, number = pricing.customerName(key), pricing.customerNumber(key, prefix)

        check(type(name) == 'string' and #name >= 2 and #name <= 24, 'name length: ' .. tostring(name))
        eq(pricing.customerName(key), name, 'name is stable')
        eq(pricing.customerNumber(key, prefix), number, 'number is stable')
        check(number:match('^%d%d%d%-%d%d%d%d$'), 'number format: ' .. number)
        check(number:sub(1, 3) ~= prefix, 'number under the burner prefix: ' .. number)

        if not seen[number] then
            seen[number] = true
            distinct = distinct + 1
        end
    end

    check(distinct > 1950, ('only %d distinct numbers out of 2000 keys'):format(distinct))
end)

test('pricing.haggleChance: 1 at the offer, falls as the ask climbs, 0 at the limit', function()
    local haggle = ECON.Haggle
    local offer, ceiling = 1000, 100000

    for name, row in pairs(PERSONALITIES) do
        for _, relationship in ipairs({ -100, 0, 100 }) do
            local last = 1.0

            for ask = offer - 50, offer * 2, 5 do
                local chance = pricing.haggleChance({
                    offer = offer, ask = ask, ceiling = ceiling, haggle = haggle,
                    shift = row.haggle, relationship = relationship,
                    relationshipShift = config.Selling.Relationship.HaggleShift,
                })

                check(chance >= 0 and chance <= 1, name .. ' chance outside 0..1')
                check(chance <= last + 1e-9, ('%s chance rose from %.3f to %.3f at ask %d'):format(name, last, chance, ask))
                if ask <= offer then eq(chance, 1.0, 'asking no more than the offer') end
                if ask >= offer * (1 + haggle.MaxMarkup) then eq(chance, 0.0, 'at or past MaxMarkup') end
                last = chance
            end
        end
    end

    local base = { offer = 1000, ask = 1100, haggle = haggle }
    local plain = pricing.haggleChance(base)
    check(math.abs(plain - haggle.BaseChance * (1 - 0.1 / haggle.MaxMarkup)) < 1e-9, 'straight-line value at +10%')

    local liked = pricing.haggleChance({ offer = 1000, ask = 1100, haggle = haggle, relationship = 100, relationshipShift = 0.15 })
    local hated = pricing.haggleChance({ offer = 1000, ask = 1100, haggle = haggle, relationship = -100, relationshipShift = 0.15 })
    check(liked > plain and hated < plain, 'relationship shifts the chance both ways')

    eq(pricing.haggleChance({ offer = 1000, ask = 1100, ceiling = 1050, haggle = haggle }), 0.0, 'over the ceiling')
    eq(pricing.ceiling({ max = 100 }, 7), 700, 'ceiling is max x qty')
end)

test('pricing.refuseChance / tip / between / chance', function()
    eq(pricing.refuseChance(40, 0), 40, 'neutral ped')
    eq(pricing.refuseChance(40, 100), 0, 'best relationship')
    eq(pricing.refuseChance(40, -100), 80, 'worst relationship')
    eq(pricing.refuseChance(80, -100), 100, 'clamped at 100')
    eq(pricing.refuseChance(40, 40, 40), 0, 'a regular never refuses')

    local last = 101
    for relationship = -100, 100, 10 do
        local chance = pricing.refuseChance(40, relationship)
        check(chance <= last, 'refusal rose with relationship')
        last = chance
    end

    eq(pricing.tip(1000, { tip = 0 }, 0.1, fixed(0)), 0, 'a personality that never tips')
    eq(pricing.tip(1000, { tip = 0.3 }, 0.1, fixed(0.29)), 100, 'tip is the share of the sale')
    eq(pricing.tip(1000, { tip = 0.3 }, 0.1, fixed(0.3)), 0, 'roll at the odds does not tip')
    eq(pricing.tip(3, { tip = 1 }, 0.1, fixed(0)), 1, 'a tip is at least one')
    eq(pricing.tip(1000, nil, 0.1, fixed(0)), 0, 'no personality')

    for i = 0, 200 do
        local value = pricing.between(fixed(i / 201), 3, 9)
        check(value >= 3 and value <= 9 and math.type(value) == 'integer', 'between out of range')
    end

    eq(pricing.between(fixed(0.5), 5, 5), 5, 'single value range')
    eq(pricing.between(fixed(0.5), 9, 3), 9, 'inverted range returns min')
    check(pricing.chance(fixed(0.049), 5) and not pricing.chance(fixed(0.05), 5), 'chance boundary')
end)

test('dialogue: 250+ lines, every one formats with its placeholders in order', function()
    local dialogue = config.Dialogue
    local priced = { offer = true, drop_order = true }
    local single = { counter_ok = true, counter_no = true }
    local total = 0

    for _, moment in ipairs({ 'offer', 'accept', 'counter_ok', 'counter_no', 'decline', 'thanks', 'walked',
        'refused', 'robbery', 'drop_order', 'drop_accept', 'drop_thanks', 'drop_late', 'regular' }) do
        check(type(dialogue[moment]) == 'table', 'missing moment ' .. moment)
        check(type(dialogue[moment].default) == 'table' and #dialogue[moment].default > 0, moment .. ' has no default lines')
    end

    for moment, pools in pairs(dialogue) do
        for who, lines in pairs(pools) do
            check(who == 'default' or PERSONALITIES[who], ('%s.%s is not a personality'):format(moment, who))

            for _, line in ipairs(lines) do
                total = total + 1
                check(type(line) == 'string' and #line > 0 and #line <= 160, 'bad line in ' .. moment)
                check(not line:find('\226\128\148', 1, true), 'em dash in: ' .. line)

                local specs = {}
                for spec in line:gsub('%%%%', ''):gmatch('%%(%a)') do specs[#specs + 1] = spec end

                local want = priced[moment] and { 'd', 's', 's', 'd' } or single[moment] and { 'd' } or {}
                check(#specs <= #want, ('%s line has too many placeholders: %s'):format(moment, line))

                for i = 1, #specs do
                    eq(specs[i], want[i], ('placeholder %d of "%s"'):format(i, line))
                end

                local ok, text
                if priced[moment] then
                    ok, text = pcall(string.format, line, 7, 'UNIT', 'PRODUCT', 4242)
                else
                    ok, text = pcall(string.format, line, 4242)
                end

                check(ok, 'format failed: ' .. line)

                for amount in text:gmatch('%$(%d+)') do
                    eq(amount, '4242', 'the dollar amount in "' .. line .. '"')
                end
            end
        end
    end

    check(total >= 250, ('only %d dialogue lines'):format(total))

    local line = pricing.say(dialogue, 'offer', 'tight', fixed(0.3), 3, 'g', 'weed', 150)
    check(#line > 0 and line:find('150', 1, true) and not line:find('%%d'), 'pricing.say did not fill the line: ' .. line)
    eq(pricing.say(dialogue, 'no_such_moment', 'tight', fixed(0.3)), '', 'unknown moment')
    check(#pricing.say(dialogue, 'robbery', 'no_such_personality', fixed(0.9)) > 0, 'unknown personality falls back to default')
    eq(pricing.say({ m = { default = { 'needs %d' } } }, 'm', nil, fixed(0)), 'needs %d', 'a line short of arguments comes back raw')
end)

test('levels: curve boundaries, cap, progress, gain and loss', function()
    local XP = ECON.XP

    eq(levels.fromXp(0, XP), 1, 'no xp')
    eq(levels.fromXp(nil, XP), 1, 'nil xp')
    eq(levels.fromXp(-500, XP), 1, 'negative xp')
    eq(levels.xpFor(1, XP), 0, 'level 1 costs nothing')
    eq(levels.xpFor(2, XP), XP.LevelStep, 'level 2 costs one step')
    eq(levels.xpFor(4, XP), XP.LevelStep * 6, 'level 4 costs 1+2+3 steps')

    for level = 2, XP.MaxLevel do
        local need = levels.xpFor(level, XP)
        eq(levels.fromXp(need, XP), level, 'exactly enough for level ' .. level)
        eq(levels.fromXp(need - 1, XP), level - 1, 'one short of level ' .. level)
        check(math.type(need) == 'integer', 'xpFor is not a whole number')
    end

    eq(levels.fromXp(levels.xpFor(XP.MaxLevel, XP) * 100, XP), XP.MaxLevel, 'capped at MaxLevel')

    local last = 1
    for xp = 0, levels.xpFor(XP.MaxLevel, XP) + 5000, 137 do
        local level = levels.fromXp(xp, XP)
        check(level >= last and level <= XP.MaxLevel, 'level went down as xp rose')
        last = level

        local progress = levels.progress(xp, XP)
        check(progress >= 0 and progress <= 1, 'progress outside 0..1')
        if level < XP.MaxLevel then check(progress < 1, 'progress hit 1 below max level') end
    end

    eq(levels.progress(levels.xpFor(3, XP), XP), 0.0, 'start of a level')
    eq(levels.progress(levels.xpFor(3, XP) + XP.LevelStep * 3 / 2, XP), 0.5, 'half way through level 3')
    eq(levels.progress(levels.xpFor(XP.MaxLevel, XP), XP), 1.0, 'max level reads full')

    local gain, loss = math.huge, 0
    for level = 1, XP.MaxLevel do
        local g, l = levels.gain(level, XP), levels.loss(level, XP)
        check(g <= gain and g >= XP.GainMin, 'gain should thin out but never below GainMin')
        check(l >= loss and l <= XP.LossMax, 'loss should grow but never past LossMax')
        gain, loss = g, l
    end

    eq(levels.gain(1, XP), XP.GainBase, 'gain at level 1')
    eq(levels.gain(XP.MaxLevel, XP), math.max(XP.GainMin, XP.GainBase // XP.MaxLevel), 'gain at max level')
    eq(levels.loss(1, XP), XP.LossBase, 'loss at level 1')
    eq(levels.loss(XP.MaxLevel, XP), XP.LossMax, 'loss at max level')

    local titles = ECON.Titles
    eq(levels.title(1, titles), 'Nobody', 'title at 1')
    eq(levels.title(3, titles), 'Corner boy', 'title between steps')
    eq(levels.title(4, titles), 'Runner', 'title on a step')
    eq(levels.title(20, titles), 'Kingpin', 'top title')
    eq(levels.title(0, titles), '', 'below every title')
end)

test('zones: smallest containing circle wins, default outside, lookups', function()
    local areas, default = config.Zones.Areas, config.Zones.Default

    eq(zones.at(20000.0, 20000.0), default, 'far outside everything')
    eq(zones.at(-3000.0, -5000.0), default, 'out at sea')

    -- Brute-force oracle over a grid: whatever zones.at returns must contain the point and no
    -- smaller area may contain it.
    local inside, outside = 0, 0

    for x = -3500, 4000, 150 do
        for y = -3500, 7500, 150 do
            local zone = zones.at(x, y)
            local smallest

            for _, area in ipairs(areas) do
                local dx, dy = x - area.center.x, y - area.center.y
                if dx * dx + dy * dy <= area.radius * area.radius and (not smallest or area.radius < smallest.radius) then
                    smallest = area
                end
            end

            if smallest then
                inside = inside + 1
                eq(zone.radius, smallest.radius, ('zone at %d,%d'):format(x, y))
            else
                outside = outside + 1
                eq(zone, default, ('default at %d,%d'):format(x, y))
            end
        end
    end

    check(inside > 50 and outside > 50, 'grid did not cover both cases')

    -- Rancho's centre is inside Davis too; Rancho is the smaller circle.
    eq(zones.at(360.0, -2040.0).id, 'rancho', 'overlap resolves to the smaller area')

    -- A tight block fully inside a wide district.
    local wide = { id = 't_wide', label = 'Wide', center = vec2(9000.0, 9000.0), radius = 500.0, wealth = 1 }
    local tight = { id = 't_tight', label = 'Tight', center = vec2(9100.0, 9000.0), radius = 60.0, wealth = 5, gang = 'ballas' }

    areas[#areas + 1] = wide
    areas[#areas + 1] = tight

    eq(zones.at(9100.0, 9000.0).id, 't_tight', 'inside the nested circle')
    eq(zones.at(9100.0, 9060.0).id, 't_tight', 'exactly on the nested circle edge')
    eq(zones.at(9100.0, 9060.5).id, 't_wide', 'just outside the nested circle')
    eq(zones.at(9000.0, 9500.0).id, 't_wide', 'exactly on the outer edge')
    eq(zones.at(9000.0, 9500.5), default, 'just outside the outer edge')
    eq(zones.get('t_tight'), tight, 'get by id')

    areas[#areas] = nil
    areas[#areas] = nil

    for _, area in ipairs(areas) do
        eq(zones.get(area.id), area, 'get ' .. area.id)
        check(zones.at(area.center.x, area.center.y).radius <= area.radius, area.id .. ' centre resolves to something larger')
        check(area.wealth >= 0 and area.wealth <= 5, area.id .. ' wealth outside 0..5')
        check(area.gang == nil or config.Gangs.List[area.gang], area.id .. ' names an unknown gang')
    end

    eq(zones.get(default.id), default, 'get the default zone')
    eq(zones.get('nowhere'), nil, 'unknown id')
    eq(zones.wealthLabel(0), 'Broke', 'wealth 0 label')
    eq(zones.wealthLabel(5), 'Loaded', 'wealth 5 label')
    eq(zones.wealthLabel(9), '9', 'unknown wealth falls back to the number')
end)

test('locales: every key the street slice uses exists in en.json', function()
    local used = 0

    for _, rel in ipairs({ 'server/trapphone/dispatch.lua', 'server/trapphone/selling.lua', 'server/trapphone/dropoffs.lua',
        'client/trapphone/selling.lua', 'client/trapphone/dropoffs.lua', 'client/trapphone/dispatch.lua' }) do
        local src = L.readFile(L.resource .. '/' .. rel)

        for key in src:gmatch("'([%l]+%.[%w_]+)'") do
            local section = key:match('^(%l+)%.')

            if (section == 'selling' or section == 'dropoffs' or section == 'dispatch') and key:sub(-1) ~= '_' then
                used = used + 1
                check(S.strings[key], ('%s uses locale key %s which is not in locales/en.json'):format(rel, key))
            end
        end
    end

    check(used > 40, 'the scan found too few keys to be working')

    for _, reason in ipairs({ 'snitch', 'witness', 'sale', 'wash' }) do
        check(S.strings['dispatch.reason_' .. reason], 'missing dispatch.reason_' .. reason)
    end
end)

-- ---------------------------------------------------------------------------------------------
-- 3. The server side in a fake FiveM.
-- ---------------------------------------------------------------------------------------------

S.addPlayer(1, { name = 'Seller', x = 0.0, y = 0.0 })
S.addPlayer(2, { name = 'Driver', x = 10.0, y = 0.0 })
S.addPlayer(3, { name = 'Other', x = 500.0, y = 500.0 })

local phones = require 'server.trapphone.phones'
local progress = require 'server.trapphone.progress'
local relations = require 'server.trapphone.relations'
local dispatch = require 'server.trapphone.dispatch'
local selling = require 'server.trapphone.selling'
local dropoffs = require 'server.trapphone.dropoffs'

local PHONE = config.Phone.Item
local MIN_SERVE = config.Selling.MinServeSeconds
local LOOK = '9f2a01c4-1-0'

S.pump() -- run every server thread up to its first Wait

-- Rolls land in the middle of their range unless a test says otherwise: no robbery, no tip,
-- no snitch, a walking customer, a pitch that is not refused.
S.force = 0.5

---Call a callback a little later than the last one, so the rate limiter never interferes.
local function call(name, src, ...)
    S.advance(2)
    return S.call(name, src, ...)
end

local function give(src, item, count)
    S.players[src].items[item] = count
end

---Stop anything a player has going and hand them a clean stock.
local function reset(src, stock)
    S.advance(400)
    S.call('hustleStop', src)

    local p = S.players[src]
    p.items = { [PHONE] = 1 }
    p.vehicle, p.cash, p.bank, p.black = 0, 0, 0, 0

    for item, count in pairs(stock or {}) do p.items[item] = count end
end

---Start a corner and bring a customer as far as a texted offer.
local function customer(src, look)
    local start = call('hustleStart', src, 'corner', 'any')
    check(start.ok, 'start failed: ' .. tostring(start.error))

    S.advance(15)

    local req = call('requestCustomer', src)
    check(req.ok, 'no customer: wait ' .. tostring(req.wait))

    local res = call('customerLook', src, req.ticketId, look or LOOK)
    check(res.ok, 'look refused: ' .. tostring(res.error))

    return res, req
end

test('selling: start validates mode, family, phone, stock and being on foot', function()
    reset(1)

    eq(call('hustleStart', 1, 'nonsense', 'any').ok, false, 'unknown mode')
    eq(call('hustleStart', 1, 'corner', 'sugar').ok, false, 'unknown family')
    eq(call('hustleStart', 1, 'corner', { 'weed' }).ok, false, 'family of the wrong type')
    eq(call('hustleStart', 1, 'corner', 'any').error, S.strings['selling.nothing_to_sell'], 'no stock')

    give(1, 'weedbaggy', 10)
    give(1, PHONE, 0)
    eq(call('hustleStart', 1, 'corner', 'any').error, S.strings['selling.no_phone'], 'no phone')

    give(1, PHONE, 1)
    eq(call('hustleStart', 1, 'corner', 'coke').error, S.strings['selling.nothing_to_sell'], 'stock of another family')

    S.players[1].vehicle = 77
    eq(call('hustleStart', 1, 'corner', 'any').error, S.strings['selling.on_foot'], 'corner from a car')
    S.players[1].vehicle = 0

    -- weed_1oz is npc = false: holding only that is holding nothing the street buys.
    give(1, 'weedbaggy', 0)
    give(1, 'weed_1oz', 3)
    eq(call('hustleStart', 1, 'corner', 'weed').ok, false, 'only a non-street item')

    give(1, 'weedbaggy', 10)
    local res = call('hustleStart', 1, 'corner', 'weed')

    check(res.ok, 'valid start refused: ' .. tostring(res.error))
    eq(res.data.mode, 'corner', 'hustle mode in the reply')
    eq(res.data.family, 'weed', 'hustle family in the reply')
    eq(res.data.spotSet, false, 'no spot yet')
    eq(selling.mode(1), 'corner', 'selling.mode')
    eq(selling.mode(3), 'idle', 'selling.mode for someone else')

    local weed
    for _, row in ipairs(res.data.products) do
        if row.family == 'weed' then weed = row end
    end
    check(weed and #weed.items == 2, 'products should list both weed items held')

    eq(call('hustleStop', 1).data.mode, 'idle', 'stopped')
    eq(selling.mode(1), 'idle', 'idle after stop')
end)

test('selling: a full corner sale takes the product, then pays, and tells everyone', function()
    reset(1, { weedbaggy = 10 })

    local mark = S.mark()
    local res, req = customer(1)
    local offer = res.offer
    local entry = ECON.Prices.weedbaggy

    eq(req.kind, 'corner', 'kind')
    eq(offer.kind, 'corner', 'offer kind')
    eq(offer.item, 'weedbaggy', 'offer item')
    eq(offer.state, 'open', 'offer state')
    eq(offer.unit, 'gram', 'offer unit key')
    eq(offer.counters, ECON.Haggle.MaxCounters, 'haggles available')
    check(offer.qty >= 1 and offer.qty <= entry.maxSale, 'quantity outside 1..maxSale')
    check(offer.price >= entry.min * offer.qty and offer.price <= entry.max * offer.qty, 'price outside min/max')
    check(res.number:match('^%d%d%d%-%d%d%d%d$'), 'customer number')
    eq(res.serveAfter, MIN_SERVE, 'serveAfter')

    local texts = S.events('sd-trapphone:client:message', 1, mark)
    eq(#texts, 1, 'one text for the offer')
    eq(texts[1].payload.msg.offer.ticketId, offer.ticketId, 'the offer rides on the text')
    check(#texts[1].payload.msg.text > 0, 'the offer text is empty')

    eq(S.call('requestCustomer', 1).ok, false, 'no second customer while one is live')

    -- Too early: the server refuses and logs it.
    local logMark = #S.logs
    S.advance(1)
    local early = S.call('completeSale', 1, offer.ticketId)
    eq(early.ok, false, 'sale before MinServeSeconds')
    eq(#S.audit('suspect', logMark), 1, 'early completion is logged')
    eq(S.players[1].items.weedbaggy, 10, 'nothing taken on a refused sale')

    S.advance(MIN_SERVE)
    mark = S.mark()

    local done = S.call('completeSale', 1, offer.ticketId)
    check(done.ok, 'sale refused: ' .. tostring(done.error))
    eq(done.data.total, offer.price, 'total paid')
    eq(done.data.tip, 0, 'no tip at this roll')
    eq(S.players[1].items.weedbaggy, 10 - offer.qty, 'product removed')
    eq(S.players[1].cash, offer.price, 'cash paid')

    local phone = phones.current(1)
    eq(phone.data.stats.sales, 1, 'sales stat')
    eq(phone.data.stats.earned, offer.price, 'earned stat')
    eq(phone.data.xp.weed, levels.gain(1, ECON.XP), 'xp gained')
    eq(relations.get('CID1', 'ped', LOOK), config.Selling.Relationship.PerSale, 'relationship moved')

    local sale = S.turfSales[#S.turfSales]
    check(sale and sale.src == 1 and sale.total == offer.price and sale.zone and sale.zone.id, 'turf.onSale(src, phone, zone, total)')

    local closed = S.events('sd-trapphone:client:ticketClosed', 1, mark)
    eq(#closed, 1, 'client told the ticket closed')
    eq(closed[1].payload.state, 'done', 'closed as done')
    eq(phone.data.threads[res.number].msgs[1].offer.state, 'done', 'stored offer marked done')
    eq(#S.audit('sale', logMark), 1, 'sale audited')

    eq(S.call('completeSale', 1, offer.ticketId).ok, false, 'a ticket cannot be completed twice')
    eq(S.players[1].cash, offer.price, 'no second payout')
end)

test('selling: tickets are owned, typed and positioned', function()
    reset(1, { weedbaggy = 10 })

    local res = customer(1)
    local id = res.offer.ticketId
    S.advance(MIN_SERVE + 1)

    local logMark = #S.logs
    eq(call('completeSale', 3, id).ok, false, 'someone else completing the ticket')
    eq(call('completeSale', 1, { id }).ok, false, 'ticket id of the wrong type')
    eq(call('offerRespond', 3, res.number, id, 'accept').ok, false, 'someone else accepting the ticket')
    eq(#S.audit('suspect', logMark), 3, 'each of those is logged')
    eq(call('offerRespond', 1, '000-0000', id, 'accept').ok, false, 'wrong number for the ticket')
    eq(call('offerRespond', 1, res.number, id, 'steal').ok, false, 'unknown action')
    eq(call('completeDrop', 1, id).ok, false, 'street ticket completed as a drop-off')

    -- Teleported away: the sale is refused, logged, and the customer is gone.
    S.players[1].coords = vec3(3000.0, 3000.0, 30.0)
    logMark = #S.logs
    eq(call('completeSale', 1, id).error, S.strings['selling.too_far'], 'far from where the ticket was made')
    eq(#S.audit('suspect', logMark), 1, 'logged')
    eq(S.players[1].cash, 0, 'nothing paid')
    eq(selling.ticket(id), nil, 'ticket closed')
    S.players[1].coords = vec3(0.0, 0.0, 30.0)
end)

test('selling: a malformed look key is rejected and logged, a repeated look is turned away', function()
    reset(1, { weedbaggy = 20 })

    check(call('hustleStart', 1, 'corner', 'any').ok, 'start')
    S.advance(15)

    local req = call('requestCustomer', 1)
    local logMark = #S.logs

    eq(call('customerLook', 1, req.ticketId, "x'; DROP TABLE").ok, false, 'garbage key')
    eq(#S.audit('suspect', logMark), 1, 'logged')
    eq(selling.ticket(req.ticketId), nil, 'ticket dropped')

    -- Serve one look, then offer the same look again straight away.
    S.advance(60)
    req = call('requestCustomer', 1)
    check(req.ok, 'second customer')

    local res = call('customerLook', 1, req.ticketId, LOOK)
    check(res.ok, 'look accepted')
    S.advance(MIN_SERVE + 1)
    check(S.call('completeSale', 1, res.offer.ticketId).ok, 'sale')

    S.advance(60)
    req = call('requestCustomer', 1)
    check(req.ok, 'third customer')

    local again = call('customerLook', 1, req.ticketId, LOOK)
    eq(again.ok, false, 'same look again inside the reuse window')
    eq(again.retry, true, 'client is told to pick someone else')
end)

test('selling: accept, decline and the haggle', function()
    local REL = config.Selling.Relationship
    reset(1, { weedbaggy = 30 })
    relations.set('CID1', 'ped', 'aaaa0001-0-0', 0)

    -- Accept, then serve.
    local res = customer(1, 'aaaa0001-0-0')
    local id, number, price = res.offer.ticketId, res.number, res.offer.price
    local accepted = call('offerRespond', 1, number, id, 'accept')

    check(accepted.ok and accepted.data.state == 'accepted', 'accept')
    eq(call('offerRespond', 1, number, id, 'accept').ok, false, 'accepting twice')
    eq(call('offerRespond', 1, number, id, 'counter', price + 10).ok, false, 'no haggling after accepting')
    S.advance(MIN_SERVE)
    check(S.call('completeSale', 1, id).ok, 'accepted ticket completes')

    -- Decline.
    reset(1, { weedbaggy = 30 })
    relations.set('CID1', 'ped', 'aaaa0002-0-0', 0)
    res = customer(1, 'aaaa0002-0-0')

    local declined = call('offerRespond', 1, res.number, res.offer.ticketId, 'decline')
    check(declined.ok and declined.data.state == 'declined', 'decline')
    eq(relations.get('CID1', 'ped', 'aaaa0002-0-0'), REL.PerDecline, 'declining costs standing')
    eq(selling.ticket(res.offer.ticketId), nil, 'declined ticket is gone')
    eq(S.players[1].items.weedbaggy, 30, 'nothing sold')

    -- A counter that is not a counter.
    reset(1, { weedbaggy = 30 })
    relations.set('CID1', 'ped', 'aaaa0003-0-0', 0)
    res = customer(1, 'aaaa0003-0-0')
    id, number, price = res.offer.ticketId, res.number, res.offer.price

    eq(call('offerRespond', 1, number, id, 'counter', price).ok, false, 'counter at the offer')
    eq(call('offerRespond', 1, number, id, 'counter', price + 0.5).ok, false, 'fractional counter')
    eq(call('offerRespond', 1, number, id, 'counter', 'lots').ok, false, 'counter of the wrong type')
    eq(call('offerRespond', 1, number, id, 'counter', 0 / 0).ok, false, 'NaN counter')
    eq(selling.ticket(id).counters, ECON.Haggle.MaxCounters, 'none of those used up a haggle')

    -- A won counter raises the price that is paid.
    S.force = 0.0
    local ask = price + 1
    local won = call('offerRespond', 1, number, id, 'counter', ask)
    S.force = 0.5

    check(won.ok and won.data.won == true and won.data.state == 'accepted', 'won counter')
    eq(won.data.price, ask, 'price after the counter')
    eq(relations.get('CID1', 'ped', 'aaaa0003-0-0'), REL.PerHaggleWin, 'winning costs a little standing')
    S.advance(MIN_SERVE)
    eq(S.call('completeSale', 1, id).data.total, ask, 'paid the countered price')
    eq(S.players[1].cash, ask, 'cash matches the countered price')

    -- Lost counters: the customer holds, then walks.
    reset(1, { weedbaggy = 30 })
    relations.set('CID1', 'ped', 'aaaa0004-0-0', 0)
    res = customer(1, 'aaaa0004-0-0')
    id, number, price = res.offer.ticketId, res.number, res.offer.price

    S.force = 0.999
    local lost = call('offerRespond', 1, number, id, 'counter', price + 1)
    check(lost.ok and lost.data.won == false and lost.data.state == 'open', 'first lost counter keeps the offer open')
    eq(lost.data.counters, ECON.Haggle.MaxCounters - 1, 'one haggle used')
    eq(lost.data.price, price, 'price unchanged')

    for _ = 2, ECON.Haggle.MaxCounters do
        lost = call('offerRespond', 1, number, id, 'counter', price + 1)
    end
    S.force = 0.5

    eq(lost.data.state, 'walked', 'out of haggles: they walk')
    eq(selling.ticket(id), nil, 'walked ticket is gone')
    eq(relations.get('CID1', 'ped', 'aaaa0004-0-0'), REL.PerHaggleFail * ECON.Haggle.MaxCounters, 'each lost counter costs standing')

    -- Asking past the item's ceiling can't win even on the best roll.
    reset(1, { weedbaggy = 30 })
    res = customer(1, 'aaaa0005-0-0')
    S.force = 0.0
    local greedy = call('offerRespond', 1, res.number, res.offer.ticketId, 'counter',
        ECON.Prices.weedbaggy.max * res.offer.qty + 1)
    S.force = 0.5
    eq(greedy.data.won, false, 'over the ceiling is always refused')
end)

test('selling: no product, no pay; no pay, product back; robbery pays nothing', function()
    reset(1, { weedbaggy = 10 })

    -- The inventory refuses to give the product up.
    local res = customer(1, 'bbbb0001-0-0')
    S.advance(MIN_SERVE + 1)
    S.inventory.failRemove = true
    local stuck = S.call('completeSale', 1, res.offer.ticketId)
    S.inventory.failRemove = false

    eq(stuck.ok, false, 'removal failed')
    eq(S.players[1].cash, 0, 'nothing paid when nothing was removed')
    eq(S.players[1].items.weedbaggy, 10, 'stock untouched')

    -- The same ticket still completes once the inventory behaves.
    S.advance(2)
    check(S.call('completeSale', 1, res.offer.ticketId).ok, 'retry succeeds')
    eq(S.players[1].cash, res.offer.price, 'paid once')

    -- The product was sold before the hand-off finished.
    reset(1, { weedbaggy = 10 })
    res = customer(1, 'bbbb0002-0-0')
    S.advance(MIN_SERVE + 1)
    give(1, 'weedbaggy', 0)
    eq(S.call('completeSale', 1, res.offer.ticketId).error, S.strings['selling.not_enough'], 'stock gone')
    eq(S.players[1].cash, 0, 'nothing paid')

    -- Payout as an item that can't be carried: the product comes back.
    reset(1, { weedbaggy = 10 })
    res = customer(1, 'bbbb0003-0-0')
    S.advance(MIN_SERVE + 1)
    ECON.PayoutAccount = 'markedbills'
    S.inventory.failAdd = true
    local unpaid = S.call('completeSale', 1, res.offer.ticketId)
    S.inventory.failAdd = false

    eq(unpaid.error, S.strings['selling.pay_failed'], 'payout failed')
    -- failAdd also blocked the hand-back in this fake, so check the intent on a clean run.
    S.advance(2)
    give(1, 'weedbaggy', 10)
    check(S.call('completeSale', 1, res.offer.ticketId).ok, 'item payout')
    eq(S.players[1].items.markedbills, res.offer.price, 'paid one item per dollar')

    ECON.PayoutAccount = 'black'
    reset(1, { weedbaggy = 10 })
    res = customer(1, 'bbbb0004-0-0')
    S.advance(MIN_SERVE + 1)
    check(S.call('completeSale', 1, res.offer.ticketId).ok, 'black payout')
    eq(S.players[1].black, res.offer.price, 'paid as dirty money')
    eq(S.players[1].cash, 0, 'not as cash')
    ECON.PayoutAccount = 'cash'

    -- Robbery.
    reset(1, { weedbaggy = 10 })
    relations.set('CID1', 'ped', 'bbbb0005-0-0', 0)
    phones.current(1).data.xp.weed = 500
    res = customer(1, 'bbbb0005-0-0')
    S.advance(MIN_SERVE + 1)

    local chance = config.Selling.RobberyChance
    config.Selling.RobberyChance = 100
    local robbed = S.call('completeSale', 1, res.offer.ticketId)
    config.Selling.RobberyChance = chance

    check(robbed.ok and robbed.data.robbed == true, 'robbed')
    eq(S.players[1].items.weedbaggy, 10 - res.offer.qty, 'the product is gone')
    eq(S.players[1].cash, 0, 'and nothing was paid')
    eq(phones.current(1).data.xp.weed, 500 - levels.loss(1, ECON.XP), 'xp lost')
    eq(relations.get('CID1', 'ped', 'bbbb0005-0-0'), config.Selling.Relationship.PerRobbery, 'relationship wrecked')
end)

test('selling: a customer becomes a named regular', function()
    local REL = config.Selling.Relationship
    reset(1, { weedbaggy = 10 })

    local look = 'cccc0001-2-1'
    relations.set('CID1', 'ped', look, REL.RegularAt - REL.PerSale)

    local res = customer(1, look)
    S.advance(MIN_SERVE + 1)
    check(S.call('completeSale', 1, res.offer.ticketId).ok, 'sale')

    local phone = phones.current(1)
    local contact = phones.getContact(phone, res.number)

    check(contact, 'regular saved as a contact')
    eq(contact.type, 'regular', 'contact type')
    eq(contact.name, pricing.customerName(look), 'generated name')
    eq(contact.key, look, 'contact remembers the look')
    eq(phone.data.threads[res.number].name, contact.name, 'their thread carries the name')

    -- Their next offer arrives under the name, and a regular never robs.
    S.advance(config.Selling.OfferSeconds * 4)
    local mark = S.mark()
    res = customer(1, look)
    eq(S.events('sd-trapphone:client:message', 1, mark)[1].payload.name, contact.name, 'offer texted under the name')
end)

test('selling: an unanswered offer runs out', function()
    reset(1, { weedbaggy = 10 })

    local res = customer(1, 'dddd0001-0-0')
    local mark = S.mark()

    S.advance(config.Selling.OfferSeconds * 3)
    S.pump()

    eq(selling.ticket(res.offer.ticketId), nil, 'ticket expired')

    local closed = S.events('sd-trapphone:client:ticketClosed', 1, mark)
    eq(#closed, 1, 'client told')
    eq(closed[1].payload.state, 'expired', 'as expired')
    eq(phones.current(1).data.threads[res.number].msgs[1].offer.state, 'expired', 'stored offer marked expired')
    eq(S.call('completeSale', 1, res.offer.ticketId).ok, false, 'an expired ticket cannot be completed')

    -- A customer the client never found is dropped without a word.
    S.advance(30)
    local req = call('requestCustomer', 1)
    check(req.ok, 'next customer')
    S.trigger('sd-trapphone:server:customerLost', 1, req.ticketId)
    eq(selling.ticket(req.ticketId), nil, 'lost ticket is gone')
end)

test('selling: the pull-up spot is the real position and brings car buyers', function()
    reset(1, { weedbaggy = 10 })
    S.players[1].coords = vec3(123.456, -789.123, 30.0)

    local set = call('setSpot', 1)
    check(set.ok and set.data.spotSet == true, 'spot set')

    local spot = phones.current(1).data.spot
    check(math.abs(spot.x - 123.46) < 0.001 and math.abs(spot.y + 789.12) < 0.001, 'spot is where the player stands')

    check(call('hustleStart', 1, 'corner', 'any').ok, 'start')
    S.advance(15)
    S.force = 0.0
    local req = call('requestCustomer', 1)
    S.force = 0.5

    eq(req.kind, 'car', 'a buyer in a car')
    check(req.spot and req.spot.x == spot.x, 'the spot is sent with a car buyer')

    S.trigger('sd-trapphone:server:customerLost', 1, req.ticketId)

    local cleared = call('clearSpot', 1)
    check(cleared.ok and cleared.data.spotSet == false, 'spot cleared')
    eq(phones.current(1).data.spot, nil, 'spot removed from the phone')
    S.players[1].coords = vec3(0.0, 0.0, 30.0)
end)

test('selling: pitching refuses, bites, and remembers who was asked', function()
    reset(1, { weedbaggy = 10 })
    phones.current(1).data.xp.weed = 500
    relations.set('CID1', 'ped', 'eeee0001-0-0', 0)
    relations.set('CID1', 'ped', 'eeee0002-0-0', 0)

    eq(call('pitch', 1, 'not a key').ok, false, 'garbage key')

    S.force = 0.0
    S.advance(5)
    local no = S.call('pitch', 1, 'eeee0001-0-0')
    S.force = 0.5

    eq(no.ok, false, 'refused')
    eq(no.refused, true, 'flagged as a refusal')
    check(type(no.error) == 'string' and #no.error > 0, 'the refusal has a line')
    eq(phones.current(1).data.xp.weed, 500 - levels.loss(1, ECON.XP), 'a refusal costs xp')

    S.advance(5)
    eq(S.call('pitch', 1, 'eeee0001-0-0').error, S.strings['selling.already_pitched'], 'same ped again')

    S.advance(5)
    local yes = S.call('pitch', 1, 'eeee0002-0-0')
    check(yes.ok, 'pitch taken: ' .. tostring(yes.error))
    eq(yes.offer.kind, 'pitch', 'offer kind')

    S.advance(5)
    eq(S.call('pitch', 1, 'eeee0003-0-0').error, S.strings['selling.busy'], 'one customer at a time')

    S.advance(MIN_SERVE)
    check(S.call('completeSale', 1, yes.offer.ticketId).ok, 'pitched sale completes')
    eq(S.players[1].cash, yes.offer.price, 'paid')

    S.players[1].vehicle = 9
    S.advance(5)
    eq(S.call('pitch', 1, 'eeee0004-0-0').ok, false, 'no pitching from a car')
    S.players[1].vehicle = 0
end)

test('selling: losing the phone or the stock stops the hustle and says why', function()
    reset(1, { weedbaggy = 1 })
    check(call('hustleStart', 1, 'corner', 'any').ok, 'start')

    give(1, 'weedbaggy', 0)
    S.advance(15)
    local mark = S.mark()
    eq(call('requestCustomer', 1).stopped, true, 'out of stock')
    eq(selling.mode(1), 'idle', 'idle')
    eq(S.events('sd-trapphone:client:hustleStopped', 1, mark)[1].payload.reason, S.strings['selling.stopped_stock'], 'reason sent')

    reset(1, { weedbaggy = 5 })
    check(call('hustleStart', 1, 'corner', 'any').ok, 'start again')
    give(1, PHONE, 0)
    S.advance(15)
    mark = S.mark()
    eq(call('requestCustomer', 1).stopped, true, 'phone gone')
    eq(S.events('sd-trapphone:client:hustleStopped', 1, mark)[1].payload.reason, S.strings['selling.stopped_phone'], 'reason sent')
end)

test('dropoffs: an order is texted, accepted, driven and delivered at the door', function()
    local D = config.Deliveries
    reset(2, { cokebaggy = 20 })
    relations.set('CID2', 'ped', 'door-1', 0)

    eq(call('hustleStart', 2, 'drops', 'any').error, S.strings['dropoffs.need_vehicle'], 'on foot')
    S.players[2].vehicle = 55

    local start = call('hustleStart', 2, 'drops', 'coke')
    check(start.ok and start.data.mode == 'drops', 'start: ' .. tostring(start.error))
    eq(start.data.dropsEnabled, true, 'dropsEnabled')

    local mark = S.mark()
    S.advance(15)
    S.pump()

    local texts = S.events('sd-trapphone:client:message', 2, mark)
    eq(#texts, 1, 'one order texted')

    local offer, number = texts[1].payload.msg.offer, texts[1].payload.number
    local entry = ECON.Prices.cokebaggy

    eq(offer.kind, 'drop', 'offer kind')
    eq(offer.state, 'open', 'offer state')
    check(type(offer.place) == 'string' and #offer.place > 0, 'the order names a place')
    check(offer.qty >= 1 and offer.qty <= math.ceil(entry.maxSale * D.QuantityMultiplier), 'quantity')
    check(offer.price >= entry.min * offer.qty and offer.price <= entry.max * offer.qty, 'price inside min/max')
    eq(dropoffs.queued(2), 1, 'queue')
    eq(#S.events('sd-trapphone:client:dropAccepted', 2, mark), 0, 'no door before accepting')

    -- No second order before RequestDelay.
    S.advance(10)
    S.pump()
    eq(dropoffs.queued(2), 1, 'still one order')

    mark = S.mark()
    local accepted = call('offerRespond', 2, number, offer.ticketId, 'accept')
    check(accepted.ok and accepted.data.state == 'accepted', 'accept')

    local routes = S.events('sd-trapphone:client:dropAccepted', 2, mark)
    eq(#routes, 1, 'the door is sent on accept')

    local route = routes[1].payload
    local ticket = selling.ticket(offer.ticketId)
    local door = D.Spots[ticket.door].coords

    eq(route.ticketId, offer.ticketId, 'route ticket')
    eq(route.number, number, 'route number')
    eq(route.coords.x, door.x, 'route door')

    local distance = #(S.players[2].coords - door.xyz)
    check(distance >= D.MinDistance and distance <= D.MaxDistance, 'door at a sensible distance')
    check(ticket.expires >= S.clock + D.DeliverMinutes * 60 - 5, 'accepted order gets the delivery window')

    -- Still in the car, then on foot but nowhere near, then claiming it from across the map.
    eq(call('completeDrop', 2, offer.ticketId).error, S.strings['selling.on_foot'], 'from the car')
    S.players[2].vehicle = 0

    local logMark = #S.logs
    eq(call('completeDrop', 2, offer.ticketId).error, S.strings['dropoffs.too_far'], 'far from the door')
    eq(#S.audit('suspect', logMark), 1, 'a completion from that far is logged')
    eq(call('completeSale', 2, offer.ticketId).ok, false, 'a drop-off cannot be completed as a street sale')
    eq(call('completeDrop', 3, offer.ticketId).ok, false, 'someone else at the door')

    S.players[2].coords = vec3(door.x + D.CompleteRadius + 2.0, door.y, door.z)
    logMark = #S.logs
    eq(call('completeDrop', 2, offer.ticketId).error, S.strings['dropoffs.too_far'], 'just outside the radius')
    eq(#S.audit('suspect', logMark), 0, 'a near miss is not logged')
    eq(S.players[2].cash, 0, 'nothing paid yet')

    S.players[2].coords = vec3(door.x + 1.0, door.y, door.z)
    mark = S.mark()

    local done = call('completeDrop', 2, offer.ticketId)
    check(done.ok, 'delivery refused: ' .. tostring(done.error))
    eq(S.players[2].items.cokebaggy, 20 - offer.qty, 'product removed')
    eq(S.players[2].cash, offer.price, 'paid')

    local phone = phones.current(2)
    eq(phone.data.stats.drops, 1, 'drops stat')
    eq(phone.data.stats.sales, 0, 'not counted as a corner sale')
    eq(phone.data.xp.coke, math.floor(levels.gain(1, ECON.XP) * ECON.XP.DropOffBonus), 'drop-off xp bonus')
    eq(S.events('sd-trapphone:client:ticketClosed', 2, mark)[1].payload.kind, 'drop', 'client told the drop closed')
    eq(dropoffs.queued(2), 0, 'queue empty')
    eq(selling.mode(2), 'drops', 'still taking orders')
end)

test('dropoffs: queue cap, promised stock, late orders and stopping', function()
    local D = config.Deliveries
    reset(2, { cokebaggy = 3 })
    S.players[2].coords = vec3(10.0, 0.0, 30.0)
    S.players[2].vehicle = 55

    check(call('hustleStart', 2, 'drops', 'any').ok, 'start')

    -- With the biggest order every time, three baggies are promised after very few orders
    -- and no order may promise stock that is already spoken for.
    S.force = 0.999

    for _ = 1, D.MaxQueue + 3 do
        S.advance(D.RequestDelay + 5)
        S.pump()
    end

    S.force = 0.5

    local open = selling.ticketsOf(2, 'drop')
    local promised, doors = 0, {}

    for _, ticket in ipairs(open) do
        promised = promised + ticket.qty
        check(not doors[ticket.door], 'two orders for the same door')
        doors[ticket.door] = true
    end

    check(#open >= 1 and #open <= D.MaxQueue, 'queue within MaxQueue')
    check(promised <= 3, ('promised %d of 3 held'):format(promised))

    -- Unanswered orders run out.
    local mark = S.mark()
    S.players[2].vehicle = 0 -- on foot: no new orders while the old ones expire
    S.advance(D.AcceptSeconds + 10)
    S.pump()

    eq(dropoffs.queued(2), 0, 'unanswered orders expired')
    check(#S.events('sd-trapphone:client:ticketClosed', 2, mark) >= 1, 'client told')

    -- An accepted order that is never delivered is called off when the window closes.
    S.players[2].vehicle = 55
    mark = S.mark()
    S.advance(D.RequestDelay + 5)
    S.pump()

    local text = S.events('sd-trapphone:client:message', 2, mark)[1].payload
    check(call('offerRespond', 2, text.number, text.msg.offer.ticketId, 'accept').ok, 'accept')

    S.players[2].vehicle = 0
    S.advance(D.DeliverMinutes * 60 + 30)
    S.pump()
    eq(selling.ticket(text.msg.offer.ticketId), nil, 'late order called off')

    -- Stopping lets every open order go.
    S.players[2].vehicle = 55
    S.advance(D.RequestDelay + 5)
    S.pump()
    check(dropoffs.queued(2) >= 1, 'an order is open')

    mark = S.mark()
    check(call('hustleStop', 2).ok, 'stop')
    eq(dropoffs.queued(2), 0, 'no orders after stopping')
    eq(selling.mode(2), 'idle', 'idle')
    check(#S.events('sd-trapphone:client:ticketClosed', 2, mark) >= 1, 'client told to drop the route')
end)

test('dispatch: police count, canSell, heat, alert cooldown and snitch delay', function()
    local D = config.Dispatch

    -- Earlier tests rolled snitch calls that were never delivered; start from a clean slate.
    S.timeouts = {}

    eq(dispatch.canSell(), true, 'no police check by default')

    D.CheckForPolice = true
    S.advance(20)
    local ok, reason = dispatch.canSell()
    eq(ok, false, 'not enough police')
    eq(reason, S.strings['dispatch.not_enough_police'], 'localized reason')

    reset(1, { weedbaggy = 5 })
    eq(call('hustleStart', 1, 'corner', 'any').error, reason, 'selling cannot start')
    check(phones.snapshot(1, phones.current(1)).hustle.blocked == reason, 'the phone shows why')

    for src = 10, 9 + D.RequiredPolice do
        S.addPlayer(src, { job = D.PoliceJobs[1 + src % #D.PoliceJobs] })
    end

    eq(dispatch.canSell(), false, 'the head count is cached for a few seconds')
    S.advance(20)
    eq(dispatch.policeCount(), D.RequiredPolice, 'police counted across every police job')
    eq(dispatch.canSell(), true, 'enough police')
    eq(dispatch.isPolice(10), true, 'isPolice')
    eq(dispatch.isPolice(1), false, 'isPolice for a civilian')
    D.CheckForPolice = false

    -- Alert: payload, heat, cooldown.
    eq(dispatch.heat(1), 0, 'cold to start')

    local mark = S.mark()
    eq(dispatch.alert(1, 'witness'), true, 'alert sent')

    local sent = S.events('sd-trapphone:client:alert', 1, mark)
    eq(#sent, 1, 'the seller client is told to fire the dispatch bridge')
    eq(sent[1].payload.code, D.Alert.code, 'code')
    eq(sent[1].payload.title, D.Alert.title, 'title')
    eq(sent[1].payload.message, S.strings['dispatch.reason_witness'], 'message for the reason')
    eq(sent[1].payload.sprite, D.Alert.sprite, 'sprite')
    eq(sent[1].payload.jobs, D.PoliceJobs, 'jobs')
    eq(sent[1].payload.coords.x, S.players[1].coords.x, 'coords default to the player')
    eq(dispatch.heat(1), D.Heat.PerAlert, 'heat raised')

    eq(dispatch.alert(1, 'witness'), false, 'second alert inside the cooldown')
    eq(dispatch.heat(1), D.Heat.PerAlert, 'a held alert adds no heat')

    S.advance(180)
    eq(dispatch.heat(1), D.Heat.PerAlert - 3 * D.Heat.CoolPerMinute, 'heat cools by the minute')
    S.advance(60 * 60)
    eq(dispatch.heat(1), 0, 'and never below zero')

    eq(dispatch.alert(1, 'made_up_reason'), true, 'alert after the cooldown')
    eq(S.sent[#S.sent].payload.message, D.Alert.title, 'unknown reason falls back to the title')
    eq(dispatch.alert(999, 'witness'), false, 'no alert about someone who left')

    -- Snitch: a delayed call from where the deal happened.
    S.advance(D.Cooldown + D.Snitch.Timeout + 10)
    S.force = 0.999
    eq(dispatch.snitch(1, 1, 'pitch'), false, 'a high roll is no call')
    S.force = 0.0
    S.players[1].coords = vec3(50.0, 60.0, 30.0)
    mark = S.mark()
    eq(dispatch.snitch(1, 1, 'pitch'), true, 'a low roll is a call')
    eq(#S.events('sd-trapphone:client:alert', 1, mark), 0, 'nothing is sent straight away')
    eq(dispatch.snitch(1, 1, 'pitch'), false, 'one call per timeout')
    eq(dispatch.snitch(10, 1, 'witness'), false, 'police are never snitched on')

    S.players[1].coords = vec3(0.0, 0.0, 30.0)
    S.flushTimeouts()
    S.force = 0.5

    sent = S.events('sd-trapphone:client:alert', 1, mark)
    eq(#sent, 1, 'the call arrives after the delay')
    eq(sent[1].payload.coords.x, 50.0, 'from where the player was, not where they went')
    eq(sent[1].payload.message, S.strings['dispatch.reason_snitch'], 'snitch message')

    -- Simple mode.
    D.Simple = true
    S.advance(D.Cooldown + 10)
    S.force = 0.0
    eq(dispatch.snitch(1, 1, 'pitch'), false, 'simple mode ignores refused pitches')
    eq(dispatch.snitch(1, 1, 'witness'), true, 'simple mode alerts on the sale roll')
    S.force = 0.5
    D.Simple = false

    for src = 10, 9 + D.RequiredPolice do S.dropPlayer(src) end
end)

test('cleanup: a player who leaves takes their session and tickets with them', function()
    reset(3, { weedbaggy = 5 })

    local res = customer(3, 'ffff0001-0-0')
    check(selling.ticket(res.offer.ticketId), 'ticket live')

    S.dropPlayer(3)

    eq(selling.ticket(res.offer.ticketId), nil, 'ticket gone')
    eq(selling.session(3), nil, 'session gone')
    eq(#selling.ticketsOf(3), 0, 'no tickets left')
end)

realPrint(('\n%d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
