# Exports

This resource exposes client-side and server-side exports. Call client exports from client resources and server exports from server resources. State-changing client exports are validated and paced by the server.

## Client exports

| Export | Description |
| --- | --- |
| `isCornerSelling()` | Whether the player is corner selling. |
| `isDoingDropOffs()` | Whether the player is on a drop-off run. |
| `isBusy()` | Whether the resource is handling a sale, meeting, bagging up, or another activity. |
| `sendMessage(text, sender?)` | Sends a message to the player's own phone. Returns a boolean. Text must be non-empty; sender is optional. |
| `addContact(contact)` | Saves a plain contact on the player's own phone. Pass `{ number, name }`; returns a boolean. |
| `meetNewContact()` | Points the map at a pending introduction or asks for one, using the normal unlock rules and odds. |
| `getPedRelationship(pedKey)` | Gets the player's relationship value for a ped key. |
| `updatePedRelationship(pedKey, amount)` | Updates the player's relationship with a ped, subject to server limits. |

The handset also registers `getActivePhone`, `isOpen`, and `usePhone` directly.

## Server exports

| Export | Description |
| --- | --- |
| `sendMessageToPhone(from, to, text)` | Sends a message from one phone number to another. Returns a boolean. |
| `addContactToPhone(phoneId, contact)` | Adds `{ number, name, type? }` to a phone; returns a boolean. |
| `getContact(phoneId, number)` | Returns a saved contact or `nil`. |
| `getAllContacts(phoneId)` | Returns all saved contacts. |
| `verifyPhoneOwnership(src, phoneId)` | Whether player server ID `src` currently carries the phone. |
| `addXP(src, family, amount)` | Adds XP in a configured product family to the phone the player carries; returns the resulting level or `false`. |
| `removeXP(src, family, amount)` | Removes XP in a configured product family; returns the resulting level or `false`. |
| `increaseGangRep(src, gang, amount)` / `decreaseGangRep(src, gang, amount)` | Adjusts a player's standing with a configured crew; returns the new standing or `false`. |
| `increaseJobGangRep(job, gang, amount)` / `decreaseJobGangRep(job, gang, amount)` | Adjusts a shared-rep job's standing with a configured crew; returns the new standing or `false`. |
