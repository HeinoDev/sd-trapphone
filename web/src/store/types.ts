// The shapes the server sends. They mirror docs/design.md "Phone state".

export type OfferState = 'open' | 'accepted' | 'declined' | 'done' | 'expired' | 'walked';

export interface Offer {
  ticketId: string | number;
  kind: 'corner' | 'car' | 'pitch' | 'drop';
  item: string;
  label: string;
  family: string;
  unit: string;
  qty: number;
  price: number;
  state: OfferState;
  counters: number;
  expires: number;
  place?: string;
}

export interface Message {
  id: number;
  from: 'me' | 'them';
  text: string;
  ts: number;
  offer?: Offer;
}

export interface Thread {
  number: string;
  name: string;
  kind: 'customer' | 'contact' | 'player' | 'system';
  unread: number;
  ts: number;
  msgs: Message[];
}

export interface Contact {
  number: string;
  name: string;
  type: string;
  key?: string;
  gang?: string;
}

export interface RepLine {
  family: string;
  label: string;
  color: string;
  title: string;
  level?: number;
  bars: number;
}

export interface Hustle {
  mode: 'idle' | 'corner' | 'drops';
  family: string;
  spotSet: boolean;
  queue: number;
  dropsEnabled: boolean;
  blocked?: string;
  products: {
    family: string;
    label: string;
    color: string;
    items: { item: string; label: string; unit: string; count: number }[];
  }[];
}

export interface Turf {
  zone: { id: string; label: string; wealth: number; wealthLabel: string };
  gang?: {
    id: string;
    label: string;
    color: string;
    standing: string;
    standingLabel: string;
    protectedUntil?: number;
  };
  heat: number;
  demand: { family: string; label: string; color: string; level: 'low' | 'normal' | 'high' }[];
}

export interface Settings {
  wallpaper: string;
  ringtone: string;
  volume: number;
}

export interface PhoneState {
  /** shell: the faceplate of the item in hand (the item decides it, not a setting). */
  phone: { id: string; number: string; shell?: string };
  settings: Settings;
  threads: Thread[];
  contacts: Contact[];
  scores: Record<string, number>;
  stats: { sales: number; earned: number; drops: number };
  now: number;
  rep?: RepLine[];
  hustle?: Hustle;
  turf?: Turf;
}

export interface Setup {
  wallpapers: string[];
  ringtones: string[];
  peek: boolean;
  peekSeconds: number;
  families: Record<string, { label: string; color: string }>;
  units: Record<string, { label: string; short: string }>;
  contactTypes: Record<string, { label: string; actions: string[] }>;
  canPassNumbers: boolean;
}

export interface Clock {
  h: number;
  m: number;
}

export interface MessagePayload {
  number: string;
  name: string;
  kind: Thread['kind'];
  unread: number;
  msg: Message;
  silent?: boolean;
}

export interface OfferPayload {
  number: string;
  ticketId: string | number;
  offer: Offer;
}

/** What every slice callback answers with. */
export interface Reply<T = unknown> {
  ok: boolean;
  error?: string;
  data?: T;
}
