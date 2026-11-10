---@type table sd-trapphone config root (configs/config.lua).
local config = require 'configs.config'
---@type table Handset items and colours (shared.handsets).
local handsets = require 'shared.handsets'
---@type table The handset (client.trapphone.phone).
local phone = require 'client.trapphone.phone'
---@type table Shared world helpers (client.trapphone.world): owns every entity we create.
local world = require 'client.trapphone.world'
---@type table Target bridge (bridge.client.target).
local target = require 'bridge.client.target'
---@type table Notify bridge (bridge.client.notify).
local notify = require 'bridge.client.notify'
---@type table Inventory bridge (bridge.client.inventory).
local inventory = require 'bridge.client.inventory'

---@type table Service switches and interaction style (config.Services), shared half.
local CFG = config.Services

---@class TrapSite
---@field kind 'wash'|'market'
---@field index integer the location's index on the server
---@field coords vector4
---@field model integer|nil attendant model
---@field blip integer|nil
---@field point table|nil lib.points point that brings the attendant in and out
---@field ped integer|nil the attendant, while the player is near
---@field prompt boolean the "press E" hint is showing

---@type table Services module; the table returned at end of file. The back rooms as the
---player finds them: an attendant at each place the server says this phone has unlocked.
local services = {}

---@type TrapSite[] Every unlocked location currently set up.
local sites = {}
---@type boolean Whether money is spinning right now.
local washing = false
---@type string What `sites` was last built from, so an unchanged list is not rebuilt.
local built = ''

---@type number How close the attendant appears, in metres.
local STAGE_DISTANCE = 50.0
---@type number How close a 'zone' style interaction prompts, in metres.
local PROMPT_DISTANCE = 2.0
---@type number Walking further than this from the laundry stops the wash.
local LEAVE_DISTANCE = 8.0
---@type integer The attendant used when a location names no model.
local FALLBACK_MODEL = `s_m_y_dealer_01`

---@type table<string, table> Shared config per service kind.
local KINDS = { wash = CFG.MoneyWash, market = CFG.BlackMarket }

---Thousands separator for money, e.g. 12500 -> "12,500".
---@param n number
---@return string text
local function comma(n)
    local s = tostring(math.floor(tonumber(n) or 0))

    while true do
        local grouped, k = s:gsub('^(-?%d+)(%d%d%d)', '%1,%2')
        s = grouped
        if k == 0 then break end
    end

    return s
end

---Whether the player is free to start dealing with an attendant.
---@return boolean free
local function free()
    return not washing and not world.isBusy() and not IsEntityDead(cache.ped) and not lib.progressActive()
end

---Wash dirty money at a laundry: ask how much, wait while it spins, collect. Walking off or
---cancelling hands the dirty money back.
---@param site TrapSite
local function openWash(site)
    if not free() then return end

    phone.close()

    local quote = lib.callback.await('sd-trapphone:server:washQuote', false, site.index)

    if not quote or not quote.ok then
        notify.show((quote and quote.error) or locale('services.no_answer'), 'error')
        return
    end

    local q = quote.data

    if q.max < 1 then
        notify.show(locale('services.wash_nothing'), 'error')
        return
    end

    local input = lib.inputDialog(locale('services.wash_title'), {
        {
            type = 'number',
            label = locale('services.wash_amount'),
            description = locale('services.wash_desc', comma(q.dirty), comma(q.max), math.floor(q.fee * 100 + 0.5)),
            min = 1,
            max = q.max,
            default = q.max,
            required = true,
        },
    })

    local amount = input and math.floor(tonumber(input[1]) or 0) or 0
    if amount < 1 or not free() then return end

    local start = lib.callback.await('sd-trapphone:server:washStart', false, site.index, amount)

    if not start or not start.ok then
        notify.show((start and start.error) or locale('services.no_answer'), 'error')
        return
    end

    washing = true
    world.setBusy('wash', true)

    -- Stay close while it spins.
    CreateThread(function()
        local spot = vec3(site.coords.x, site.coords.y, site.coords.z)

        while washing do
            if #(GetEntityCoords(cache.ped) - spot) > LEAVE_DISTANCE or IsEntityDead(cache.ped) then
                if lib.progressActive() then lib.cancelProgress() end
                break
            end

            Wait(500)
        end
    end)

    local done = lib.progressBar({
        duration = start.data.seconds * 1000,
        label = locale('services.wash_progress', comma(start.data.payout)),
        useWhileDead = false,
        canCancel = true,
        disable = { combat = true },
    })

    washing = false
    world.setBusy('wash', false)

    if done then
        local res = lib.callback.await('sd-trapphone:server:washFinish', false)

        if res and res.ok then
            notify.show(locale('services.wash_done', comma(res.data.payout)), 'success')
        else
            notify.show((res and res.error) or locale('services.no_answer'), 'error')
        end
    else
        lib.callback.await('sd-trapphone:server:washCancel', false)
        notify.show(locale('services.wash_cancelled'), 'error')
    end
end

---Ask how many of one thing to buy from the back room, then buy it.
---@param site TrapSite
---@param entry table { item, label, price, max }
local function buy(site, entry)
    local qty = 1

    if entry.max > 1 then
        local input = lib.inputDialog(entry.label, {
            {
                type = 'number',
                label = locale('services.market_qty'),
                description = locale('services.market_each', comma(entry.price)),
                min = 1,
                max = entry.max,
                default = 1,
                required = true,
            },
        })

        if not input then return end

        qty = math.floor(tonumber(input[1]) or 0)
    end

    if qty < 1 then return end

    local res = lib.callback.await('sd-trapphone:server:marketBuy', false, site.index, entry.item, qty)

    if res and res.ok then
        notify.show(locale('services.market_bought', res.data.qty, res.data.label, comma(res.data.total)), 'success')
    else
        notify.show((res and res.error) or locale('services.no_answer'), 'error')
    end
