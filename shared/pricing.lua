---@type table Pricing module; the table returned at end of file. Pure maths and picks for the
---street economy: no natives, no ox_lib, no config require. Every function takes the config
---tables it needs and, where it rolls, a random function returning [0, 1), so the offline
---tests can drive it with a fixed sequence under stock Lua 5.4.
local pricing = {}

---@alias TrapRandom fun(): number a random source returning a float in [0, 1)

---@type string[] Street names for customers. Kept neutral so a name never contradicts the ped
---it lands on (the look key carries no gender).
local NAMES = {
    'Ace', 'Ash', 'Bams', 'Bishop', 'Blue', 'Bones', 'Boogie', 'Breeze', 'Buck', 'Cash',
    'Chino', 'Cricket', 'Dee', 'Deuce', 'Dice', 'Dizzy', 'Domino', 'Dre', 'Dubs', 'Echo',
    'Fats', 'Flaco', 'Flip', 'Ghost', 'Gizmo', 'Goose', 'Haze', 'Jay', 'Jinx', 'Juice',
    'Kay', 'Keys', 'Kilo', 'Lefty', 'Lucky', 'Mack', 'Mouse', 'Nickel', 'Nine', 'Noodle',
    'Peanut', 'Pep', 'Pookie', 'Preach', 'Queen', 'Red', 'Rico', 'Rooster', 'Scoop', 'Shorty',
    'Skip', 'Slim', 'Smiley', 'Smoke', 'Sparks', 'Spider', 'Stacks', 'Tank', 'Tee', 'Tiny',
    'Trey', 'Twin', 'Whisper', 'Woody', 'Yoyo', 'Zip',
}

---@type string[] Where a customer says they are from, appended to some names ("Dre from the Mesa").
local TAGS = {
    'from the block', 'from the Mesa', 'from the pier', 'from the hills', 'from the tracks',
    'from the canals', 'from the yard', 'from the east', 'from the lot', 'from the courts',
}

---Clamp a number into a range.
---@param value number
---@param min number
---@param max number
---@return number clamped
local function clamp(value, min, max)
    if value < min then return min end
    if value > max then return max end

    return value
end

---Round half up to an integer.
---@param value number
---@return integer rounded
local function round(value)
    return math.floor(value + 0.5)
end

---A stable 32-bit hash of a string (FNV-1a with a final mix so the low bits spread well).
---The same key and salt give the same number on every machine and every restart.
---@param key string|number what to hash
---@param salt? string mixed in first, so one key can give several independent numbers
---@return integer hash 0..4294967295
function pricing.hash(key, salt)
    local text = (salt or '') .. '|' .. tostring(key)
    local h = 2166136261

    for i = 1, #text do
        h = ((h ~ text:byte(i)) * 16777619) & 0xFFFFFFFF
    end

    h = h ~ (h >> 16)
    h = (h * 0x45d9f3b) & 0xFFFFFFFF
    h = h ~ (h >> 15)

    return h
end

---A whole number between two bounds, both included.
---@param rand TrapRandom
---@param min integer
---@param max integer
---@return integer value
function pricing.between(rand, min, max)
    if max <= min then return min end

    return clamp(min + math.floor(rand() * (max - min + 1)), min, max)
end

---A true/false roll.
---@param rand TrapRandom
---@param percent number 0..100
---@return boolean hit
function pricing.chance(rand, percent)
    return rand() * 100 < percent
end

---Whether a zone's wealth tier craves a product.
---@param entry table one config.Economy.Prices row
---@param wealth integer|nil zone wealth 0..5
---@return boolean craved
function pricing.inDemand(entry, wealth)
    if wealth == nil or type(entry.demand) ~= 'table' then return false end

    for i = 1, #entry.demand do
        if entry.demand[i] == wealth then return true end
    end

    return false
end

