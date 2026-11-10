# sd-trapphone design

A keypad burner phone that runs a street business, built on the sd-deaddrop stack, with an
early-2000s candybar handset as the interface.

This file is the contract between the parts. The core (written first, read it) is real code:

- `configs/**` every tunable. Server-only files never ship to clients.
- `server/trapphone/store.lua` SQL. `phones.lua` live phones, messages, contacts, snapshot.
  `progress.lua` XP and levels. `relations.lua` signed standing values. `audit.lua` logs.
- `client/trapphone/phone.lua` the handset: open/close, prop, page plumbing.
- `shared/zones.lua`, `shared/levels.lua`, `shared/log.lua`, `shared/items.lua`.
- `web/` the handset page (React 19, Vite, Tailwind, zustand).

Style: copy sd-deaddrop. One module per file, `local x = {}` ... `return x`, LuaLS
annotations on every function and module-level local, `require` at the top with a typed
comment, config read into a `CFG` local, server-authoritative everything, `log.*` for console,
`audit.log` for the trail, `locale('key')` for every player-facing string. Comments say why,
in plain words. No globals. CfxLua syntax (`+=`, backtick hashes, `?.`) is fine.

## Rules that are not negotiable

1. The client is never trusted. Every callback validates type, range, ownership and, where
   a place matters, the player's real position (`GetEntityCoords(GetPlayerPed(src))`).
2. Money and items move only on the server, only after validation, items before money on a
   sale (remove the product, then pay), money before items on a purchase.
3. A sale exists only as a server ticket. The client asks, the server rolls and remembers.
4. Every ped, vehicle, object and blip the client creates is registered with
   `client.trapphone.world` so it is removed on cancel, timeout and resource stop.
5. Never restart-unsafe: no leaked NUI focus, no frozen player, no orphan entities.
6. `IsPlayerAceAllowed` returns the number 1 on this server build: test truthiness, never `== true`.

## Naming

- Net events: `sd-trapphone:server:<name>` / `sd-trapphone:client:<name>`.
- ox_lib callbacks: `sd-trapphone:server:<name>`.
- NUI messages (Lua to page) and NUI callbacks (page to Lua): `trap:<area>:<name>`.
- Tables: `trapphone_phones`, `trapphone_relations` (already created by store.lua).

## Phone state (what the page draws)

`phones.snapshot` builds it; `phones.push(phone, patch)` replaces top-level keys;
`phones.addPart(name, fn)` adds a section; `phones.refresh(phone, name)` re-sends one.

```
PhoneState = {
  phone    = { id, number },
  settings = { shell, wallpaper, ringtone, volume },
  threads  = Thread[]            -- newest first
  contacts = Contact[]
  scores   = { [game] = best },
  stats    = { sales, earned, drops },
  now      = os.time(),
  rep      = { family, label, color, title, level?, bars 0..5 }[]   -- part, progress.lua
  hustle   = Hustle              -- part, selling.lua
  turf     = Turf                -- part, turf.lua
}
Thread  = { number, name, kind 'customer'|'contact'|'player'|'system', unread, ts, msgs = Message[] }
Message = { id, from 'me'|'them', text, ts, offer? = Offer }
Contact = { number, name, type (key of config.Contacts.Types), key?, gang? }
Offer   = { ticketId, kind 'corner'|'car'|'pitch'|'drop', item, label, family, unit, qty,
            price (total, integer), state 'open'|'accepted'|'declined'|'done'|'expired'|'walked',
            counters (haggles left), expires (os.time), place? (drop-offs: street name) }
Hustle  = { mode 'idle'|'corner'|'drops', family (family key or 'any'), spotSet boolean,
            queue (open drop-off orders), dropsEnabled boolean, blocked? (localized reason
            selling can't start, e.g. not enough police),
            products = { family, label, color, items = { item, label, unit, count }[] }[] }
Turf    = { zone = { id, label, wealth, wealthLabel },
            gang? = { id, label, color, standing (id), standingLabel, protectedUntil? (os.time) },
            heat 0..100,
            demand = { family, label, color, level 'low'|'normal'|'high' }[] }
```

