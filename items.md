# Item definitions

## ox_inventory

Everything Trap Phone needs added to `ox_inventory/data/items.lua`. Paste the blocks below into that file's item table, and copy the images from this resource's `images/` folder into `ox_inventory/web/images/` (an item with no image there simply shows without one).

### The phones and the tools

The handset comes in ten colours. Each is its own item with its own model in the hand, and the
item decides the faceplate on screen. Add them all, or only the colours you want to sell.

```lua
    ['trap_phone_graphite'] = {
        label = 'Trap Phone (Graphite)',
        weight = 190,
        stack = false,
        close = true,
        consume = 0,
        description = 'A prepaid keypad burner. Whoever holds it holds the business.',
        client = { export = 'sd-trapphone.usePhone', image = 'trap_phone_graphite.png' },
    },

    ['trap_phone_chrome'] = {
        label = 'Trap Phone (Chrome)',
        weight = 190,
        stack = false,
        close = true,
        consume = 0,
        description = 'A prepaid keypad burner. Whoever holds it holds the business.',
        client = { export = 'sd-trapphone.usePhone', image = 'trap_phone_chrome.png' },
    },

    ['trap_phone_pearl'] = {
        label = 'Trap Phone (Pearl)',
        weight = 190,
        stack = false,
        close = true,
        consume = 0,
        description = 'A prepaid keypad burner. Whoever holds it holds the business.',
        client = { export = 'sd-trapphone.usePhone', image = 'trap_phone_pearl.png' },
    },

    ['trap_phone_bling'] = {
        label = 'Trap Phone (Bling)',
        weight = 190,
        stack = false,
        close = true,
        consume = 0,
        description = 'A prepaid keypad burner. Whoever holds it holds the business.',
        client = { export = 'sd-trapphone.usePhone', image = 'trap_phone_bling.png' },
    },

    ['trap_phone_ice'] = {
        label = 'Trap Phone (Ice)',
        weight = 190,
        stack = false,
        close = true,
        consume = 0,
        description = 'A prepaid keypad burner. Whoever holds it holds the business.',
        client = { export = 'sd-trapphone.usePhone', image = 'trap_phone_ice.png' },
    },

    ['trap_phone_bubblegum'] = {
        label = 'Trap Phone (Bubblegum)',
        weight = 190,
        stack = false,
        close = true,
        consume = 0,
        description = 'A prepaid keypad burner. Whoever holds it holds the business.',
        client = { export = 'sd-trapphone.usePhone', image = 'trap_phone_bubblegum.png' },
    },

    ['trap_phone_lime'] = {
        label = 'Trap Phone (Lime)',
        weight = 190,
        stack = false,
        close = true,
        consume = 0,
        description = 'A prepaid keypad burner. Whoever holds it holds the business.',
        client = { export = 'sd-trapphone.usePhone', image = 'trap_phone_lime.png' },
    },

    ['trap_phone_cherry'] = {
        label = 'Trap Phone (Cherry)',
        weight = 190,
        stack = false,
        close = true,
        consume = 0,
        description = 'A prepaid keypad burner. Whoever holds it holds the business.',
        client = { export = 'sd-trapphone.usePhone', image = 'trap_phone_cherry.png' },
    },

    ['trap_phone_grape'] = {
        label = 'Trap Phone (Grape)',
        weight = 190,
        stack = false,
        close = true,
        consume = 0,
        description = 'A prepaid keypad burner. Whoever holds it holds the business.',
        client = { export = 'sd-trapphone.usePhone', image = 'trap_phone_grape.png' },
    },

    ['trap_phone_tangerine'] = {
        label = 'Trap Phone (Tangerine)',
        weight = 190,
        stack = false,
        close = true,
        consume = 0,
        description = 'A prepaid keypad burner. Whoever holds it holds the business.',
        client = { export = 'sd-trapphone.usePhone', image = 'trap_phone_tangerine.png' },
    },

    ['scales'] = {
        label = 'Digital Scales',
        weight = 400,
        stack = false,
        close = true,
        consume = 0,
        description = 'Pocket scales, accurate to a tenth of a gram. Runs on batteries.',
        client = { export = 'sd-trapphone.useScales', image = 'scales.png' },
    },

    ['batteries'] = {
        label = 'Batteries',
        weight = 40,
        stack = true,
        close = true,
        consume = 0,
        description = 'A pair of AAA batteries. Use them to put a fresh charge in your scales.',
        client = { export = 'sd-trapphone.useBatteries', image = 'batteries.png' },
    },

    ['baggies'] = {
        label = 'Baggies',
        weight = 1,
        stack = true,
        description = 'Small resealable bags, for grams and quarters.',
        client = { image = 'baggies.png' },
    },

    ['large_baggies'] = {
        label = 'Large Baggies',
        weight = 3,
        stack = true,
        description = 'Bigger resealable bags, for ounces.',
        client = { image = 'large_baggies.png' },
    },
```

### Product sizes

The gram items (`weedbaggy`, `cokebaggy`, `meth`) ship with most servers already. These are the bigger sizes the scales split down and the plugs sell; skip any your server already has.

