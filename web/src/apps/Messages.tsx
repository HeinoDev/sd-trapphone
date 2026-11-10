import { useEffect, useRef, useState } from 'react';
import { useKeys } from '@/device/keys';
import { act, call } from '@/nui/call';
import { dropThread, markRead, pop, push, serverNow, usePhone } from '@/store/phone';
import type { Offer, Thread as ThreadData } from '@/store/types';
import { Frame, List, TextBox, ago, countdown, money, useListNav, useTextField, type Row } from '@/ui/kit';
import { useI18n } from '@/i18n';

/** Re-render once a second, for countdowns. */
function useTick(): number {
  const [now, setNow] = useState(serverNow());

  useEffect(() => {
    const id = window.setInterval(() => setNow(serverNow()), 1000);
    return () => window.clearInterval(id);
  }, []);

  return now;
}

/** Every conversation, newest first. */
export function Messages() {
  const t = useI18n();
  const threads = usePhone(s => s.state)!.threads;
  const now = useTick();
  const nav = useListNav(threads.length);

  const rows: Row[] = threads.map(th => {
    const last = th.msgs[th.msgs.length - 1];
    return {
      key: th.number,
      label: th.name,
      sub: last ? `${last.from === 'me' ? t('ui.you') + ': ' : ''}${last.text}` : '',
      right: ago(th.ts, now),
      dot: th.unread > 0,
    };
  });

  const open = (i: number) => {
    if (threads[i]) push('thread', { number: threads[i].number });
  };

  useKeys(key => {
    if (nav.handle(key)) return;
    if (key === 'ok' || key === 'softL') open(nav.index);
    else if (key === 'softR') pop();
  });

  return (
    <Frame title={t('ui.app.messages')} softL={threads.length ? t('ui.open') : ''} softR={t('ui.back')}>
      <div className="messages-list">
        <List rows={rows} index={nav.index} onPick={i => { nav.setIndex(i); open(i); }} empty={t('ui.messages.empty')} />
      </div>
    </Frame>
  );
}

const OPEN_STATES = new Set(['open', 'accepted']);

/** The offer a conversation is currently about, if it can still be answered. */
function liveOffer(thread: ThreadData | undefined, now: number): Offer | null {
  if (!thread) return null;

  for (let i = thread.msgs.length - 1; i >= 0; i--) {
    const offer = thread.msgs[i].offer;
    if (offer) return OPEN_STATES.has(offer.state) && offer.expires > now ? offer : null;
  }

  return null;
}

function Ticket({ offer, now }: { offer: Offer; now: number }) {
  const t = useI18n();
  const setup = usePhone(s => s.setup)!;
  const unit = setup.units[offer.unit]?.label ?? offer.unit;
  const live = OPEN_STATES.has(offer.state) && offer.expires > now;
  const state = !live && OPEN_STATES.has(offer.state) ? 'expired' : offer.state;

  return (
    <div className={`ticket${live ? '' : ' ticket-closed'}`}>
      <div className="ticket-line">
        <span>{offer.qty} x {unit} {offer.label}</span>
        <span>{money(offer.price)}</span>
      </div>
      <div className="ticket-meta">
        <span className={state === 'done' || state === 'accepted' ? 'tag-good' : live ? '' : 'tag-bad'}>
          {t(`ui.offer.${state}`)}
        </span>
        <span>{live ? countdown(offer.expires - now) : offer.place ?? ''}</span>
      </div>
      {live && offer.place && <div className="ticket-meta"><span>{offer.place}</span></div>}
    </div>
  );
}

