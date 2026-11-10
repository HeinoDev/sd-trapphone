-- SERVER-ONLY: what contacts and gangs text. One line is picked at random from a list each
-- time. Written the way people typed on a keypad in 2003: short, lower case, few vowels spared.
--
-- Placeholders are filled in by server/trapphone/contacts.lua and turf.lua and must stay in
-- the order given in the comment above each list. A list with no placeholder note takes none.
return {
    -- A contact reaching out for the first time, by contact type. %s = the area they wait in.
    intro = {
        plug = {
            'heard u been movin. i got weight. come c me in %s, marked it 4 u',
            'yo. friend of a friend says ur solid. %s. come alone',
            'u need a real connect not crumbs. im in %s rite now',
            'got ur number off a customer. lets talk bizness. %s',
            'word is u sell out every nite. i can fix that. meet me %s',
        },
        supplier = {
            'hi hun. u need bags n scales? i do bulk. im at %s',
            'ur gonna need supplies if u keep growin. come by %s',
            'i sell what the corner shop wont. %s, dont b long',
            'heard ur weighin by eye. come c me in %s b4 u lose money',
        },
        gang = {
            'u been eatin on our blocks. time we met. %s',
            'the old heads wanna c ur face. %s. dont make us come 2 u',
            'u sell round here u talk 2 me first. %s',
            'we c u. come 2 %s n we can keep it friendly',
            'respect goes 2 ways. show up in %s',
        },
        informant = {
            'psst. i hear things. things u wanna kno. %s',
            'i kno where they r buyin 2nite. find me in %s',
            'got ears all over town. small fee. %s',
            'u dont kno me but i kno ur corners. come 2 %s',
        },
        launderer = {
            'that money smells. i can make it smell nice. %s',
            'u got a cash problem. i got a spin cycle. meet me %s',
            'a man with ur income needs a good cleaner. %s',
        },
        fixer = {
            'need things that dont come with a receipt? %s',
            'i get things. all kinds. come 2 %s n keep it quiet',
            'heard u r some1 now. some1 needs tools. %s',
        },
    },

    -- Right after the first meeting, by contact type.
    met = {
        plug = {
            'good 2 meet u. txt me when u need a re up',
            'save this number. order thru the fone, pay when u c me',
            'dont txt me bout nothin but bizness',
        },
        supplier = {
            'nice meetin u hun. txt ur list any time',
            'u kno where i am now. order on the fone n come get it',
        },
        gang = {
            'now we kno each other. stay on the rite side of us',
            'u want peace on our blocks u kno who 2 pay',
            'dont make me regret givin u this number',
        },
        informant = {
            'u got my number. tips cost. no refunds',
            'txt me when u wanna kno where the money is',
        },
        launderer = {
            'marked the laundry 4 u. bring it dirty, leave clean',
            'come by the shop any time. i take my cut, u take the rest',
        },
        fixer = {
            'marked the back room 4 u. knock twice',
            'my guy is in the back room. tell him i sent u',
        },
    },

    order = {
        -- %s = the area to collect in, %d = the total to bring.
        confirm = {
            'ok. %s. bring $%d cash, no small talk',
            'got it. meet me %s. $%d n its urs',
            'packin it up now. %s. dont 4get the $%d',
            'cool. b in %s. $%d, count it b4 u come',
            'i can do that. %s, $%d. dont b late',
        },
        collected = {
            'pleasure. dont txt me 4 a bit',
            'all there. go make ur money',
            'good doin bizness. b safe out there',
            'dont open it on the street',
        },
        -- %d = what the order costs.
        broke = {
            'u r short. $%d or dont waste my time',
            'i said $%d. come back when u got it',
            'this aint a charity. $%d',
        },
        -- %d = minutes until they will take another order.
        cooldown = {
            'slow down. hit me in %d min',
            'i just sorted u out. %d more min',
            'cant b seen with u that often. %d min',
        },
        waiting = {
            'im still waitin on u 4 the last one',
            'come get what u ordered first',
        },
        cantCarry = {
            'u cant carry all that. make room n come back',
            'ur pockets r full. sort it out',
        },
    },

    meet = {
        -- %s = the area they are waiting in.
        reminder = {
            'still here. %s. not 4 long tho',
            'where r u?? %s',
            'clock is tickin. %s',
            'u comin or not. %s',
        },
        missed = {
            'u didnt show. 4get it',
            'waited long enuf. im gone',
            'dont waste my time again',
            'no show. nice 1',
        },
    },

    intel = {
        -- %s = the area, %s = the product.
        tip = {
            'over in %s they r dyin 4 %s rite now',
            '%s. every1 askin 4 %s. go',
            'word is %s is dry. bring %s n name ur price',
            'my boy says %s cant get enuf %s 2nite',
            'try %s. ppl payin silly money 4 %s',
        },
        none = {
            'nothin movin rite now. kept ur money tho. jk. try l8r',
            'streets r quiet. ask me again in a bit',
        },
    },

    bribe = {
        -- %d = hours of protection bought.
        paid = {
            'ok. u r good on our blocks 4 %d hrs',
            'money talks. %d hrs, nobody touches u',
            'ill tell the boys. %d hrs of peace',
            'smart. u got %d hrs',
        },
        refused = {
            'keep ur money. we dont deal with u',
            'u think u can buy us after what u did? nah',
            'not from u. not 2day',
        },
    },

    tax = {
        -- %d = what they want.
        demand = {
            'u been eatin on our block. $%d. my boys r comin 2 collect',
            'rent is due. $%d. dont run',
            '$%d 4 the corner u been usin. they r on the way',
            'nothin is free round here. $%d',
        },
        paid = {
            'good. keep it that way',
            'c how easy that was',
            'smart. u can stay. 4 now',
        },
        refused = {
            'wrong answer',
            'u just made it personal',
            'ok. we do it the hard way',
            'bad move',
        },
    },

    riot = {
        -- %s = the crew's name.
        start = {
            '%s r on the streets. they want blood 4 what u did',
            'u pushed %s 2 far. they r comin',
            '%s just put the word out. all of them',
        },
        -- %d = this wave, %d = how many waves.
        wave = {
            'more of them comin. %d of %d',
            'here they come again. %d of %d',
        },
        -- %s = the crew's name.
        over = {
            '%s pulled back. dont think its 4gotten',
            'its over. %s buried enuf 2day',
        },
        paidOff = {
            'ok. its squashed. tell ur ppl 2 stay off us',
            'money on the table. i called them off',
        },
    },

    share = {
        -- %s = the contact's name.
        received = {
            'some1 vouched 4 u. this is %s. save the number',
            '%s here. ur friend says ur ok. we will c',
        },
    },

    -- Answers to whatever the player types at a contact, by contact type.
    reply = {
        plug = {
            'order thru the menu. i dont do chat',
            'u want weight or u want a pen pal',
            'k',
            'not on the fone',
            'txt me an order or dont txt me',
            '?',
        },
        supplier = {
            'send me a list hun, not a story',
            'lol ok. u need bags or not',
            'busy. order on the fone',
            'k hun',
        },
        gang = {
            'watch ur mouth',
            'u wanna talk, bring money',
            'we kno where u sell',
            'dont txt this number 4 fun',
            'say less',
        },
        informant = {
            'info costs. u kno the price',
            'shh. not here',
            'i only talk when im paid',
            'mayb i heard somethin. mayb not',
        },
        launderer = {
            'come 2 the shop. not on the fone',
            'i dont kno what u r talkin about ;)',
            'bring it in. we talk there',
        },
        fixer = {
            'back room. not here',
            'i never got this txt',
            'come in person',
            'del this msg',
        },
        -- A number that has not been met yet.
        unknown = {
            'who dis',
            'wrong number',
            'new fone who dis',
            'dont kno u',
            '??',
        },
        -- Asked where to meet while a meet is pending. %s = the area.
        where = {
            '%s. look at ur map',
            'i said %s',
            '%s. hurry up',
        },
    },
}
