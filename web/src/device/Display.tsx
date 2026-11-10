import type { ComponentType } from 'react';
import { unreadTotal, usePhone } from '@/store/phone';
import { Idle, Menu } from '@/apps/Home';
import { Compose, Counter, Messages, ThreadView } from '@/apps/Messages';
import { AddContact, ContactView, Contacts, Dialer, Order } from '@/apps/Contacts';
import { Hustle, Status, Turf } from '@/apps/Business';
import { Help, Themes, Tones, Worm } from '@/apps/Extras';
import { useI18n } from '@/i18n';

// Every screen the display can show, by the id the navigation stack holds.
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const SCREENS: Record<string, ComponentType<any>> = {
  idle: Idle,
  menu: Menu,
  messages: Messages,
  thread: ThreadView,
  counter: Counter,
  compose: Compose,
  contacts: Contacts,
  contact: ContactView,
  order: Order,
  addcontact: AddContact,
  dialer: Dialer,
  hustle: Hustle,
  turf: Turf,
  status: Status,
  games: Worm,
  tones: Tones,
  themes: Themes,
  help: Help,
};

const pad2 = (n: number): string => String(n).padStart(2, '0');

function StatusBar() {
  const t = useI18n();
  const state = usePhone(s => s.state);
  const clock = usePhone(s => s.clock);
  const mode = state?.hustle?.mode ?? 'idle';
  const unread = unreadTotal(state);

  return (
    <div className="statusbar">
      <span className="signal" aria-hidden="true">
        {[3, 5, 7, 10].map(h => <i key={h} style={{ height: h }} />)}
      </span>
      {unread > 0 && (
        <svg width="12" height="9" viewBox="0 0 12 9" aria-label={t('ui.new_messages', unread)}>
          <path d="M0 0h12v9H0zM1 1l5 4 5-4" fill="none" stroke="#fff" />
        </svg>
      )}
      {mode !== 'idle' && <span className="status-flag">{t(mode === 'corner' ? 'ui.flag_corner' : 'ui.flag_drops')}</span>}
      <span className="statusbar-spacer" />
      <span>{pad2(clock.h)}:{pad2(clock.m)}</span>
      <span className="battery" aria-hidden="true"><i /></span>
    </div>
  );
}

/** What the lens shows: status bar, the screen on top of the stack, and anything floating over it. */
export default function Display() {
  const t = useI18n();
  const open = usePhone(s => s.open);
  const booted = usePhone(s => s.booted);
  const state = usePhone(s => s.state);
  const top = usePhone(s => s.stack[s.stack.length - 1]);
  const depth = usePhone(s => s.stack.length);
  const toast = usePhone(s => s.toast);
  const peek = usePhone(s => s.peek);
  const Screen = SCREENS[top.id] ?? Idle;

  return (
    <div className={`screen wp-${state?.settings.wallpaper ?? 'aqua'}`}>
      <StatusBar />
      {/* The key gives each screen its own life: its key handler and state never leak into the next. */}
      {state && open && <Screen key={`${depth}:${top.id}`} {...top.params} />}

      {toast && open && <div className={`toast toast-${toast.tone}`} role="status">{toast.text}</div>}

      {peek && !open && (
        <div className="peek">
          <div>{t('ui.new_message')}</div>
          <div className="peek-from">{peek.name}</div>
          <div className="peek-text">{peek.msg.text}</div>
        </div>
      )}

      {open && !booted && (
        <div className="boot" aria-hidden="true">
          <div className="boot-logo">KOLT</div>
          <div className="boot-line">{t('ui.operator')}</div>
        </div>
      )}

      <div className="screen-grid" />
    </div>
  );
}
