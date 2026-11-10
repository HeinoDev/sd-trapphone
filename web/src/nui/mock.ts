import type { PhoneState, Reply, Setup } from '@/store/types';
import { demoReply } from './demo';

// Stand-in data for working on the page in a plain browser (npm run dev). Never used in game.

const now = Math.floor(Date.now() / 1000);

export const MOCK_SETUP: Setup = {
  wallpapers: ['aqua', 'sunset', 'grid', 'chromeblob', 'plain'],
  ringtones: ['trapline', 'pager', 'ascend', 'lowrider', 'silent'],
  peek: true,
  peekSeconds: 5,
  families: {
    weed: { label: 'Weed', color: '#6fcf4a' },
    coke: { label: 'Coke', color: '#e9eef5' },
    meth: { label: 'Meth', color: '#6fd3ff' },
  },
  units: {
    gram: { label: 'gram', short: 'g' },
    quarter: { label: 'quarter', short: 'qtr' },
    ounce: { label: 'ounce', short: 'oz' },
    kilo: { label: 'brick', short: 'kg' },
  },
  contactTypes: {
    plug: { label: 'Plug', actions: ['order', 'message'] },
    supplier: { label: 'Supplier', actions: ['order', 'message'] },
    gang: { label: 'Shot caller', actions: ['bribe', 'standing', 'message'] },
    informant: { label: 'Informant', actions: ['intel', 'message'] },
    launderer: { label: 'Launderer', actions: ['wash', 'message'] },
    fixer: { label: 'Fixer', actions: ['market', 'message'] },
    regular: { label: 'Regular', actions: ['message'] },
    player: { label: 'Number', actions: ['message'] },
    custom: { label: 'Contact', actions: ['message'] },
  },
  canPassNumbers: true,
};

export const MOCK_STATE: PhoneState = {
  phone: { id: 'tp_mock', number: '555-0193', shell: 'graphite' },
  settings: { wallpaper: 'aqua', ringtone: 'trapline', volume: 0.5 },
  now,
  scores: { worm: 240 },
  stats: { sales: 148, earned: 61250, drops: 17 },
  contacts: [
    { number: '555-0142', name: 'Smoke', type: 'plug', key: 'smoke' },
    { number: '555-0151', name: 'OG Hollow', type: 'gang', key: 'oghollow', gang: 'ballas' },
    { number: '555-0166', name: 'Ears', type: 'informant', key: 'ears' },
    { number: '555-7731', name: 'Lil Tay', type: 'regular' },
  ],
  threads: [
    {
      number: '555-7731',
      name: 'Lil Tay',
      kind: 'customer',
      unread: 1,
      ts: now - 20,
      msgs: [
        { id: 1, from: 'them', text: 'u around? need the usual', ts: now - 400 },
        { id: 2, from: 'me', text: 'on the corner', ts: now - 380 },
        {
          id: 3,
          from: 'them',
          text: 'lemme get 3 g of that coke. 450?',
          ts: now - 20,
          offer: {
            ticketId: 't1', kind: 'corner', item: 'cokebaggy', label: 'Coke', family: 'coke', unit: 'gram',
            qty: 3, price: 450, state: 'open', counters: 2, expires: now + 70,
          },
        },
      ],
    },
    {
      number: '555-0142',
      name: 'Smoke',
      kind: 'contact',
      unread: 0,
      ts: now - 3600,
      msgs: [{ id: 1, from: 'them', text: 'got that loud in. hit me when u need weight', ts: now - 3600 }],
    },
    {
      number: '555-2210',
      name: 'Big Rico',
      kind: 'customer',
      unread: 0,
      ts: now - 9000,
      msgs: [
        {
          id: 1,
          from: 'them',
          text: 'good looks. same time tmrw',
          ts: now - 9000,
          offer: {
            ticketId: 't0', kind: 'corner', item: 'weedbaggy', label: 'Weed', family: 'weed', unit: 'gram',
            qty: 5, price: 260, state: 'done', counters: 0, expires: now - 8900,
          },
        },
      ],
    },
  ],
  rep: [
    { family: 'coke', label: 'Coke', color: '#e9eef5', title: 'Runner', bars: 3 },
    { family: 'meth', label: 'Meth', color: '#6fd3ff', title: 'Nobody', bars: 1 },
    { family: 'weed', label: 'Weed', color: '#6fcf4a', title: 'Dealer', bars: 4 },
  ],
  hustle: {
    mode: 'corner',
    family: 'any',
    spotSet: true,
    queue: 0,
    dropsEnabled: true,
    products: [
      {
        family: 'coke', label: 'Coke', color: '#e9eef5',
        items: [
          { item: 'cokebaggy', label: 'Coke', unit: 'gram', count: 14 },
          { item: 'coke_7g', label: 'Coke', unit: 'quarter', count: 2 },
        ],
      },
      { family: 'weed', label: 'Weed', color: '#6fcf4a', items: [{ item: 'weedbaggy', label: 'Weed', unit: 'gram', count: 31 }] },
    ],
  },
  turf: {
    zone: { id: 'davis', label: 'Davis', wealth: 1, wealthLabel: 'Rough' },
    gang: { id: 'ballas', label: 'Ballas', color: '#a45bd6', standing: 'neutral', standingLabel: 'Nobody to them', protectedUntil: now + 5400 },
    heat: 34,
    demand: [
      { family: 'coke', label: 'Coke', color: '#e9eef5', level: 'low' },
      { family: 'meth', label: 'Meth', color: '#6fd3ff', level: 'high' },
      { family: 'weed', label: 'Weed', color: '#6fcf4a', level: 'normal' },
    ],
  },
};

export function mockReply(name: string, body: unknown): Reply {
  const played = demoReply(name, body);
  if (played) return played;

  const b = (body ?? {}) as { action?: string; args?: Record<string, unknown> };

  if (name === 'trap:contact:action') {
    if (b.action === 'order' && !b.args) {
      return {
        ok: true,
        data: {
          items: [
            { item: 'weed_1oz', label: 'Weed (ounce)', price: 320, max: 20 },
            { item: 'weed_brick', label: 'Weed (brick)', price: 9500, max: 3, locked: true },
          ],
        },
      };
    }
    if (b.action === 'bribe' && !b.args) return { ok: true, data: { price: 5000, hours: 24, allowed: true } };
    if (b.action === 'intel' && !b.args) return { ok: true, data: { price: 300 } };
    if (b.action === 'standing') return { ok: true, data: { label: 'Ballas', standingLabel: 'Nobody to them' } };
    if (b.action === 'wash' || b.action === 'market') return { ok: true, data: { label: 'Laundry' } };
  }
  if (name === 'trap:turf:refresh') return { ok: true, data: MOCK_STATE.turf };
  if (name === 'trap:score:submit') return { ok: true };

  return { ok: true };
}
