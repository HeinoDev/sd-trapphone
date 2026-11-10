---@type table sd-trapphone config root (configs/config.lua).
local config = require 'configs.config'
---@type table Console log helper (shared.log): tagged color-coded prints.
local log = require 'shared.log'

-- Load translations for this VM from configs/config.lua's `Locale` (en is always loaded first
-- as the per-key fallback). Must run before modules that build localized content at load time.
lib.locale(config.Locale)

require 'client.trapphone.phone' -- the handset: open/close, prop, page plumbing
require 'client.trapphone.world' -- shared ped/vehicle/blip helpers + cleanup registry
require 'client.trapphone.selling' -- customers on foot and in cars, pitching, the hand-off
require 'client.trapphone.dropoffs' -- delivery runs
require 'client.trapphone.contacts' -- meeting special contacts, collecting orders
require 'client.trapphone.turf' -- gang encounters, riots, gang-kill reporting
require 'client.trapphone.services' -- money wash + black market
require 'client.trapphone.scales' -- bagging up
require 'client.trapphone.dispatch' -- police alerts through the dispatch bridge
require 'client.trapphone.exports' -- the public client exports

---@type table Shared world helpers (client.trapphone.world): owns every entity we create.
local world = require 'client.trapphone.world'

---On resource stop, remove every ped, vehicle, prop and blip this resource created.
---@param resource string stopping resource name
AddEventHandler('onResourceStop', function(resource)
    if resource ~= cache.resource then return end
    world.cleanupAll()
    lib.hideTextUI() -- a service prompt may be showing (Services Interaction = 'zone')
end)

log.debug(nil, 'client loaded')
