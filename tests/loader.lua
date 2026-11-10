-- Resource loader for the offline harness: a package searcher that maps dotted module names
-- onto the resource folder (`shared.pricing` -> <resource>/shared/pricing.lua), rewrites the
-- CfxLua-only syntax stock Lua 5.4 rejects, and loads the chunk. Modules that talk to a live
-- framework never get here: stubs.lua preloads fakes for them.
local L = {}

local here = (arg and arg[0] or 'run.lua'):gsub('\\', '/'):match('^(.*)/[^/]*$') or '.'

---@type string The resource folder (the parent of tests/), or TRAPPHONE_RESOURCE when set.
L.resource = os.getenv('TRAPPHONE_RESOURCE') or (here .. '/..')

---@type table<string, boolean> Modules another slice writes. When the file isn't there yet the
---harness hands back an empty table instead of failing, so this slice can be tested alone.
L.optional = {
    ['configs.server.lines'] = true,
}

---Rewrite one compound assignment (`a += b`) on a line into plain Lua. Handles the statement
---standing alone and sitting inside a one-line `if ... then a += 1 end`.
---@param line string
---@return string line
local function compound(line)
    local head, target, op, rest = line:match('^(.-)([%a_][%w_%.%[%]\'"]*)%s*([%+%-%*/])=%s*(.+)$')
    if not head or head:find('%-%-') then return line end

    -- Anything that isn't a statement start in front of the target means this is not an
    -- assignment (a comparison, a string, a comment).
    if not (head:match('^%s*$') or head:match('then%s+$') or head:match('do%s+$') or head:match('else%s+$')) then
        return line
    end

    local value, tail = rest:match('^(.-)(%s+end%s*)$')
    if not value then value, tail = rest, '' end

    local comment = ''
    local cut = value:find('%s*%-%-')
    if cut then value, comment = value:sub(1, cut - 1), value:sub(cut) end

    return ('%s%s = %s %s (%s)%s%s'):format(head, target, target, op, value, tail, comment)
end

---Rewrite CfxLua extensions so stock load() accepts the file.
---  `name`   -> joaat("name")   backtick hash literals
---  a += b   -> a = a + (b)     compound assignment (also -=, *=, /=)
---  a?.b     -> a.b             safe navigation, approximated as plain indexing
---@param src string file contents
---@return string plain
function L.preprocess(src)
    src = src:gsub('`([^`\n]*)`', 'joaat("%1")')
    src = src:gsub('([%w_%]%)])%?%.([%a_][%w_]*)', '%1.%2')

    local out = {}

    for line in (src .. '\n'):gmatch('(.-)\r?\n') do
        out[#out + 1] = compound(line)
    end

    return table.concat(out, '\n')
end

---Read a whole file.
---@param path string
---@return string|nil contents
function L.readFile(path)
    local f = io.open(path, 'rb')
    if not f then return nil end

    local s = f:read('a')
    f:close()

    return s
end

---Compile a resource file without running it.
---@param rel string path inside the resource, e.g. 'client/trapphone/world.lua'
---@return function|nil chunk
---@return string|nil err
function L.compile(rel)
    local path = L.resource .. '/' .. rel
    local src = L.readFile(path)
    if not src then return nil, 'missing file ' .. path end

    return load(L.preprocess(src), '@' .. rel)
end

---The package searcher: resource modules by dotted name.
---@param name string
local function searcher(name)
    local rel = name:gsub('%.', '/') .. '.lua'
    local src = L.readFile(L.resource .. '/' .. rel)

    if not src then
        if L.optional[name] then
            return function() return {} end, rel
        end

        return ('\n\tno resource file ' .. rel)
    end

    local chunk, err = load(L.preprocess(src), '@' .. rel)
    if not chunk then error(('resource file %s failed to compile: %s'):format(rel, err)) end

    return chunk, rel
end

table.insert(package.searchers, 2, searcher)

return L
