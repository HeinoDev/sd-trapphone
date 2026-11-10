---@type table sd-trapphone config root (configs/config.lua).
local config = require 'configs.config'
lib.locale(config.Locale) -- locale from configs/config.lua's `Locale` (en fallback per-key)

---@type table Console log helper (shared.log).
local log = require 'shared.log'
---@type table Server-side persistence module (server.trapphone.store).
local store = require 'server.trapphone.store'
---@type table Live phones (server.trapphone.phones).
local phones = require 'server.trapphone.phones'
---@type table Inventory bridge (bridge.server.inventory).
local inventory = require 'bridge.server.inventory'

local ok, err = pcall(store.ensureSchema)
if not ok then log.error(nil, 'schema bootstrap failed: %s', err) end

math.randomseed(os.time())

require 'server.trapphone.progress' -- XP + levels per product family
require 'server.trapphone.relations' -- ped / gang standing storage
require 'server.trapphone.dispatch' -- heat, snitches, police alerts
require 'server.trapphone.turf' -- zones + gang standing, encounters, bribes, riots
require 'server.trapphone.selling' -- corner / car / pitched sales and haggling
require 'server.trapphone.dropoffs' -- delivery runs
require 'server.trapphone.contacts' -- special contacts: intros, meets, orders, intel
require 'server.trapphone.services' -- money wash + black market
require 'server.trapphone.scales' -- bagging up
require 'server.trapphone.sdphone' -- two-way texts with sd-phone smartphones (optional)
require 'server.trapphone.exports' -- the public server exports
require 'server.trapphone.admin' -- admin + debug commands

-- ox_inventory opens the phone through the item's client export (see items.md). Every other
-- inventory registers the item as usable here and tells the client which slot was used.
if inventory.system ~= 'ox_inventory' then
    for _, name in ipairs(require('shared.handsets').items()) do
        inventory.registerUsable(name, function(src, item)
            TriggerClientEvent('sd-trapphone:client:use', src, type(item) == 'table' and item.slot or nil)
        end)
    end
end

---Save every changed phone when the resource stops, so a restart loses nothing.
---@param resource string the stopping resource name
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    phones.flushAll(true)
end)

log.info(nil, 'ready')
