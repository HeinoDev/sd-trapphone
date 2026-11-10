-- SERVER-ONLY: drop-off runs. Orders are texted to a player who is taking them (started from
-- the phone while in a vehicle); each sends them to one of the doors below.
return {
    Enabled = true,
    RequireVehicle = true, -- orders only come in while you are in a vehicle
    SmsOnRequest = true, -- every order arrives as a text you accept or pass on
    MaxQueue = 5, -- open orders at once
    RequestDelay = 60, -- seconds between orders
    AcceptSeconds = 120, -- an unanswered order expires
    DeliverMinutes = 12, -- an accepted order is cancelled if you don't make it
    CompleteRadius = 6.0, -- you must be this close to the door (checked on the server)

    MinDistance = 250.0, -- doors closer to you than this are skipped
    MaxDistance = 3500.0,

    -- Orders are bigger than corner sales: the corner maxSale times this, rounded up.
    QuantityMultiplier = 1.5,
    -- And pay a little better for the drive.
    PriceBonus = 1.15,

    -- Where customers wait. `model` is optional (a random customer model otherwise). The client
    -- snaps the ped to the ground, so z only needs to be roughly right. `label` is optional too:
    -- what the order calls the place (the zone's name otherwise).
    Spots = {
        { coords = vec4(-14.2, -1441.9, 31.1, 180.0) },
        { coords = vec4(85.6, -1959.6, 21.1, 230.0) },
        { coords = vec4(126.7, -1930.0, 21.4, 120.0) },
        { coords = vec4(250.1, -1934.9, 24.7, 320.0) },
        { coords = vec4(325.1, -1989.6, 24.2, 50.0) },
        { coords = vec4(495.3, -1823.3, 28.9, 140.0) },
        { coords = vec4(-161.8, -1638.3, 34.0, 50.0) },
        { coords = vec4(-212.9, -1618.1, 34.9, 180.0) },
        { coords = vec4(106.2, -1280.3, 29.2, 120.0) },
        { coords = vec4(223.9, 121.5, 102.8, 250.0) },
        { coords = vec4(882.7, -160.3, 77.1, 330.0) },
        { coords = vec4(1151.0, -461.6, 66.8, 170.0) },
        { coords = vec4(1250.9, -621.0, 69.4, 30.0) },
        { coords = vec4(1303.2, -527.4, 71.5, 160.0) },
        { coords = vec4(-1245.6, 376.2, 75.3, 20.0) },
        { coords = vec4(-1383.8, 267.2, 61.2, 280.0) },
        { coords = vec4(-1151.3, 546.1, 100.6, 190.0) },
        { coords = vec4(-824.7, 422.1, 92.1, 0.0) },
        { coords = vec4(-1383.1, -640.0, 28.7, 120.0) },
        { coords = vec4(-1193.8, -1556.8, 4.4, 300.0) },
        { coords = vec4(-1108.4, -1527.9, 6.8, 30.0) },
        { coords = vec4(-668.3, -971.6, 22.3, 0.0) },
        { coords = vec4(-564.4, -1071.3, 22.3, 270.0) },
        { coords = vec4(1392.9, 3605.6, 34.9, 200.0) },
        { coords = vec4(1973.8, 3815.1, 33.4, 120.0) },
        { coords = vec4(1728.7, 3851.6, 34.8, 40.0) },
        { coords = vec4(2415.6, 4993.2, 46.2, 130.0) },
        { coords = vec4(1662.1, 4776.2, 42.0, 280.0) },
        { coords = vec4(-9.5, 6653.6, 31.1, 40.0) },
        { coords = vec4(-374.5, 6190.9, 31.7, 220.0) },
        { coords = vec4(-272.5, 6400.9, 31.5, 210.0) },
        { coords = vec4(-3089.2, 221.3, 14.1, 320.0) },
    },
}
