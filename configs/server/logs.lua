-- SERVER-ONLY (not in fxmanifest files{}): audit logging, routed through
-- server/trapphone/audit.lua to ox_lib lib.logger (backend picked by the `ox:logger` convar).
return {
    Enabled = true, -- master switch: false disables ALL audit logging

    -- Per-event switches; a missing key counts as on.
    Events = {
        phone_created = true, -- a new phone id was stamped onto an item
        sale = true, -- a corner / car / pitched sale completed
        drop = true, -- a drop-off completed
        haggle = false, -- every counter-offer (noisy)
        level_up = true, -- a phone levelled a product family
        contact_met = true, -- a special contact was unlocked
        order = true, -- a plug / supplier order was collected
        bribe = true, -- protection bought from a crew
        tax = true, -- a turf tax was paid or refused
        riot = true, -- a riot started or ended
        wash = true, -- dirty money washed
        market = true, -- a black market purchase
        bagging = false, -- scales used (noisy)
        snitch = true, -- an alert went out
        admin_command = true, -- a privileged admin command was run
        suspect = true, -- a server-authoritative reject that smells like an exploit attempt
    },
}