```lua
    ['weed_7g'] = {
        label = 'Quarter of Weed',
        weight = 7,
        stack = true,
        description = 'Seven grams, bagged.',
        client = { image = 'weed_7g.png' },
    },

    ['weed_1oz'] = {
        label = 'Ounce of Weed',
        weight = 28,
        stack = true,
        description = 'A full ounce, vacuum packed.',
        client = { image = 'weed_1oz.png' },
    },

    ['weed_brick'] = {
        label = 'Brick of Weed',
        weight = 1000,
        stack = true,
        description = 'A pressed kilo. Needs weighing out before it is worth anything on a corner.',
        client = { image = 'weed_brick.png' },
    },

    ['coke_7g'] = {
        label = 'Quarter of Coke',
        weight = 7,
        stack = true,
        description = 'Seven grams, bagged.',
        client = { image = 'coke_7g.png' },
    },

    ['coke_1oz'] = {
        label = 'Ounce of Coke',
        weight = 28,
        stack = true,
        description = 'A full ounce, wrapped tight.',
        client = { image = 'coke_1oz.png' },
    },

    ['coke_brick'] = {
        label = 'Brick of Coke',
        weight = 1000,
        stack = true,
        description = 'A stamped kilo. Needs weighing out before it is worth anything on a corner.',
        client = { image = 'coke_brick.png' },
    },

    ['meth_7g'] = {
        label = 'Quarter of Meth',
        weight = 7,
        stack = true,
        description = 'Seven grams, bagged.',
        client = { image = 'meth_7g.png' },
    },

    ['meth_1oz'] = {
        label = 'Ounce of Meth',
        weight = 28,
        stack = true,
        description = 'A full ounce of shards.',
        client = { image = 'meth_1oz.png' },
    },

    ['meth_brick'] = {
        label = 'Brick of Meth',
        weight = 1000,
        stack = true,
        description = 'A kilo of shards in a taped bag. Needs weighing out before it is worth anything on a corner.',
        client = { image = 'meth_brick.png' },
    },
```

If your server is missing the gram items too:

```lua
    ['weedbaggy'] = {
        label = 'Gram of Weed',
        weight = 1,
        stack = true,
        client = { image = 'weedbaggy.png' },
    },

    ['cokebaggy'] = {
        label = 'Gram of Coke',
        weight = 1,
        stack = true,
        client = { image = 'cokebaggy.png' },
    },

    ['meth'] = {
        label = 'Gram of Meth',
        weight = 1,
        stack = true,
        client = { image = 'meth.png' },
    },
```

## Other inventories (qb-inventory, qs-inventory, tgiann-inventory, ...)

The `client = { export = ... }` lines above are an ox_inventory feature. On other backends register the same item names in your framework's shared items; the resource registers the use handlers for `trap_phone`, `scales` and `batteries` itself at boot through the bridge.

For qb-core style shared items (`qb-core/shared/items.lua`):

