import { create } from 'zustand';
import type { Clock, MessagePayload, OfferPayload, PhoneState, Setup } from './types';

export interface ScreenEntry {
  id: string;
  params?: Record<string, unknown>;
}

interface Toast {
  text: string;
  tone: 'info' | 'good' | 'bad';
  at: number;
}

interface PhoneStore {
  open: boolean;
  booted: boolean;
  state: PhoneState | null;
  setup: Setup | null;
  clock: Clock;
  /** Seconds to add to Date.now()/1000 to get the server's os.time(). */
  skew: number;
  stack: ScreenEntry[];
  toast: Toast | null;
  peek: MessagePayload | null;
  pressed: string | null;
}

const IDLE: ScreenEntry = { id: 'idle' };

export const usePhone = create<PhoneStore>(() => ({
  open: false,
  booted: false,
  state: null,
  setup: null,
  clock: { h: 12, m: 0 },
  skew: 0,
  stack: [IDLE],
  toast: null,
  peek: null,
  pressed: null,
}));

const set = usePhone.setState;
const get = usePhone.getState;

/** The server's clock right now, in seconds (offers expire against it). */
export const serverNow = (): number => Math.floor(Date.now() / 1000 + get().skew);

export function openPhone(state: PhoneState, setup: Setup, clock: Clock): void {
  set({
    open: true,
    state,
    setup,
    clock,
    skew: state.now - Date.now() / 1000,
    stack: [IDLE],
    peek: null,
    toast: null,
  });
}

export function closePhone(): void {
  set({ open: false, booted: true, toast: null });
}

export function patchState(patch: Partial<PhoneState>): void {
  const state = get().state;
  if (state) set({ state: { ...state, ...patch } });
}

export function setClock(clock: Clock): void {
  set({ clock });
}

/** A new message: put it in its conversation and float that conversation to the top. */
export function receiveMessage(payload: MessagePayload): void {
  const state = get().state;
  if (!state) return;

  const existing = state.threads.find(t => t.number === payload.number);
  const viewing = get().open && get().stack.some(s => s.id === 'thread' && s.params?.number === payload.number);
  const thread = {
    number: payload.number,
    name: payload.name,
    kind: payload.kind,
    unread: viewing ? 0 : payload.unread,
    ts: payload.msg.ts,
    msgs: [...(existing?.msgs ?? []).filter(m => m.id !== payload.msg.id), payload.msg].slice(-50),
  };

  set({ state: { ...state, threads: [thread, ...state.threads.filter(t => t.number !== payload.number)] } });
}

export function receiveOffer(payload: OfferPayload): void {
  const state = get().state;
  if (!state) return;

  set({
    state: {
      ...state,
      threads: state.threads.map(t =>
        t.number !== payload.number
          ? t
          : { ...t, msgs: t.msgs.map(m => (m.offer?.ticketId === payload.ticketId ? { ...m, offer: payload.offer } : m)) },
      ),
    },
  });
}

export function markRead(number: string): void {
  const state = get().state;
  if (!state) return;

  set({ state: { ...state, threads: state.threads.map(t => (t.number === number ? { ...t, unread: 0 } : t)) } });
}

export function dropThread(number: string): void {
  const state = get().state;
  if (state) set({ state: { ...state, threads: state.threads.filter(t => t.number !== number) } });
}

export function showToast(text: string, tone: Toast['tone'] = 'info'): void {
  const at = Date.now();
  set({ toast: { text, tone, at } });
  window.setTimeout(() => {
    if (get().toast?.at === at) set({ toast: null });
  }, 2600);
}

export function showPeek(payload: MessagePayload | null): void {
  set({ peek: payload });
}

export function flashKey(key: string): void {
  set({ pressed: key });
  window.setTimeout(() => {
    if (get().pressed === key) set({ pressed: null });
  }, 110);
}

// Navigation: a stack of screens, the top one is what the display shows.

export function push(id: string, params?: Record<string, unknown>): void {
  set({ stack: [...get().stack, { id, params }] });
}

export function pop(): void {
  const stack = get().stack;
  if (stack.length > 1) set({ stack: stack.slice(0, -1) });
}

export function replace(id: string, params?: Record<string, unknown>): void {
  set({ stack: [...get().stack.slice(0, -1), { id, params }] });
}

export function goHome(): void {
  set({ stack: [IDLE] });
}

export const unreadTotal = (state: PhoneState | null): number =>
  state ? state.threads.reduce((n, t) => n + (t.unread || 0), 0) : 0;
