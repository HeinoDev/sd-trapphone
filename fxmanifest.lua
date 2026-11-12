fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'sd-trapphone'
author 'Samuel#0008'
version '1.0.0'
description 'Trap Phone - a keypad burner that runs a street business: corner sales, drop-offs, plugs, turf'

shared_scripts {
    '@ox_lib/init.lua',
    'bridge/shared/init.lua',
}

client_scripts {
    'bridge/client/init.lua',
    'client/main.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'bridge/server/init.lua',
    'server/main.lua',
}

-- The in-hand handset, one model per colour (stream/, built by tools/build_prop.py).
data_file 'DLC_ITYP_REQUEST' 'stream/sd_trapphone.ytyp'

ui_page 'web/build/index.html'

files {
    'bridge/**.lua',
    'shared/**.lua',
    'configs/config.lua',
    'configs/shared/**.lua',
    'client/**.lua',
    'locales/*.json',
    'web/build/index.html',
    'web/build/assets/*.js',
    'web/build/assets/*.css',
    'web/build/assets/*.woff2',
    'stream/sd_trapphone.ytyp',
}

-- Framework (qb-core/qbx_core or es_extended), inventory (ox_inventory, qb-inventory,
-- qs-inventory, tgiann-inventory, ...) and target (ox_target, qb-target, qtarget) are
-- detected at runtime by the bridge, so none of them are hard dependencies. sd-phone is
-- optional: when it is running, contacts can also reach the player's real phone.
dependencies {
    'ox_lib',
    'oxmysql',
}