```lua
    trap_phone_graphite = { name = 'trap_phone_graphite', label = 'Trap Phone (Graphite)', weight = 190, type = 'item', image = 'trap_phone_graphite.png', unique = true, useable = true, shouldClose = true, description = 'A prepaid keypad burner. Whoever holds it holds the business.' },
    trap_phone_chrome = { name = 'trap_phone_chrome', label = 'Trap Phone (Chrome)', weight = 190, type = 'item', image = 'trap_phone_chrome.png', unique = true, useable = true, shouldClose = true, description = 'A prepaid keypad burner. Whoever holds it holds the business.' },
    trap_phone_pearl = { name = 'trap_phone_pearl', label = 'Trap Phone (Pearl)', weight = 190, type = 'item', image = 'trap_phone_pearl.png', unique = true, useable = true, shouldClose = true, description = 'A prepaid keypad burner. Whoever holds it holds the business.' },
    trap_phone_bling = { name = 'trap_phone_bling', label = 'Trap Phone (Bling)', weight = 190, type = 'item', image = 'trap_phone_bling.png', unique = true, useable = true, shouldClose = true, description = 'A prepaid keypad burner. Whoever holds it holds the business.' },
    trap_phone_ice = { name = 'trap_phone_ice', label = 'Trap Phone (Ice)', weight = 190, type = 'item', image = 'trap_phone_ice.png', unique = true, useable = true, shouldClose = true, description = 'A prepaid keypad burner. Whoever holds it holds the business.' },
    trap_phone_bubblegum = { name = 'trap_phone_bubblegum', label = 'Trap Phone (Bubblegum)', weight = 190, type = 'item', image = 'trap_phone_bubblegum.png', unique = true, useable = true, shouldClose = true, description = 'A prepaid keypad burner. Whoever holds it holds the business.' },
    trap_phone_lime = { name = 'trap_phone_lime', label = 'Trap Phone (Lime)', weight = 190, type = 'item', image = 'trap_phone_lime.png', unique = true, useable = true, shouldClose = true, description = 'A prepaid keypad burner. Whoever holds it holds the business.' },
    trap_phone_cherry = { name = 'trap_phone_cherry', label = 'Trap Phone (Cherry)', weight = 190, type = 'item', image = 'trap_phone_cherry.png', unique = true, useable = true, shouldClose = true, description = 'A prepaid keypad burner. Whoever holds it holds the business.' },
    trap_phone_grape = { name = 'trap_phone_grape', label = 'Trap Phone (Grape)', weight = 190, type = 'item', image = 'trap_phone_grape.png', unique = true, useable = true, shouldClose = true, description = 'A prepaid keypad burner. Whoever holds it holds the business.' },
    trap_phone_tangerine = { name = 'trap_phone_tangerine', label = 'Trap Phone (Tangerine)', weight = 190, type = 'item', image = 'trap_phone_tangerine.png', unique = true, useable = true, shouldClose = true, description = 'A prepaid keypad burner. Whoever holds it holds the business.' },
    scales        = { name = 'scales', label = 'Digital Scales', weight = 400, type = 'item', image = 'scales.png', unique = true, useable = true, shouldClose = true, description = 'Pocket scales, accurate to a tenth of a gram. Runs on batteries.' },
    batteries     = { name = 'batteries', label = 'Batteries', weight = 40, type = 'item', image = 'batteries.png', unique = false, useable = true, shouldClose = true, description = 'A pair of AAA batteries. Use them to put a fresh charge in your scales.' },
    baggies       = { name = 'baggies', label = 'Baggies', weight = 1, type = 'item', image = 'baggies.png', unique = false, useable = false, shouldClose = false, description = 'Small resealable bags, for grams and quarters.' },
    large_baggies = { name = 'large_baggies', label = 'Large Baggies', weight = 3, type = 'item', image = 'large_baggies.png', unique = false, useable = false, shouldClose = false, description = 'Bigger resealable bags, for ounces.' },

    weed_7g       = { name = 'weed_7g', label = 'Quarter of Weed', weight = 7, type = 'item', image = 'weed_7g.png', unique = false, useable = false, shouldClose = false, description = 'Seven grams, bagged.' },
    weed_1oz      = { name = 'weed_1oz', label = 'Ounce of Weed', weight = 28, type = 'item', image = 'weed_1oz.png', unique = false, useable = false, shouldClose = false, description = 'A full ounce, vacuum packed.' },
    weed_brick    = { name = 'weed_brick', label = 'Brick of Weed', weight = 1000, type = 'item', image = 'weed_brick.png', unique = false, useable = false, shouldClose = false, description = 'A pressed kilo.' },
    coke_7g       = { name = 'coke_7g', label = 'Quarter of Coke', weight = 7, type = 'item', image = 'coke_7g.png', unique = false, useable = false, shouldClose = false, description = 'Seven grams, bagged.' },
    coke_1oz      = { name = 'coke_1oz', label = 'Ounce of Coke', weight = 28, type = 'item', image = 'coke_1oz.png', unique = false, useable = false, shouldClose = false, description = 'A full ounce, wrapped tight.' },
    coke_brick    = { name = 'coke_brick', label = 'Brick of Coke', weight = 1000, type = 'item', image = 'coke_brick.png', unique = false, useable = false, shouldClose = false, description = 'A stamped kilo.' },
    meth_7g       = { name = 'meth_7g', label = 'Quarter of Meth', weight = 7, type = 'item', image = 'meth_7g.png', unique = false, useable = false, shouldClose = false, description = 'Seven grams, bagged.' },
    meth_1oz      = { name = 'meth_1oz', label = 'Ounce of Meth', weight = 28, type = 'item', image = 'meth_1oz.png', unique = false, useable = false, shouldClose = false, description = 'A full ounce of shards.' },
    meth_brick    = { name = 'meth_brick', label = 'Brick of Meth', weight = 1000, type = 'item', image = 'meth_brick.png', unique = false, useable = false, shouldClose = false, description = 'A kilo of shards in a taped bag.' },
```

qs-inventory reads the same shape from `qs-inventory/shared/items.lua`. On ESX without a slot inventory, add the same names to the `items` table in your database.

Notes:

- The `trap_phone_<colour>` items must not stack. With `UniqueMetadataPhones` on (`configs/shared/phone.lua`) each phone carries its own business in its metadata (`trapId`), and two phones in one stack would share it.
- `scales` should not stack either: the battery charge is stored on the item (`battery`, 0 to 100). On an inventory that cannot store metadata the scales simply never run down.
- `batteries` are taken by the server when a charge is replaced, so the item itself is not consumed on use (`consume = 0`).
- `baggies` and `large_baggies` are only used up when `UseBaggies` is on in `configs/shared/scales.lua`.
- Every product item name comes from `configs/shared/drugs.lua`. If your server already has its own names for these sizes, change them there (and the matching keys in `configs/server/economy.lua` and the plugs' stock in `configs/server/contacts.lua`) instead of adding duplicates.
- The default black market (`configs/server/services.lua`) and supplier stock also reference items assumed to exist on your server: `lockpick`, `armour`, `weapon_knife`, `weapon_pistol`, `weapon_microsmg` and `ammo-9`. All of them are plain config values; swap any for your own items.
