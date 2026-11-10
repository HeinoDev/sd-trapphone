import { useEffect, useState } from 'react';
import { useKeys } from '@/device/keys';
import { act, call } from '@/nui/call';
import { pop, push, replace, showToast, usePhone } from '@/store/phone';
import { Confirm, Frame, List, TextBox, money, useListNav, useTextField, type Row } from '@/ui/kit';
import { useI18n } from '@/i18n';

/** Saved numbers. The first row adds a new one. */
export function Contacts() {
  const t = useI18n();
  const state = usePhone(s => s.state)!;
  const setup = usePhone(s => s.setup)!;
  const contacts = [...state.contacts].sort((a, b) => a.name.localeCompare(b.name));
  const nav = useListNav(contacts.length + 1);

  const rows: Row[] = [
    { key: '+', label: t('ui.contacts.new') },
    ...contacts.map(c => ({ key: c.number, label: c.name, sub: setup.contactTypes[c.type]?.label ?? c.type, right: c.number })),
  ];

  const open = (i: number) => {
    if (i === 0) push('addcontact', {});
    else push('contact', { number: contacts[i - 1].number });
  };

  useKeys(key => {
    if (nav.handle(key)) return;
    if (key === 'ok' || key === 'softL') open(nav.index);
    else if (key === 'softR') pop();
  });

  return (
    <Frame title={t('ui.app.contacts')} softL={t('ui.open')} softR={t('ui.back')}>
      <List rows={rows} index={nav.index} onPick={i => { nav.setIndex(i); open(i); }} />
    </Frame>
  );
}

/** Contact types that can be met in person and can pass their number on. */
const SPECIAL = new Set(['plug', 'supplier', 'gang', 'informant', 'launderer', 'fixer']);

interface Card {
  text: string;
  detail?: string;
  /** Present when the card is a question: what Yes does. */
  yes?: () => void;
}

/** One contact: what you can ask of them. */
export function ContactView({ number }: { number: string }) {
  const t = useI18n();
  const state = usePhone(s => s.state)!;
  const setup = usePhone(s => s.setup)!;
  const contact = state.contacts.find(c => c.number === number);
  const [card, setCard] = useState<Card | null>(null);

  const type = contact?.type ?? 'custom';
  const actions = [...(setup.contactTypes[type]?.actions ?? ['message'])];
  if (SPECIAL.has(type)) {
    actions.push('route');
    if (setup.canPassNumbers) actions.push('share');
  }
  actions.push('delete');

  const nav = useListNav(actions.length);

  const run = async (action: string) => {
    if (action === 'message') {
      push(state.threads.some(th => th.number === number) ? 'thread' : 'compose', { number });
    } else if (action === 'order') {
      push('order', { number });
    } else if (action === 'delete') {
      await call('trap:contact:delete', { number });
      pop();
    } else if (action === 'bribe') {
      const info = await act<{ price: number; hours: number; allowed: boolean; reason?: string }>('trap:contact:action', { number, action });
      if (!info.ok || !info.data) return;
      if (!info.data.allowed) {
        setCard({ text: info.data.reason ?? t('ui.contacts.bribe_refused') });
        return;
      }
      setCard({
        text: t('ui.contacts.bribe_ask', money(info.data.price)),
        detail: t('ui.contacts.bribe_detail', info.data.hours),
        yes: () => void act('trap:contact:action', { number, action, args: { confirm: true } }, t('ui.contacts.bribe_done')),
      });
    } else if (action === 'intel') {
      const info = await act<{ price: number }>('trap:contact:action', { number, action });
      if (!info.ok || !info.data) return;
      setCard({
        text: t('ui.contacts.intel_ask', money(info.data.price)),
        yes: () => void act('trap:contact:action', { number, action, args: { confirm: true } }, t('ui.contacts.intel_done')),
      });
    } else if (action === 'standing') {
      const info = await act<{ label: string; standingLabel: string }>('trap:contact:action', { number, action });
      if (info.ok && info.data) setCard({ text: info.data.label, detail: info.data.standingLabel });
    } else {
      // wash, market, route, share: the server does it and says how it went.
      const reply = await act<{ label?: string }>('trap:contact:action', { number, action });
      if (reply.ok) showToast(t(`ui.contacts.${action}_done`, reply.data?.label ?? ''), 'good');
    }
  };

  useKeys(key => {
    if (card) {
      if ((key === 'ok' || key === 'softL') && card.yes) card.yes();
      setCard(null);
      return;
    }
    if (nav.handle(key)) return;
    if (key === 'ok' || key === 'softL') void run(actions[nav.index]);
    else if (key === 'softR') pop();
  });

  const rows: Row[] = actions.map(a => ({ key: a, label: t(`ui.action.${a}`) }));

  return (
    <Frame
      title={contact?.name ?? number}
      softL={card ? (card.yes ? t('ui.yes') : t('ui.ok')) : t('ui.select')}
      softR={card ? (card.yes ? t('ui.no') : '') : t('ui.back')}
    >
      <div className="pad">
        <div className="kv"><span>{setup.contactTypes[type]?.label ?? type}</span><b>{number}</b></div>
      </div>
      <List rows={rows} index={nav.index} onPick={i => { nav.setIndex(i); void run(actions[i]); }} />
      {card && <Confirm text={card.text} detail={card.detail} />}
    </Frame>
  );
}

interface StockLine {
  item: string;
  label: string;
  price: number;
  max: number;
  locked?: boolean;
}

