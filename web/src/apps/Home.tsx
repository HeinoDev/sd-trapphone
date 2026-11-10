import { useState } from 'react';
import { useKeys } from '@/device/keys';
import { pop, push, unreadTotal, usePhone } from '@/store/phone';
import { Frame } from '@/ui/kit';
import Pix from '@/ui/Pix';
import { useI18n } from '@/i18n';

const pad2 = (n: number): string => String(n).padStart(2, '0');

/** The resting screen: wallpaper, clock, and what the business is doing right now. */
export function Idle() {
  const t = useI18n();
  const state = usePhone(s => s.state)!;
  const clock = usePhone(s => s.clock);
  const mode = state.hustle?.mode ?? 'idle';
  const unread = unreadTotal(state);

  useKeys(key => {
    if (key === 'softL' || key === 'ok') push('menu');
    else if (key === 'softR') push('contacts');
    else if (key === 'call') push('messages');
    else if (/^[0-9]$/.test(key)) push('dialer', { start: key });
  });

  return (
    <Frame bare softL={t('ui.menu')} softR={t('ui.names')}>
      <div className="idle">
        <div className="idle-operator">{t('ui.operator')}</div>
        <div className="idle-clock">{pad2(clock.h)}:{pad2(clock.m)}</div>
        {unread > 0 && <div className="idle-line">{t(unread === 1 ? 'ui.new_message' : 'ui.new_messages', unread)}</div>}
        {mode !== 'idle' && (
          <div className="idle-line">
            {t(mode === 'corner' ? 'ui.hustle.serving' : 'ui.hustle.taking_orders')}
            {state.turf ? `, ${state.turf.zone.label}` : ''}
          </div>
        )}
        <div className="idle-note">{state.phone.number}</div>
      </div>
    </Frame>
  );
}

const APPS = ['messages', 'contacts', 'hustle', 'turf', 'status', 'games', 'tones', 'themes', 'help'] as const;

/** The 3 x 3 main menu. The title bar names whatever is highlighted. */
export function Menu() {
  const t = useI18n();
  const state = usePhone(s => s.state)!;
  const [index, setIndex] = useState(0);
  const unread = unreadTotal(state);

  const move = (dx: number, dy: number) => {
    const col = (index % 3 + dx + 3) % 3;
    const row = (Math.floor(index / 3) + dy + 3) % 3;
    setIndex(row * 3 + col);
  };

  useKeys(key => {
    if (key === 'left') move(-1, 0);
    else if (key === 'right') move(1, 0);
    else if (key === 'up') move(0, -1);
    else if (key === 'down') move(0, 1);
    else if (key === 'ok' || key === 'softL') push(APPS[index]);
    else if (key === 'softR') pop();
    else if (/^[1-9]$/.test(key)) push(APPS[Number(key) - 1]);
  });

  return (
    <Frame bare title={t(`ui.app.${APPS[index]}`)} softL={t('ui.select')} softR={t('ui.back')}>
      <div className="menu">
        {APPS.map((id, i) => (
          <button
            type="button"
            key={id}
            className={`tile${i === index ? ' tile-on' : ''}`}
            aria-label={t(`ui.app.${id}`)}
            onMouseEnter={() => setIndex(i)}
            onClick={() => push(id)}
          >
            <Pix name={id} />
            {id === 'messages' && unread > 0 && <span className="tile-badge">{unread}</span>}
          </button>
        ))}
      </div>
    </Frame>
  );
}
