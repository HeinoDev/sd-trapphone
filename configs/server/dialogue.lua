-- SERVER-ONLY: what customers text. One list of lines per moment, plus optional lists per
-- personality (keys of configs/server/selling.lua Personalities) that are mixed in about half
-- the time for that kind of customer.
--
-- Placeholders are filled in a fixed order, so a line may use the first few and leave the rest
-- out, but can't reorder them:
--   offer, drop_order   %d quantity, %s unit, %s product, %d total price   ("need 3 g of weed, got $150")
--   counter_ok          %d the price they agreed to
--   counter_no          %d the price they are sticking to
--   everything else     no placeholders
-- A literal percent sign must be written %%.
return {
    -- A customer asking for product on the corner or pulling up in a car.
    offer = {
        default = {
            'yo u around? need %d %s of %s. got $%d',
            'need %d %s %s, $%d',
            'u holdin? lookin for %d %s of %s. $%d on me',
            'tryna get %d %s of that %s for $%d',
            'can u do %d %s %s for $%d',
            'hey its me. %d %s of %s? i got $%d',
            'pulling up. %d %s %s. $%d cash',
            'lemme get %d %s of %s, $%d cool?',
            'u still sellin? %d %s of %s if so. $%d',
            '%d %s of %s. $%d. where u at',
            'heard u got it. %d %s %s for $%d?',
            'need %d %s of %s asap. $%d',
            'my boy said hit u up. %d %s %s, i got $%d',
            'u open? %d %s of %s, $%d',
            'omw 2 u. want %d %s of %s. $%d ok',
            'same as last time? %d %s %s. $%d',
            'just got paid. %d %s of %s 4 $%d',
            'wya. need %d %s of %s',
            'sup. %d %s %s if u got it. $%d',
            '%d %s of %s plz. $%d in hand',
        },
        chill = {
            'yo no rush. %d %s of %s when u can. $%d',
            'ayy whats good. lemme grab %d %s of %s, got $%d 4 u',
            'easy day. %d %s %s? $%d',
            'chillin round the corner. %d %s of %s, $%d sound ok?',
            'whenever ur free man. %d %s of %s. $%d',
            'sup fam :) %d %s %s for $%d?',
        },
        tight = {
            '%d %s of %s. $%d and thats it',
            '%d %s of %s. i counted it twice. $%d, not a dollar more',
            '%d %s %s. $%d. dont try me on price',
            'need %d %s of %s. $%d is all i got 2day',
            '%d %s of %s, $%d. take it or leave it',
            'last guy charged less. %d %s %s 4 $%d',
        },
        jumpy = {
            'u alone?? need %d %s of %s. $%d. hurry',
            '%d %s %s. $%d. quick b4 some1 sees',
            'dont say nothin on here. %d %s of %s. $%d',
            'is it safe?? %d %s of %s, $%d. be fast',
            'need %d %s %s rn. $%d. no stoppin',
            'u sure nobody watchin? %d %s of %s. $%d',
        },
        baller = {
            'need %d %s of %s. $%d, keep it movin',
            '%d %s of ur best %s. $%d no problem',
            'party 2nite. %d %s %s. $%d and a lil extra if its good',
            'make it %d %s of %s. moneys not a thing. $%d',
            '%d %s of %s for the crib. $%d cash',
            'driver is waitin. %d %s %s, $%d',
        },
        fiend = {
            'plz tell me u got it. %d %s of %s. $%d',
            'i need %d %s %s NOW. $%d its all there i swear',
            'u there?? u there?? %d %s of %s. $%d',
            'been lookin all day man. %d %s of %s. got $%d',
            'cmon pick up. %d %s %s. $%d',
            'need it bad. %d %s of %s. $%d plz',
        },
        square = {
            'hi, is this the right number? i would like %d %s of %s. i have $%d',
            'hello. a friend gave me this number. %d %s of %s for $%d?',
            'um. %d %s of %s please. is $%d ok',
            'never done this b4. %d %s %s? $%d?',
            'hi sorry 2 bother u. %d %s of %s. i brought $%d',
            'do u take cash? %d %s of %s. $%d',
        },
    },

    -- You accepted their offer.
    accept = {
        default = {
            'bet',
            'cool omw',
            'ok comin 2 u',
            'aight 1 min',
            'say less',
            'on my way',
            'k dont move',
            'good lookin',
            'word. b there',
            'ok ok im close',
            'kk',
            'nice. c u in a sec',
        },
        chill = { 'bet take ur time', 'cool cool', 'ayy my guy', 'easy. walkin over' },
        tight = { 'ok. price stays', 'fine', 'k. exact change' },
        jumpy = { 'ok ok ok', 'k be ready. no talkin', 'comin. keep ur head down' },
        baller = { 'good. dont keep me waitin', 'bet. make it nice', 'pullin up' },
        fiend = { 'THANK U', 'omg ok runnin', 'yes yes omw', 'dont leave plz' },
        square = { 'ok thank you. on my way', 'great, see you shortly', 'ok. what do u look like' },
    },

    -- You countered and they took it.
    counter_ok = {
        default = {
            'ugh. fine. $%d',
            'aight $%d. but only cuz its u',
            '$%d ok. u robbin me tho',
            'k $%d. hurry up',
            'damn. $%d. deal',
            'ok $%d. better b good',
            '$%d fine. dont do me like that again',
            'u lucky i need it. $%d',
            'alright alright $%d',
            'smh. $%d. comin',
        },
        chill = { 'haha ok $%d its all good', '$%d works. no stress', 'u got it. $%d' },
        tight = { '...$%d. this the last time', '$%d. i wont 4get this', 'fine. $%d. happy?' },
        jumpy = { 'ok $%d whatever just b quick', '$%d fine fine. hurry' },
        baller = { '$%d? thats it? sure', 'lol $%d is nothin. bet', '$%d. keep the change comin' },
        fiend = { 'ok ok $%d anything', '$%d yes just plz', 'ill find it. $%d ok' },
        square = { 'oh. ok. $%d then', 'i guess $%d is fair?', '$%d. is that normal' },
    },

    -- You countered and they said no. The number is what they are still offering.
    counter_no = {
        default = {
            'nah. $%d or nothin',
            'lol no. $%d',
            'u trippin. $%d',
            'i said $%d',
            'cant do that. $%d',
            'come on man. $%d',
            'not 4 that. $%d final',
            '$%d. thats what i got',
            'no way. $%d',
            'thats 2 much. $%d',
        },
        chill = { 'haha nah bro. $%d', 'cmon now. $%d is fair', 'nah we good at $%d' },
        tight = { 'absolutely not. $%d', 'do i look rich. $%d', '$%d. ask again n im gone' },
        jumpy = { 'no no. $%d. stop textin so much', '$%d!! i gotta go soon' },
        baller = { 'i pay 4 quality not 4 jokes. $%d', 'cute. $%d' },
        fiend = { 'i dont HAVE more. $%d', 'plz man $%d is everything i got' },
        square = { 'sorry, i only brought $%d', 'i cant, $%d is my budget' },
    },

    -- You declined their offer.
    decline = {
        default = {
            'aight nvm',
            'wow ok',
            'forget it then',
            'k. ill ask some1 else',
            'ur loss',
            'damn. ok',
            'whatever man',
            'cool. lose my number',
            'ok then',
            'smh',
            'fine b like that',
            'thought we was good',
        },
        chill = { 'no worries. next time', 'all good bro', 'its cool. later' },
        tight = { 'good. saved my money', 'didnt want it anyway' },
        jumpy = { 'ok ok 4get i asked. delete this', 'u never heard from me' },
        baller = { 'plenty of others. bye', 'ur not the only 1 in town' },
        fiend = { 'no no plz', 'cmon dont do this 2 me', 'why u gotta b like that' },
        square = { 'oh. sorry to bother you', 'ok. have a nice day' },
    },

    -- The sale went through.
    thanks = {
        default = {
            'good lookin',
            'preciate it',
            'ur the best',
            'thx. hit u later',
            'solid',
            'aight 1',
            'thx. same time nxt week',
            'gd stuff. later',
            'respect',
            'ty',
            'nice doin business',
            'bless',
            'u str8. ill b back',
            'cheers',
        },
        chill = { 'my guy. stay up', 'always a pleasure :)', 'good vibes. later', 'u a real 1' },
        tight = { 'ok. fair enough', 'thx. still think its pricey', 'k' },
        jumpy = { 'thx. deletin this', 'we never met', 'gone. dont text me 1st' },
        baller = { 'good. keep it comin', 'ill tell my ppl bout u', 'u just got a customer' },
        fiend = { 'thank u thank u', 'u saved me', 'ill b back 2morrow', 'omg finally' },
        square = { 'thank you very much', 'that was easier than i thought', 'thanks. please be discreet' },
    },

    -- They gave up: the offer ran out, you took too long, or you pushed the price too far.
    walked = {
        default = {
            'nvm im out',
            '4get it. took 2 long',
            'man im gone',
            'u playin. bye',
            'got it somewhere else',
            'cant wait no more',
            'aint got all day',
            'yea nah. later',
            'wasted my time',
            'too slow',
            'im not standin here 4ever',
            'nvm found another guy',
        },
        chill = { 'gotta bounce. nxt time', 'no stress. catch u later' },
        tight = { 'knew it. waste of time', 'not payin that. bye' },
        jumpy = { 'nope. bad feelin. gone', 'some1 was lookin at me. im out' },
        baller = { 'my time costs more than ur stuff', 'u just lost a good customer' },
        fiend = { 'where r u?? 4get it', 'i cant wait i cant', 'goin 2 the other guy' },
        square = { 'i changed my mind, sorry', 'this was a bad idea. goodbye' },
    },

    -- You walked up and pitched, and they want none of it. Spoken to your face, not texted.
    refused = {
        default = {
            'Nah, I\'m good.',
            'Get away from me, man.',
            'Do I look like I do that?',
            'Not interested.',
            'Wrong person, buddy.',
            'Keep walking.',
            'I don\'t mess with that.',
            'You serious right now?',
            'Nope. Have a good one.',
            'Back up off me.',
            'I got kids, man.',
            'Not today.',
            'Try somebody else.',
            'You must be new around here.',
        },
        chill = { 'Appreciate it, but I\'m straight.', 'Nah, not my thing. Stay safe though.' },
        tight = { 'With these prices? No.', 'I\'m not paying for that.' },
        jumpy = { 'Don\'t talk to me. Don\'t even look at me.', 'Are you crazy? Out here?' },
        baller = { 'I have people for that.', 'From the street? Please.' },
        fiend = { 'I\'m trying to stay clean, man. Don\'t.', 'Not today. Not today.' },
        square = { 'I\'m calling somebody about this.', 'Excuse me? Absolutely not.', 'That is illegal, you know.' },
    },

    -- They took it and ran instead of paying.
    robbery = {
        default = {
            'lol thx 4 the free stuff',
            'u got got',
            'shoulda watched ur back',
            'nothin personal',
            'too easy',
            'better luck nxt time',
            'thx sucker',
            'dont come lookin 4 me',
            'welcome 2 the streets',
            'run ur pockets nxt time 2',
        },
    },

    -- A delivery order while you are taking drop-offs.
    drop_order = {
        default = {
            'can u bring %d %s of %s 2 my place? $%d',
            'delivery? %d %s %s. $%d at the door',
            'need %d %s of %s dropped off. $%d',
            'u deliver rite? %d %s of %s, $%d',
            'cant leave the house. %d %s %s. got $%d',
            '%d %s of %s 2 the door plz. $%d',
            'yo come thru w %d %s of %s. $%d waitin',
            'order: %d %s %s. payin $%d',
            'u drivin 2nite? %d %s of %s, $%d',
            'bring %d %s of %s. ill b out front. $%d',
            'house call? %d %s %s for $%d',
            'need a drop. %d %s of %s. $%d cash',
            'gotta re-up. %d %s of %s 2 mine. $%d',
            'having ppl over. %d %s %s. $%d',
        },
        chill = { 'no rush. %d %s of %s 2 my spot, $%d', 'swing by when u can. %d %s %s. $%d' },
        tight = { '%d %s of %s. $%d. gas is ur problem', '%d %s of %s 4 $%d delivered. no extras' },
        jumpy = { 'come 2 the door. dont knock. %d %s of %s. $%d', 'park down the st. %d %s %s. $%d' },
        baller = { 'send %d %s of %s up 2 the house. $%d', '%d %s of %s 4 the afterparty. $%d' },
        fiend = { 'plz hurry. %d %s of %s. $%d', 'how long?? %d %s %s. got $%d' },
        square = { 'hello, do you do home delivery? %d %s of %s. $%d', 'hi. %d %s of %s to my address please. $%d' },
    },

    -- You accepted a delivery.
    drop_accept = {
        default = {
            'bet. ill b out front',
            'ok door is open',
            'cool. honk when ur here',
            'k waitin outside',
            'nice. dont b long',
            'aight c u soon',
            'ok im by the door',
            'good. hurry tho',
        },
    },

    -- The delivery was handed over.
    drop_thanks = {
        default = {
            'thx 4 comin out',
            'door 2 door. love it',
            'fast. ill order again',
            'preciate the drive',
            'u a lifesaver',
            'thx. same time nxt wk?',
            'good service lol',
            'ty. drive safe',
            'that was quick. respect',
            'best in the city',
            'thx. tell ur boss u need a raise',
            'got it. later',
        },
        fiend = { 'finally. thank u', 'u dont kno how bad i needed this' },
        baller = { 'good. a lil extra 4 the trip maybe', 'reliable. i like that' },
        square = { 'thank you for delivering', 'very professional. thanks' },
    },

    -- A delivery you accepted and never made.
    drop_late = {
        default = {
            'where r u?? 4get it',
            'u never showed. dont bother',
            'waited outside like a fool',
            'cancel it. got some1 else',
            'no show. wow',
            'ok im goin back inside',
        },
    },

    -- They have bought enough to save your number.
    regular = {
        default = {
            'savin ur number. ur my guy now',
            'u reliable. ima hit u direct from now on',
            'keep this line open 4 me',
            'i only buy from u now',
            'put me in ur phone. ill b callin',
            'told u id b back. lock me in',
        },
    },
}
