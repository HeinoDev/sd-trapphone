---@type table Levels module; the table returned at end of file. Pure maths over an XP config
---table (config.Economy.XP), so the offline tests can drive it without a server.
local levels = {}

---The level a total XP amount sits at. Level n -> n+1 costs step x n, so the total needed to
---reach level L is step x L(L-1)/2.
---@param xp integer total xp
---@param cfg table config.Economy.XP
---@return integer level 1..cfg.MaxLevel
function levels.fromXp(xp, cfg)
    local level = 1
    local remaining = math.max(0, xp or 0)

    while level < cfg.MaxLevel and remaining >= cfg.LevelStep * level do
        remaining -= cfg.LevelStep * level
        level += 1
    end

    return level
end

---Total XP needed to stand at the start of a level.
---@param level integer
---@param cfg table config.Economy.XP
---@return integer xp
function levels.xpFor(level, cfg)
    return cfg.LevelStep * level * (level - 1) // 2
end

---Progress through the current level, 0..1 (1 at max level).
---@param xp integer total xp
---@param cfg table config.Economy.XP
---@return number progress
function levels.progress(xp, cfg)
    local level = levels.fromXp(xp, cfg)
    if level >= cfg.MaxLevel then return 1.0 end

    local into = xp - levels.xpFor(level, cfg)

    return into / (cfg.LevelStep * level)
end

---XP earned by one sale at a level: it thins out as you climb.
---@param level integer
---@param cfg table config.Economy.XP
---@return integer xp
function levels.gain(level, cfg)
    return math.max(cfg.GainMin, cfg.GainBase // math.max(1, level))
end

---XP lost by one failure at a level: it bites harder as you climb.
---@param level integer
---@param cfg table config.Economy.XP
---@return integer xp
function levels.loss(level, cfg)
    return math.min(cfg.LossMax, cfg.LossBase * math.max(1, level))
end

---The title a level carries (config.Economy.Titles): highest `from` that fits.
---@param level integer
---@param titles { from: integer, label: string }[]
---@return string label
function levels.title(level, titles)
    local label = ''

    for i = 1, #titles do
        if level >= titles[i].from then label = titles[i].label end
    end

    return label
end

return levels