---How many units a customer asks for: 1 up to the item's maxSale (times a multiplier for
---drop-offs, rounded up), never more than the seller is holding.
---@param entry table one config.Economy.Prices row
---@param held integer how many the seller has free to sell
---@param rand TrapRandom
---@param multiplier? number scales maxSale (config.Deliveries.QuantityMultiplier)
---@return integer qty 0 when nothing is held
function pricing.quantity(entry, held, rand, multiplier)
    if held < 1 then return 0 end

    local most = math.ceil((entry.maxSale or 1) * (multiplier or 1))

    most = math.max(1, math.min(most, math.floor(held)))

    return pricing.between(rand, 1, most)
end

---Roll one offer. The per-unit price starts at the item's base price, is lifted by zone
---demand, the customer's relationship, the seller's level and any flat bonus, wobbles by the
---spread, and is then clamped to the item's min/max. Totals are always whole numbers.
---@param opts { entry: table, qty: integer, economy: table, wealth?: integer, relationship?: number, level?: integer, bonus?: number }
---entry is one config.Economy.Prices row, economy is config.Economy, bonus a plain multiplier
---@param rand TrapRandom
---@return { unit: integer, total: integer, demand: boolean } offer
function pricing.offer(opts, rand)
    local entry, economy = opts.entry, opts.economy
    local qty = math.max(1, math.floor(opts.qty or 1))
    local demand = pricing.inDemand(entry, opts.wealth)
    local price = entry.price

    if demand then price = price * (economy.DemandBonus or 1) end

    local relationship = clamp(opts.relationship or 0, -100, 100)
    price = price * (1 + relationship / 100 * (economy.RelationshipBonus or 0))

    local levelBonus = math.max(0, (opts.level or 1) - 1) * (economy.LevelBonusPerLevel or 0)
    price = price * (1 + math.min(economy.LevelBonusCap or 0, levelBonus))

    price = price * (opts.bonus or 1)

    local spread = economy.OfferSpread or 0
    price = price * (1 + (rand() * 2 - 1) * spread)

    local unit = math.tointeger(clamp(round(price), math.ceil(entry.min), math.floor(entry.max))) or entry.min

    return { unit = unit, total = unit * qty, demand = demand }
end

---The most a customer can ever be talked up to for a ticket: the item's max per unit.
---@param entry table one config.Economy.Prices row
---@param qty integer
---@return integer ceiling total price
function pricing.ceiling(entry, qty)
    return math.floor(entry.max) * qty
end

---The chance a counter-offer is taken. Asking for no more than the offer is always taken. It
---falls in a straight line from BaseChance at +0% to nothing at +MaxMarkup, shifted by the
---customer's personality and relationship (the shifts move the line up or down, the cut-off at
---MaxMarkup stays hard), and anything over the ceiling is always refused.
---@param opts { offer: integer, ask: integer, ceiling?: integer, haggle: table, shift?: number, relationship?: number, relationshipShift?: number }
---offer and ask are totals, haggle is config.Economy.Haggle, shift is the personality's haggle
---value, relationshipShift is how much a +100 relationship adds
---@return number chance 0..1
function pricing.haggleChance(opts)
    local offer, ask, haggle = opts.offer, opts.ask, opts.haggle

    if ask <= offer then return 1.0 end
    if offer <= 0 then return 0.0 end
    if opts.ceiling and ask > opts.ceiling then return 0.0 end

    local maxMarkup = haggle.MaxMarkup or 0
    local markup = (ask - offer) / offer
    if maxMarkup <= 0 or markup >= maxMarkup then return 0.0 end

    local chance = (haggle.BaseChance or 0) * (1 - markup / maxMarkup)

    chance = chance + (opts.shift or 0)
    chance = chance + clamp(opts.relationship or 0, -100, 100) / 100 * (opts.relationshipShift or 0)

    return clamp(chance, 0.0, 1.0)
end

---The chance (percent) that a ped pitched cold says no. A good relationship lowers it, a bad
---one raises it, and a regular never refuses.
---@param base number config.Selling.RefuseDrugsChance
---@param relationship number -100..100
---@param regularAt? number relationship at which a ped is a regular
---@return number percent 0..100
function pricing.refuseChance(base, relationship, regularAt)
    relationship = clamp(relationship or 0, -100, 100)
    if regularAt and relationship >= regularAt then return 0.0 end

    return clamp(base * (1 - relationship / 100), 0, 100)
