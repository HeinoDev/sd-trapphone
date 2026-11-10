# sd-trapphone

A keypad burner phone that runs a street business. Part of the sd-phone family, but its own
device: an early-2000s candybar with a colour screen, a d-pad and a full keypad.

## What it does

- **The handset.** Messages, Contacts, Hustle, Turf, Status, a Worm game, ringtones and five
  wallpapers. Works with the mouse, the keyboard, or both. You can still walk and drive with
  it out.
- **Ten colours.** Each colour is its own item with its own model in the hand, and the item
  decides the faceplate on screen: graphite, chrome, pearl, bling, ice, bubblegum, lime,
  cherry, grape and tangerine.
- **Texts sd-phone.** With sd-phone running, a burner and a smartphone can text each other.
  The burner shows up in the smartphone's Messages under its own number, and replies come back.
- **Corner selling.** Start serving from the phone. Customers text an offer and walk over, or
  pull up in a car at a spot you mark. Accept, name your own price, or turn them down.
- **Pitching.** Walk up to anyone and offer. Some say no. Some of those call it in.
- **Drop-offs.** Take orders while driving and deliver to doors across the map.
- **A name on the street.** XP and levels per product, kept on the phone itself, so a stolen
  phone is a stolen business. Customers remember you; good ones become named regulars.
- **People.** Plugs, a supplier, an informant, a launderer, a fixer and each crew's shot
  caller reach out as your name grows. Order weight, buy tips, pay for protection.
- **Turf.** Every area has money, a product it craves and often a crew. Sell on their block
  without paying and they come and ask. Enough dead members and they riot.
- **Back rooms.** A money wash and a black market that open once you know the right person.
- **Bagging up.** Battery-powered scales break bricks and ounces into smaller bags.
- **Heat.** Snitches and witnesses bring the police through your dispatch resource.

## Install

1. Put `sd-trapphone` in your resources and `ensure sd-trapphone` after `ox_lib`, `oxmysql`
   and your framework. The database tables create themselves.
2. Add the items from [items.md](items.md) to your inventory.
3. Go through `configs/`. Prices, XP and locations are in `configs/server/`, which never
   reaches a client.

Framework (QBCore, Qbox, ESX), inventory, target and dispatch are detected at runtime.

## The prop

`stream/` holds one model per colour (`sd_trapphone_<colour>`, about 4,700 triangles, texture
embedded). They are built from the handset page itself, so the prop matches what is on screen:

1. Capture `#prop=<colour>` and `#propback=<colour>` from the page (see `tools/make_textures.py`).
2. `python tools/make_textures.py` composes the textures and the inventory icons in `images/`.
3. `blender --python tools/build_prop.py -- report.json` builds and exports every colour.
   Needs Blender 5.x with the Sollumz extension.

## Rebuilding the handset

The built page ships in `web/build`. To change it:

```
cd web
npm install
npm run dev      # the handset in a browser, with mock data
npm run build
```

## Tests

`lua tests/run.lua` runs the offline checks for pricing, levels and zones under stock Lua 5.4.

## For other resources

Exports are listed in [docs/design.md](docs/design.md).
