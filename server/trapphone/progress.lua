---@type table sd-trapphone config root (configs/config.lua).
local config = require 'configs.config'
---@type table Console log helper (shared.log).
local log = require 'shared.log'
---@type table Audit-log helper (server.trapphone.audit).
local audit = require 'server.trapphone.audit'
---@type table Pure level maths (shared.levels).
local levels = require 'shared.levels'
---@type table Live phones (server.trapphone.phones).
local phones = require 'server.trapphone.phones'

---@type table XP curve config (config.Economy.XP).
local XP = config.Economy.XP

---@type table Progress module; the table returned at end of file. XP and levels per product
---family, stored on the phone.
local progress = {}

---@type fun(phone: table, family: string, level: integer, src: integer|nil)[] Level-up listeners.
local listeners = {}

---A phone's level in one product family.
---@param phone table TrapPhone
---@param family string a key of config.Drugs.Families
---@return integer level
function progress.level(phone, family)
    return levels.fromXp(phone.data.xp[family] or 0, XP)
end

---A phone's best level across every family (what back-room tiers are judged on).
---@param phone table TrapPhone
---@return integer level
function progress.bestLevel(phone)
    local best = 1

    for family in pairs(config.Drugs.Families) do
        best = math.max(best, progress.level(phone, family))
    end

    return best
end

---Whether a phone meets an unlock rule ({ family = <family>|'any', level = n }).
---@param phone table TrapPhone
---@param unlock { family: string, level: integer }|nil nil always passes
---@return boolean met
function progress.meets(phone, unlock)
    if not unlock then return true end
    if unlock.family == 'any' then return progress.bestLevel(phone) >= unlock.level end

    return progress.level(phone, unlock.family) >= unlock.level
end

---Run a function whenever a phone gains a level in a family.
---@param fn fun(phone: table, family: string, level: integer, src: integer|nil)
function progress.onLevelUp(fn)
    listeners[#listeners + 1] = fn
end

---Add XP to a family on a phone. Fires the level-up listeners once per level gained.
---@param phone table TrapPhone
---@param family string a key of config.Drugs.Families
---@param amount integer xp to add (positive)
---@return integer level the level after the gain
function progress.add(phone, family, amount)
    if not config.Drugs.Families[family] or amount <= 0 then return progress.level(phone, family) end

    local before = progress.level(phone, family)

    phone.data.xp[family] = (phone.data.xp[family] or 0) + math.floor(amount)
    phones.touch(phone)

    local after = progress.level(phone, family)
    if after > before then
        local src = phones.holderOf(phone)

        audit.log('level_up', src or 'system', ('phone %s reached level %d in %s'):format(phone.id, after, family),
            { phone = phone.id, family = family, level = after })

        for level = before + 1, after do
            for i = 1, #listeners do
                local ok, err = pcall(listeners[i], phone, family, level, src)
                if not ok then log.error('progress', 'level-up listener failed: %s', err) end
            end
        end

        phones.refresh(phone, 'rep')
    end

    return after
end

---Take XP from a family on a phone (never below zero). Levels can drop.
---@param phone table TrapPhone
---@param family string a key of config.Drugs.Families
---@param amount integer xp to remove (positive)
---@return integer level the level after the loss
function progress.remove(phone, family, amount)
    if not config.Drugs.Families[family] or amount <= 0 then return progress.level(phone, family) end

    local before = progress.level(phone, family)

    phone.data.xp[family] = math.max(0, (phone.data.xp[family] or 0) - math.floor(amount))
    phones.touch(phone)

    local after = progress.level(phone, family)
    if after ~= before then phones.refresh(phone, 'rep') end

    return after
end

---XP for one completed sale in a family, at the phone's current level.
---@param phone table TrapPhone
---@param family string
---@return integer xp
function progress.saleGain(phone, family)
    return levels.gain(progress.level(phone, family), XP)
end

---XP lost to one failure in a family, at the phone's current level.
---@param phone table TrapPhone
---@param family string
---@return integer xp
function progress.failLoss(phone, family)
    return levels.loss(progress.level(phone, family), XP)
end

-- The handset's "rep" section: one line per family. Exact numbers are hidden unless the
-- economy config says otherwise; the title and a coarse bar are always shown.
phones.addPart('rep', function(_, phone)
    local list = {}

    for family, info in pairs(config.Drugs.Families) do
        local xp = phone.data.xp[family] or 0
        local level = levels.fromXp(xp, XP)

        list[#list + 1] = {
            family = family,
            label = info.label,
            color = info.color,
            title = levels.title(level, config.Economy.Titles),
            level = config.Economy.ShowLevelNumbers and level or nil,
            bars = math.floor(levels.progress(xp, XP) * 5),
        }
    end

    table.sort(list, function(a, b) return a.label < b.label end)

    return list
end)

return progress
