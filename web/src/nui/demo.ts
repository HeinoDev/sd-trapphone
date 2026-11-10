import { patchState, receiveMessage, receiveOffer, serverNow, showToast, usePhone } from '@/store/phone';
import { playAlert, playGood } from '@/device/sound';
import type { Offer, Reply, Thread } from '@/store/types';

// The street, pretended. Outside the game there is no server to roll offers or take product,
// so this plays both sides just well enough that every screen of the handset can be tried:
// start serving and customers text, haggle and some bite, order from a plug and they answer.
// Nothing here ships to a game client's logic; in FiveM the real server answers instead.

const CUSTOMERS = [
  { name: 'Dre', number: '555-4410' },
  { name: 'Kiki', number: '555-8102' },
  { name: 'Tall Mike', number: '555-3396' },
  { name: 'Shay', number: '555-6027' },
  { name: 'Lil Tay', number: '555-7731' },
];

const PRODUCTS = [
  { item: 'cokebaggy', label: 'Coke', family: 'coke', unit: 'gram', price: 150, max: 5 },
  { item: 'weedbaggy', label: 'Weed', family: 'weed', unit: 'gram', price: 55, max: 7 },
  { item: 'coke_7g', label: 'Coke', family: 'coke', unit: 'quarter', price: 560, max: 2 },
];

const ASKS = ['yo u on? need %q %u of %p. %$', 'lemme get %q %u %p for %$', 'pull up w %q %u of %p? got %$', 'u still got %p? %q %u, %$ cash'];
const THANKS = ['good looks', 'bet. same time tmrw', 'u the best fr', 'smooth. hit u later'];
const NOPES = ['nah thats too much', 'cmon be real', 'cant do that'];
const REPLIES = ['who dis', 'cant talk rn', 'say less', 'hit me later', 'aight'];

let ticket = 100;
let seq = 1000;
let timer = 0;

const pick = <T,>(list: T[]): T => list[Math.floor(Math.random() * list.length)];
const state = () => usePhone.getState().state;

function text(number: string, name: string, kind: Thread['kind'], body: string, offer?: Offer, mine = false): void {
  receiveMessage({
    number,
    name,
    kind,
    unread: mine ? 0 : 1,
    msg: { id: ++seq, from: mine ? 'me' : 'them', text: body, ts: serverNow(), offer },
    silent: mine,
  });

  if (mine) return;

  playAlert();
  if (usePhone.getState().open) showToast(`${name}: ${body}`);
}

/** A customer texts an offer for something the sample pockets hold. */
function customer(): void {
  const s = state();
  if (!s || s.hustle?.mode === 'idle') return;

  const who = pick(CUSTOMERS);
  const what = pick(PRODUCTS);
  const qty = 1 + Math.floor(Math.random() * what.max);
  const price = Math.round((what.price * qty * (0.88 + Math.random() * 0.3)) / 5) * 5;
  const unit = usePhone.getState().setup?.units[what.unit]?.short ?? what.unit;
  const body = pick(ASKS).replace('%q', String(qty)).replace('%u', unit).replace('%p', what.label.toLowerCase()).replace('%$', `$${price}`);

  text(who.number, who.name, 'customer', body, {
    ticketId: `d${++ticket}`,
    kind: s.hustle?.mode === 'drops' ? 'drop' : 'corner',
    item: what.item,
    label: what.label,
    family: what.family,
    unit: what.unit,
    qty,
    price,
    state: 'open',
    counters: 2,
    expires: serverNow() + 90,
    place: s.hustle?.mode === 'drops' ? 'Mirror Park' : undefined,
  });

  timer = window.setTimeout(customer, 14000 + Math.random() * 9000);
}

function findOffer(number: string, ticketId: unknown): Offer | undefined {
  const thread = state()?.threads.find(t => t.number === number);
  return thread?.msgs.map(m => m.offer).find(o => o?.ticketId === ticketId);
}

function settle(number: string, offer: Offer): void {
  const s = state();
  if (!s) return;

  receiveOffer({ number, ticketId: offer.ticketId, offer: { ...offer, state: 'done' } });
  patchState({
    stats: { ...s.stats, sales: s.stats.sales + 1, earned: s.stats.earned + offer.price, drops: s.stats.drops + (offer.kind === 'drop' ? 1 : 0) },
  });
  playGood();
  showToast(`+$${offer.price}`, 'good');

  const thread = state()?.threads.find(t => t.number === number);
  window.setTimeout(() => text(number, thread?.name ?? number, 'customer', pick(THANKS)), 1600);
}

