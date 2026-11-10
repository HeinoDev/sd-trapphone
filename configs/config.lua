-- Aggregate config root, loaded by both sides via `require 'configs.config'`.
-- Scope-by-folder: configs/shared/ is read by client + server, configs/client/ is client-only,
-- and configs/server/ holds the sensitive data (prices, XP, stock, locations) - excluded from
-- fxmanifest files{}, so it never ships to a client. Server-only files are merged below on the
-- server ONLY.
local config = {
    Locale = 'en', -- lib.locale loads locales/<Locale>.json, falling back to en per-key
    Debug = false, -- dev logging, target zone outlines and the /trap_* test commands; off in production

    -- Bridge diagnostics (bridge/shared/debug.lua): very verbose per-call prints from the
    -- framework/inventory/target bridge. Separate from Debug so gameplay debugging doesn't
    -- drown in bridge traffic.
    DebugPrints = false,
    -- DebugCategories = { ['bridge:inventory'] = true },

    AdminAce = 'command.trapphone', -- ace needed for the admin commands (give phone, set xp, reset)

    -- Shared (client + server)
    Phone = require 'configs.shared.phone', -- the handset: items, prop, shells, wallpapers, ringtones
    Drugs = require 'configs.shared.drugs', -- sellable products: family, unit, hand prop (prices are server-only)
    Selling = require 'configs.shared.selling', -- customer search, timeouts, cinematics, ped/vehicle pools
    Zones = require 'configs.shared.zones', -- turf map: areas, wealth, which gang runs them
    Gangs = require 'configs.shared.gangs', -- gang display + ped groups (rep numbers are server-only)
    Contacts = require 'configs.shared.contacts', -- contact types as the phone shows them
    Scales = require 'configs.shared.scales', -- bagging up: splits, timings, battery
    Services = require 'configs.shared.services', -- money wash + black market switches and interaction style
}

if IsDuplicityVersion() then
    local function merge(dst, src)
        for k, v in pairs(src) do
            if type(v) == 'table' and type(dst[k]) == 'table' then merge(dst[k], v) else dst[k] = v end
        end
    end
    merge(config.Selling, require 'configs.server.selling')
    merge(config.Gangs, require 'configs.server.gangs')
    merge(config.Contacts, require 'configs.server.contacts')
    merge(config.Services, require 'configs.server.services')

    config.Economy = require 'configs.server.economy' -- prices, XP curve, payout account, zone demand
    config.Dispatch = require 'configs.server.dispatch' -- police requirement, snitches, alert odds
    config.Deliveries = require 'configs.server.deliveries' -- drop-off queue + the door list
    config.Dialogue = require 'configs.server.dialogue' -- what customers text, by personality and moment
    config.Lines = require 'configs.server.lines' -- what contacts and gangs text
    config.Logs = require 'configs.server.logs' -- audit logging toggles
end

return config