Server to client events already wired by the core: `client:state` (patch), `client:message`
(`{ number, name, kind, unread, msg, silent }`), `client:offer` (`{ number, ticketId, offer }`),
`client:use` (slot).

## Page protocol

Lua to page (`phone.send(action, data)`): `trap:open { state, setup, clock }`, `trap:close`,
`trap:state patch`, `trap:message payload`, `trap:offer payload`, `trap:clock { h, m }`,
`trap:toast { text, tone 'info'|'good'|'bad' }` (a line on the phone screen).

Page to Lua, registered by the core: `trap:close`, `trap:typing { on }`, `trap:ui:locale`,
`trap:settings:set { key, value }`, `trap:thread:read { number }`, `trap:thread:delete { number }`,
`trap:contact:add { number, name }`, `trap:contact:delete { number }`,
`trap:message:send { number, text }`, `trap:score:submit { game, score }`.

Page to Lua, registered by the slices. Every reply is `{ ok, error? (localized text), data? }`.

| Callback | Body | Owner |
|---|---|---|
| `trap:hustle:start` | `{ mode 'corner'|'drops', family }` | street |
| `trap:hustle:stop` | | street |
| `trap:hustle:setSpot` / `trap:hustle:clearSpot` | | street |
| `trap:offer:respond` | `{ number, ticketId, action 'accept'|'decline'|'counter', price? }` | street |
| `trap:turf:refresh` | (reply data = Turf) | network |
| `trap:contact:action` | `{ number, action, args? }` | network |

Contact actions (`config.Contacts.Types[type].actions` plus `share` and `route`):

- `order` with no args: `data = { items = { item, label, price, max, locked? }[], cooldown? (seconds left) }`.
  With `args.lines = { item, qty }[]`: places the order. The contact texts a meeting place;
  the player pays and collects there.
- `bribe`: no args returns `data = { price, hours, allowed, reason? }`; `args.confirm` pays.
- `standing`: `data = { label, standingLabel, protectedUntil? }`.
- `intel`: no args returns `data = { price }`; `args.confirm` pays and the tip arrives as a text.
- `wash` / `market`: marks the place on the map (`data = { label }`).
- `route`: sets the waypoint to this contact's pending meet, if there is one.
- `share`: hands the number to the nearest player holding a trap phone (needs `CanPassNumbers`).

## Gameplay

### Corner selling (street slice)

1. Phone > Hustle > Start. `selling.start` checks: has a phone, police requirement, holds at
   least one street-sellable item of the chosen family. Creates a session `{ src, phoneId,
   mode, family, next (os.time) }`.
2. The client loop asks `requestCustomer` on its own timer. The server rate-limits (customer
   interval, then the per-item cooldown) and either says "not yet" or creates a ticket: it
   picks an item the player actually holds, a quantity, the zone from the player's real
   position, and rolls the offer with `shared/pricing.lua` (pure, tested offline).
3. The client finds an ambient ped (or creates one: `NoPedsServer`, or a car buyer when a
   pull-up spot is set and the roll says so), reports the ped's look (`world.pedKey`), and
   the server finalises personality and relationship from that key and texts the offer.
4. The player accepts, declines or counters from the phone, or simply serves the ped.
   A counter is a server roll (`config.Economy.Haggle`, personality, relationship).
5. Hand-off: client plays it, then `completeSale { ticketId }`. Server checks the ticket is
   theirs, open or accepted, old enough (`MinServeSeconds`), not expired, and the items are
   still there; removes items, pays, adds XP, moves the relationship, updates stats, calls
   `turf.onSale`, rolls a witness snitch and a robbery.
6. Pitching: a target option on ambient peds. `pitch { pedKey }` either refuses (XP loss,
   maybe a snitch) or returns a ticket that is served on the spot.

Regulars: a ped look whose relationship passes `RegularAt` gets a generated name and is
saved as a `regular` contact; their offers arrive under that name.

### Drop-offs (street slice)

Started from the phone in a vehicle. The server queues orders (`config.Deliveries`), each a
ticket with `kind = 'drop'` pointing at a door at a sensible distance. Accepting sets a
blip and waypoint; the customer is created when the player gets close; `completeDrop`
validates the player's real distance to the door.

