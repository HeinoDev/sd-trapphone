-- The handset itself. Shared: the client needs the prop/anim and the look lists, the server
-- needs the item names and the storage mode.
return {
    -- The handset comes in ten colours. Each is its own item with its own model, and the item
    -- decides the faceplate the player sees on screen and holds in the hand.
    -- [item name] = faceplate id (styled in web/src/styles.css, modelled as <Prop.Prefix><id>).
    Items = {
        trap_phone_graphite = 'graphite',
        trap_phone_chrome = 'chrome',
        trap_phone_pearl = 'pearl',
        trap_phone_bling = 'bling',
        trap_phone_ice = 'ice',
        trap_phone_bubblegum = 'bubblegum',
        trap_phone_lime = 'lime',
        trap_phone_cherry = 'cherry',
        trap_phone_grape = 'grape',
        trap_phone_tangerine = 'tangerine',
    },
    Item = 'trap_phone_graphite', -- the colour handed out by default (admin give, shops)

    -- true: every phone item is its own business. Progress, contacts and messages are stored
    --       against an id stamped into the item's metadata, so a stolen or sold phone carries
    --       everything with it. Keep the item unstackable.
    -- false: progress belongs to the character and any trap phone opens it.
    UniqueMetadataPhones = true,

    MaxMessagesPerThread = 50, -- oldest messages fall off a conversation past this
    MaxThreads = 40, -- oldest customer conversations are dropped past this (contacts are kept)
    NumberPrefix = '555', -- burner numbers read <prefix>-<4 digits>

    -- Players can still walk and drive with the handset out. Mouse look is released only
    -- while the cursor is hidden (hold the key below to bring the cursor back).
    KeepInput = true,
    OpenCommand = 'trapphone', -- also bound to OpenKey when set; the item works either way
    OpenKey = '', -- e.g. 'F3'; empty leaves it unbound (players can bind it themselves)

    -- What the character holds: the streamed handset in the phone's colour (stream/, built by
    -- tools/build_prop.py). The local axes follow GTA's own hand props, so it sits in the
    -- texting grip with no offset.
    Prop = {
        Prefix = 'sd_trapphone_', -- model name is Prefix .. faceplate id
        Fallback = `prop_npc_phone_02`, -- used if the streamed model is missing
        Bone = 28422,
        Offset = vec3(0.0, 0.0, 0.0),
        Rotation = vec3(0.0, 0.0, 0.0),
    },
    Anim = {
        Dict = 'cellphone@',
        In = 'cellphone_text_in',
        Loop = 'cellphone_text_read_base',
        Out = 'cellphone_text_out',
        VehicleDict = 'anim@cellphone@in_car@ds',
    },

    Wallpapers = { 'aqua', 'sunset', 'grid', 'chromeblob', 'plain' },
    DefaultWallpaper = 'aqua',

    -- Monophonic ringtones, synthesised in the page (no audio files). ids match
    -- web/src/device/ringtones.ts.
    Ringtones = { 'trapline', 'pager', 'ascend', 'lowrider', 'silent' },
    DefaultRingtone = 'trapline',
    DefaultVolume = 0.5, -- 0..1

    -- sd-phone is optional. When it is running:
    --   Messages      burners and smartphones can text each other. A burner's text lands in the
    --                 smartphone's Messages under the burner's number, and replies come back.
    --   NotifyIntros  a contact reaching out for the first time also pings the player's real
    --                 phone, so the introduction isn't missed with the burner put away.
    SdPhone = { Enabled = true, Messages = true, NotifyIntros = true },

    -- A small preview of the handset slides in for a new text while the phone is put away.
    PeekOnMessage = true,
    PeekSeconds = 5,
}