end

---A tip on top of a sale, or nothing.
---@param total integer the sale
---@param personality table|nil one config.Selling.Personalities row
---@param share number config.Selling.TipShare
---@param rand TrapRandom
---@return integer tip 0 when they don't tip
function pricing.tip(total, personality, share, rand)
    local odds = personality and personality.tip or 0
    if odds <= 0 or rand() >= odds then return 0 end

    return math.max(1, math.floor(total * (share or 0)))
end

---The personality a look key always maps to. Weighted by each row's `weight`, and stable: the
---names are walked in sorted order so table iteration order can't change the answer.
---@param key string|number ped look key (or any stable id)
---@param personalities table<string, table> config.Selling.Personalities
---@return string|nil name nil when the table is empty
---@return table|nil personality the matching row
function pricing.personality(key, personalities)
    local names, total = {}, 0

    for name, row in pairs(personalities) do
        names[#names + 1] = name
        total = total + math.max(0, row.weight or 0)
    end

    if #names == 0 then return nil, nil end

    table.sort(names)

    if total <= 0 then return names[1], personalities[names[1]] end

    local roll = pricing.hash(key, 'personality') / 4294967296 * total

    for i = 1, #names do
        roll = roll - math.max(0, personalities[names[i]].weight or 0)
        if roll < 0 then return names[i], personalities[names[i]] end
    end

    return names[#names], personalities[names[#names]]
end

---The name a look key always carries once they are a regular ("Dre", "Smoke from the pier").
---@param key string|number ped look key
---@return string name
function pricing.customerName(key)
    local name = NAMES[pricing.hash(key, 'name') % #NAMES + 1]
    local tagRoll = pricing.hash(key, 'tag')

    -- About one in three carries a tag, which keeps two regulars with the same street name apart.
    if tagRoll % 3 == 0 then
        return ('%s %s'):format(name, TAGS[(tagRoll // 3) % #TAGS + 1])
    end

    return name
end

---The number a look key always texts from. Never under the burner prefix, so it can't collide
---with a real trap phone or a special contact.
---@param key string|number ped look key
---@param avoidPrefix? string config.Phone.NumberPrefix
---@return string number e.g. '418-0375'
function pricing.customerNumber(key, avoidPrefix)
    local h = pricing.hash(key, 'number')
    local prefix = 200 + h % 700

    if ('%03d'):format(prefix) == tostring(avoidPrefix) then
        prefix = prefix + 1
        if prefix > 899 then prefix = 200 end
    end

    return ('%03d-%04d'):format(prefix, (h // 700) % 10000)
end

---One line of customer dialogue for a moment. Lines can be given per personality; when the
---personality has its own list it is used about half the time, so the shared lines still show.
---The line is formatted with the extra arguments in order (see configs/server/dialogue.lua); a
---line that asks for more than it is given comes back unformatted rather than erroring.
---@param dialogue table config.Dialogue
---@param moment string a key of the dialogue table ('offer', 'thanks', ...)
---@param personality string|nil a key of config.Selling.Personalities
---@param rand TrapRandom
---@param ... any values for the line's placeholders
---@return string line '' when the moment has no lines at all
function pricing.say(dialogue, moment, personality, rand, ...)
    local pools = dialogue and dialogue[moment]
    if type(pools) ~= 'table' then return '' end

    local own = personality and pools[personality]
    local shared = pools.default
    local pool = shared

    if type(own) == 'table' and #own > 0 and (type(shared) ~= 'table' or #shared == 0 or rand() < 0.5) then
        pool = own
    end

    if type(pool) ~= 'table' or #pool == 0 then return '' end

    local line = pool[pricing.between(rand, 1, #pool)]
    local ok, text = pcall(string.format, line, ...)

    return ok and text or line
end

return pricing