### Dispatch (street slice)

`server.trapphone.dispatch`: `policeCount()`, `canSell() -> ok, reason`, `heat(src)`,
`alert(src, reason) -> sent` (cooldown, raises heat, tells the seller's client to fire the
dispatch bridge), `snitch(src, scale, kind)` (rolls, then alerts after a delay).

### Turf and gangs (network slice)

`server.trapphone.turf`: `zoneOf(src) -> zone`, `isIgnored(src)`,
`onSale(src, phone, zone, total)` (rep, tax tally, encounter roll), plus the `turf` part.
Encounters: members are created client-side near the player and either demand tax (pay or
refuse, with a timer) or attack outright when standing is hostile. Bribes buy protection.
Gang kills are reported by the killer's client and counted per shared-rep job; enough of
them starts a riot (waves of armed members sent at that job's players on the turf).

### Special contacts (network slice)

On a level-up, `IntroChance` picks an eligible contact not yet met. They text from their
number with a meeting place. Meeting them (target on the ped) saves the contact and logs
`contact_met`. Orders, intel, bribes then work from the phone as in the table above.

### Services and scales (network slice)

Money wash and black market: attendants at server-only locations, sent to a client only
when that phone holds the unlocking contact type. ox_lib dialogs for amounts and stock.
Scales: use the item, pick a split, wait through a progress bar with the prop; the server
swaps items, drains the battery (item metadata), consumes baggies when enabled.

## Shared helpers the slices expose to each other

`client.trapphone.world` (street slice writes it, both use it):

```
world.track(kind 'ped'|'vehicle'|'object'|'blip', handle) -> handle
world.release(handle)                 -- delete one tracked thing now
world.cleanupAll()
world.groundAt(x, y, z) -> z
world.spawnPed(model, coords vec4, opts? { frozen, invincible, scenario }) -> ped|nil   -- local, snapped to ground
world.pedKey(ped) -> string           -- stable look key: model + head drawable + texture
world.faceEachOther(a, b)
world.handOff(ped, opts { give? model, take? model, large? boolean })   -- both sides of a hand-to-hand
world.cinematic(entity, ms, enabled) -- short scripted camera on a deal; no-op when disabled
world.blip(coords, opts { sprite, colour, scale, label, route? }) -> blip
world.setBusy(name, on) / world.isBusy() / world.busy(name)
```

`server.trapphone.selling` exposes `selling.mode(src) -> 'idle'|'corner'|'drops'`.

## Colours and the prop

The handset comes in ten colours (`config.Phone.Items`: item name -> faceplate id). The item
decides the faceplate on screen (`PhoneState.phone.shell`) and the model in the hand
(`sd_trapphone_<id>`, stream/). Nothing names an item directly: `shared/handsets.lua` answers
"is this a trap phone" and "does this player carry one".

## sd-phone link

`server/trapphone/sdphone.lua`, optional. A burner's text to a smartphone number goes in through
sd-phone's `sendSystemMessage` export; a smartphone's text to a burner number is picked up from
the server-side `sd-phone:server:messages:sent` event. Nothing in sd-phone is changed. Burner
numbers are 7 digits and sd-phone's are 10, so the two never collide.

## Exports

Client: `getActivePhone`, `isOpen`, `usePhone` (core); `isCornerSelling`, `isDoingDropOffs`,
`isBusy`, `sendMessage(text, sender?)`, `addContact(contact)`, `meetNewContact()`,
`getPedRelationship(pedKey)`, `updatePedRelationship(pedKey, amount)`.

Server: `sendMessageToPhone(from, to, text)`, `addContactToPhone(phoneId, contact)`,
`getContact(phoneId, number)`, `getAllContacts(phoneId)`, `verifyPhoneOwnership(src, phoneId)`,
`addXP(src, family, amount)`, `removeXP(src, family, amount)`, `increaseGangRep(src, gang, amount)`,
`decreaseGangRep(src, gang, amount)`, `increaseJobGangRep(job, gang, amount)`,
`decreaseJobGangRep(job, gang, amount)`.