/** Ordering from a plug or supplier. Left and right change the amount; pay when you collect. */
export function Order({ number }: { number: string }) {
  const t = useI18n();
  const contact = usePhone(s => s.state)!.contacts.find(c => c.number === number);
  const [stock, setStock] = useState<StockLine[] | null>(null);
  const [wait, setWait] = useState(0);
  const [qty, setQty] = useState<Record<string, number>>({});
  const nav = useListNav(stock?.length ?? 0);

  useEffect(() => {
    let alive = true;

    void call<{ items: StockLine[]; cooldown?: number }>('trap:contact:action', { number, action: 'order' }).then(reply => {
      if (!alive) return;
      if (!reply.ok || !reply.data) {
        showToast(reply.error ?? t('ui.failed'), 'bad');
        pop();
        return;
      }
      setStock(reply.data.items ?? []);
      setWait(reply.data.cooldown ?? 0);
    });

    return () => {
      alive = false;
    };
  }, [number, t]);

  const total = (stock ?? []).reduce((sum, line) => sum + (qty[line.item] ?? 0) * line.price, 0);

  const change = (delta: number) => {
    const line = stock?.[nav.index];
    if (!line || line.locked) return;

    setQty(q => ({ ...q, [line.item]: Math.max(0, Math.min(line.max, (q[line.item] ?? 0) + delta)) }));
  };

  const send = async () => {
    const lines = Object.entries(qty).filter(([, n]) => n > 0).map(([item, n]) => ({ item, qty: n }));
    if (lines.length === 0) return;

    const reply = await act('trap:contact:action', { number, action: 'order', args: { lines } }, t('ui.contacts.order_done'));
    if (reply.ok) pop();
  };

  useKeys(key => {
    if (nav.handle(key)) return;
    if (key === 'left') change(-1);
    else if (key === 'right' || key === 'ok') change(1);
    else if (key === 'softL') void send();
    else if (key === 'softR') pop();
  });

  const rows: Row[] = (stock ?? []).map(line => ({
    key: line.item,
    label: line.label,
    sub: line.locked ? t('ui.contacts.locked') : t('ui.contacts.each', money(line.price), line.max),
    right: line.locked ? '' : `< ${qty[line.item] ?? 0} >`,
    dim: line.locked,
  }));

  return (
    <Frame
      title={total > 0 ? t('ui.contacts.order_total', money(total)) : contact?.name ?? number}
      softL={total > 0 ? t('ui.contacts.order') : ''}
      softR={t('ui.back')}
    >
      {wait > 0 && <p className="section">{t('ui.contacts.order_wait', Math.ceil(wait / 60))}</p>}
      {stock === null ? <p className="empty">{t('ui.loading')}</p> : (
        <List rows={rows} index={nav.index} onPick={i => { nav.setIndex(i); }} empty={t('ui.contacts.no_stock')} />
      )}
    </Frame>
  );
}

/** Saving a number: the number first (unless one was passed in), then a name. */
export function AddContact({ number }: { number?: string }) {
  const [picked, setPicked] = useState(number ?? '');

  return picked
    ? <NameStep number={picked} />
    : <NumberStep onDone={setPicked} />;
}

function NumberStep({ onDone }: { onDone: (number: string) => void }) {
  const t = useI18n();
  const field = useTextField({ max: 12, numeric: true, allow: '-' });

  useKeys(key => {
    if (field.handle(key)) return;
    if ((key === 'ok' || key === 'softL') && field.value.length >= 3) onDone(field.value);
    else if (key === 'softR') {
      if (field.value) field.backspace();
      else pop();
    }
  });

  return (
    <Frame title={t('ui.contacts.new')} softL={t('ui.next')} softR={field.value ? t('ui.clear') : t('ui.back')}>
      <TextBox label={t('ui.contacts.number')} value={field.value} mode={t('ui.contacts.dash_hint')} />
    </Frame>
  );
}

function NameStep({ number }: { number: string }) {
  const t = useI18n();
  const field = useTextField({ max: 24 });

  const save = async () => {
    const name = field.value.trim();
    if (!name) return;

    const reply = await act('trap:contact:add', { number, name }, t('ui.contacts.saved'));
    if (reply.ok) pop();
  };

  useKeys(key => {
    if (field.handle(key)) return;
    if (key === 'ok' || key === 'softL') void save();
    else if (key === 'softR') {
      if (field.value) field.backspace();
      else pop();
    }
  });

  return (
    <Frame title={number} softL={t('ui.save')} softR={field.value ? t('ui.clear') : t('ui.back')}>
      <TextBox label={t('ui.contacts.name')} value={field.value} mode={field.mode} />
    </Frame>
  );
}

/** Digits typed on the idle screen land here. Save the number, or text it with the green key. */
export function Dialer({ start }: { start?: string }) {
  const t = useI18n();
  const field = useTextField({ initial: start ?? '', max: 12, numeric: true, allow: '-' });

  useKeys(key => {
    if (key === 'call' && field.value.length >= 3) {
      replace('compose', { number: field.value });
      return;
    }
    if (field.handle(key)) return;
    if ((key === 'ok' || key === 'softL') && field.value.length >= 3) replace('addcontact', { number: field.value });
    else if (key === 'softR') {
      if (field.value.length > 1) field.backspace();
      else pop();
    }
  });

  return (
    <Frame title={t('ui.dialer.title')} softL={t('ui.save')} center={t('ui.dialer.text')} softR={field.value.length > 1 ? t('ui.clear') : t('ui.back')}>
      <TextBox value={field.value} mode={t('ui.contacts.dash_hint')} />
    </Frame>
  );
}
