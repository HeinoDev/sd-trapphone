-- Contact types as the phone shows them. Who exists, what they stock and where they meet is
-- server-only (configs/server/contacts.lua).
--
-- actions: what the phone offers when the contact is opened, in order. Each is handled by
-- server/trapphone/contacts.lua (see docs/design.md "contact actions").
return {
    CanPassNumbers = true, -- a special contact's number can be handed to a player standing next to you

    Types = {
        plug = { label = 'Plug', actions = { 'order', 'message' } },
        supplier = { label = 'Supplier', actions = { 'order', 'message' } },
        gang = { label = 'Shot caller', actions = { 'bribe', 'standing', 'message' } },
        informant = { label = 'Informant', actions = { 'intel', 'message' } },
        launderer = { label = 'Launderer', actions = { 'wash', 'message' } },
        fixer = { label = 'Fixer', actions = { 'market', 'message' } },
        regular = { label = 'Regular', actions = { 'message' } },
        player = { label = 'Number', actions = { 'message' } },
        custom = { label = 'Contact', actions = { 'message' } },
    },

    MeetRadius = 60.0, -- the contact appears once you are this close to the meeting place
    MeetWaitMinutes = 10, -- how long they wait there before the meet is off
}