end

---Show what the back room sells this player.
---@param site TrapSite
local function openMarket(site)
    if not free() then return end

    phone.close()

    local res = lib.callback.await('sd-trapphone:server:marketStock', false, site.index)

    if not res or not res.ok then
        notify.show((res and res.error) or locale('services.no_answer'), 'error')
        return
    end

    local options = {}

    for _, entry in ipairs(res.data.items) do
        options[#options + 1] = {
            title = entry.label,
            description = locale('services.market_price', comma(entry.price)),
            icon = inventory.image(entry.item) or 'box',
            onSelect = function() buy(site, entry) end,
        }
    end

    if #options == 0 then
        options[1] = { title = locale('services.market_empty'), readOnly = true }
    end

    lib.registerContext({ id = 'trapphone_market', title = CFG.BlackMarket.Blip.label, options = options })
    lib.showContext('trapphone_market')
end

---Deal with the attendant at a site.
---@param site TrapSite
local function use(site)
    if site.kind == 'wash' then openWash(site) else openMarket(site) end
end

---The line an interaction shows, per service kind.
---@param kind 'wash'|'market'
---@return string label
local function useLabel(kind)
    return kind == 'wash' and locale('services.target_wash') or locale('services.target_market')
end

---Take a site's attendant out of the world.
---@param site TrapSite
local function unstage(site)
    if site.prompt then
        site.prompt = false
        lib.hideTextUI()
    end

    local ped = site.ped
    if not ped then return end

    site.ped = nil
    target.removeLocalEntity(ped)
    world.release(ped)
end

---Put a site's attendant in place.
---@param site TrapSite
local function stage(site)
    if site.ped then return end

    local ped = world.spawnPed(site.model or FALLBACK_MODEL, site.coords,
        { frozen = true, invincible = true, scenario = 'WORLD_HUMAN_STAND_IMPATIENT' })

    if not ped then return end

    -- The site may have been torn down while the model loaded.
    if not lib.table.contains(sites, site) then
        world.release(ped)
        return
    end

    site.ped = ped

    if KINDS[site.kind].Interaction ~= 'zone' then
        target.addLocalEntity(ped, {
            {
                name = ('trapphone_%s_%d'):format(site.kind, site.index),
                icon = site.kind == 'wash' and 'fa-solid fa-soap' or 'fa-solid fa-box-open',
                label = useLabel(site.kind),
                distance = 2.5,
                onSelect = function() CreateThread(function() use(site) end) end,
            },
        })
    end
end

---Remove every site: attendants, blips, points and prompts.
local function clear()
    local old = sites
    sites = {}
    built = ''

    for _, site in ipairs(old) do
        if site.point then site.point:remove() end
        unstage(site)
        world.release(site.blip)
    end
end

---Set up the locations the server says this player's phone has unlocked.
---@param list table { wash?: { coords, model }[], market?: { coords, model }[] }
local function build(list)
    if type(list) ~= 'table' then list = {} end

    -- Asked again on every phone open: leave the attendants alone when nothing changed.
    local parts = {}

    for _, kind in ipairs({ 'market', 'wash' }) do
        for index, location in ipairs(KINDS[kind].Enabled and type(list[kind]) == 'table' and list[kind] or {}) do
            parts[#parts + 1] = ('%s:%d:%.1f:%.1f:%s'):format(kind, index, location.coords.x, location.coords.y, tostring(location.model))
        end
    end

    local signature = table.concat(parts, '|')

    if signature == built then return end

    clear()
    built = signature

    for kind, cfg in pairs(KINDS) do
        local locations = cfg.Enabled and type(list[kind]) == 'table' and list[kind] or {}

        for index, location in ipairs(locations) do
            local site = { kind = kind, index = index, coords = location.coords, model = location.model, prompt = false }
            local spot = vec3(location.coords.x, location.coords.y, location.coords.z)

            site.blip = world.blip(spot, cfg.Blip)
            site.point = lib.points.new({ coords = spot, distance = STAGE_DISTANCE })

            function site.point:onEnter()
                CreateThread(function() stage(site) end)
            end

            function site.point:onExit()
                unstage(site)
            end

            if cfg.Interaction == 'zone' then
                -- No target resource needed: a hint up close and the E key.
                function site.point:nearby()
                    local near = self.currentDistance <= PROMPT_DISTANCE and free()

                    if near ~= site.prompt then
                        site.prompt = near
                        if near then lib.showTextUI(('[E] %s'):format(useLabel(kind))) else lib.hideTextUI() end
                    end

                    if near and IsControlJustReleased(0, 38) then
                        site.prompt = false
                        lib.hideTextUI()
                        CreateThread(function() use(site) end)
                    end
                end
            end

            sites[#sites + 1] = site
        end
    end
end

---Ask the server which back rooms the phone in the player's pocket opens.
local function sync()
    build(lib.callback.await('sd-trapphone:server:services', false))
end

RegisterNetEvent('sd-trapphone:client:services', build)

-- Opening the handset is when the server learns which phone this is, so ask again then,
-- unless what is already set up is in use.
AddEventHandler('sd-trapphone:client:opened', function()
    if washing then return end
    CreateThread(sync)
end)

CreateThread(function()
    Wait(6000)
    sync()
end)

-- The phone is gone (dropped, sold, taken): the doors it opened close again.
inventory.onUpdate(function()
    if #sites > 0 and not washing and not handsets.carried() then clear() end
end)

---How many back-room locations are currently set up for this player.
---@return integer count
function services.count()
    return #sites
end

return services