/** Answer a page callback the way the game would, moving the sample state along. */
export function demoReply(name: string, body: unknown): Reply | null {
  const b = (body ?? {}) as Record<string, unknown>;
  const s = state();
  if (!s) return null;

  if (name === 'trap:hustle:start') {
    patchState({ hustle: { ...s.hustle!, mode: b.mode === 'drops' ? 'drops' : 'corner', family: String(b.family ?? 'any'), queue: 0 } });
    window.clearTimeout(timer);
    timer = window.setTimeout(customer, 3500);
    return { ok: true };
  }

  if (name === 'trap:hustle:stop') {
    window.clearTimeout(timer);
    patchState({ hustle: { ...s.hustle!, mode: 'idle' } });
    return { ok: true };
  }

  if (name === 'trap:hustle:setSpot' || name === 'trap:hustle:clearSpot') {
    patchState({ hustle: { ...s.hustle!, spotSet: name === 'trap:hustle:setSpot' } });
    return { ok: true };
  }

  if (name === 'trap:offer:respond') {
    const number = String(b.number);
    const offer = findOffer(number, b.ticketId);
    if (!offer || offer.state !== 'open') return { ok: false, error: 'That offer is gone.' };

    if (b.action === 'decline') {
      receiveOffer({ number, ticketId: offer.ticketId, offer: { ...offer, state: 'declined' } });
      return { ok: true };
    }

    if (b.action === 'counter') {
      const ask = Number(b.price) || 0;
      const markup = ask / offer.price - 1;

      if (markup > 0.4 || Math.random() > 0.85 - markup * 1.6) {
        const left = offer.counters - 1;
        receiveOffer({ number, ticketId: offer.ticketId, offer: { ...offer, counters: left, state: left > 0 ? 'open' : 'walked' } });
        const thread = s.threads.find(t => t.number === number);
        window.setTimeout(() => text(number, thread?.name ?? number, 'customer', pick(NOPES)), 900);
        return { ok: true };
      }

      offer.price = Math.max(offer.price, Math.round(ask));
    }

    const accepted = { ...offer, state: 'accepted' as const };
    receiveOffer({ number, ticketId: offer.ticketId, offer: accepted });
    window.setTimeout(() => settle(number, accepted), 3200);
    return { ok: true };
  }

  if (name === 'trap:message:send') {
    const number = String(b.number);
    const known = s.contacts.find(c => c.number === number) ?? s.threads.find(t => t.number === number);
    text(number, known?.name ?? number, 'contact', String(b.text), undefined, true);
    window.setTimeout(() => text(number, known?.name ?? number, 'contact', pick(REPLIES)), 2200);
    return { ok: true };
  }

  if (name === 'trap:contact:add') {
    const number = String(b.number);
    patchState({ contacts: [...s.contacts.filter(c => c.number !== number), { number, name: String(b.name), type: 'custom' }] });
    return { ok: true };
  }

  if (name === 'trap:contact:delete') {
    patchState({ contacts: s.contacts.filter(c => c.number !== b.number) });
    return { ok: true };
  }

  if (name === 'trap:contact:action') {
    const number = String(b.number);
    const contact = s.contacts.find(c => c.number === number);
    const args = b.args as { lines?: unknown[]; confirm?: boolean } | undefined;

    if (b.action === 'order' && args?.lines) {
      window.setTimeout(() => text(number, contact?.name ?? number, 'contact', 'got u. del perro pier, by the bikes. 10 min'), 1800);
      return { ok: true };
    }
    if (b.action === 'intel' && args?.confirm) {
      window.setTimeout(() => text(number, contact?.name ?? number, 'contact', 'word is rockford hills is dry on coke. go eat'), 1800);
      return { ok: true };
    }
    if (b.action === 'bribe' && args?.confirm) {
      patchState({ turf: { ...s.turf!, gang: s.turf!.gang ? { ...s.turf!.gang, protectedUntil: serverNow() + 86400 } : undefined } });
      return { ok: true };
    }
  }

  return null;
}