/** One conversation. Offers ride on messages as tickets; Options answers the live one. */
export function ThreadView({ number }: { number: string }) {
  const t = useI18n();
  const state = usePhone(s => s.state)!;
  const thread = state.threads.find(th => th.number === number);
  const now = useTick();
  const body = useRef<HTMLDivElement | null>(null);
  const [menu, setMenu] = useState(false);
  const offer = liveOffer(thread, now);
  const saved = state.contacts.some(c => c.number === number);
  const count = thread?.msgs.length ?? 0;

  useEffect(() => {
    markRead(number);
    void call('trap:thread:read', { number });
  }, [number, count]);

  useEffect(() => {
    const el = body.current?.parentElement;
    if (el) el.scrollTop = el.scrollHeight;
  }, [count, menu]);

  const options: { id: string; label: string }[] = [];
  if (offer?.state === 'open') {
    options.push({ id: 'accept', label: t('ui.offer.accept') });
    if (offer.counters > 0 && offer.kind !== 'drop') options.push({ id: 'counter', label: t('ui.offer.counter') });
    options.push({ id: 'decline', label: t('ui.offer.decline') });
  }
  if (thread?.kind !== 'system') options.push({ id: 'reply', label: t('ui.reply') });
  if (!saved && thread?.kind !== 'system') options.push({ id: 'save', label: t('ui.save_number') });
  options.push({ id: 'delete', label: t('ui.delete_chat') });

  const nav = useListNav(options.length);

  const run = (id: string) => {
    setMenu(false);

    if (id === 'accept' || id === 'decline') {
      void act('trap:offer:respond', { number, ticketId: offer?.ticketId, action: id });
    } else if (id === 'counter' && offer) {
      push('counter', { number, ticketId: offer.ticketId, price: offer.price });
    } else if (id === 'reply') {
      push('compose', { number });
    } else if (id === 'save') {
      push('addcontact', { number });
    } else if (id === 'delete') {
      void call('trap:thread:delete', { number });
      dropThread(number);
      pop();
    }
  };

  useKeys(key => {
    if (menu) {
      if (nav.handle(key)) return;
      if (key === 'ok' || key === 'softL') run(options[nav.index].id);
      else if (key === 'softR') setMenu(false);
      return;
    }

    const el = body.current?.parentElement;
    if (key === 'up' && el) el.scrollTop -= 48;
    else if (key === 'down' && el) el.scrollTop += 48;
    else if (key === 'softL') { nav.setIndex(0); setMenu(true); }
    else if (key === 'ok') run(offer?.state === 'open' ? 'accept' : 'reply');
    else if (key === 'softR') pop();
  });

  if (menu) {
    return (
      <Frame title={thread?.name ?? number} softL={t('ui.select')} softR={t('ui.back')}>
        <List rows={options.map(o => ({ key: o.id, label: o.label }))} index={nav.index} onPick={i => run(options[i].id)} />
      </Frame>
    );
  }

  return (
    <Frame
      title={thread?.name ?? number}
      softL={t('ui.options')}
      center={offer?.state === 'open' ? t('ui.offer.accept') : undefined}
      softR={t('ui.back')}
    >
      <div className="thread" ref={body}>
        {(thread?.msgs ?? []).map(m => (
          <div key={m.id} className={`bubble${m.from === 'me' ? ' bubble-me' : ''}`}>
            {m.text}
            {m.offer && <Ticket offer={m.offer} now={now} />}
            <span className="bubble-time">{ago(m.ts, now)}</span>
          </div>
        ))}
        {count === 0 && <p className="empty">{t('ui.messages.none_yet')}</p>}
      </div>
    </Frame>
  );
}

/** Naming your own price. The customer may take it, push back, or walk. */
export function Counter({ number, ticketId, price }: { number: string; ticketId: string | number; price: number }) {
  const t = useI18n();
  const field = useTextField({ max: 6, numeric: true });

  const send = () => {
    const ask = Number(field.value);
    if (!ask) return;

    void act('trap:offer:respond', { number, ticketId, action: 'counter', price: ask });
    pop();
  };

  useKeys(key => {
    if (field.handle(key)) return;
    if (key === 'ok' || key === 'softL') send();
    else if (key === 'softR') {
      if (field.value) field.backspace();
      else pop();
    }
  });

  return (
    <Frame title={t('ui.offer.counter')} softL={t('ui.send')} softR={field.value ? t('ui.clear') : t('ui.back')}>
      <div className="pad">
        <div className="kv"><span>{t('ui.offer.their_offer')}</span><b>{money(price)}</b></div>
      </div>
      <TextBox label={t('ui.offer.your_price')} prefix="$" value={field.value} />
    </Frame>
  );
}

export function Compose({ number }: { number: string }) {
  const t = useI18n();
  const thread = usePhone(s => s.state)!.threads.find(th => th.number === number);
  const contact = usePhone(s => s.state)!.contacts.find(c => c.number === number);
  const field = useTextField({ max: 160 });

  const send = () => {
    const text = field.value.trim();
    if (!text) return;

    void act('trap:message:send', { number, text });
    pop();
  };

  useKeys(key => {
    if (field.handle(key)) return;
    if (key === 'ok' || key === 'softL') send();
    else if (key === 'softR') {
      if (field.value) field.backspace();
      else pop();
    }
  });

  return (
    <Frame title={t('ui.to', thread?.name ?? contact?.name ?? number)} softL={t('ui.send')} softR={field.value ? t('ui.clear') : t('ui.back')}>
      <TextBox value={field.value} mode={`${field.mode}  ${field.value.length}/160`} />
    </Frame>
  );
}
