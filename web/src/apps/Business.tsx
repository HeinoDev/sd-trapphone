import { useEffect, useState } from 'react';
import { useKeys } from '@/device/keys';
import { act, call } from '@/nui/call';
import { patchState, pop, serverNow, usePhone } from '@/store/phone';
import type { Turf as TurfData } from '@/store/types';
import { Bars, Frame, List, countdown, money, useListNav, type Row } from '@/ui/kit';
import { useI18n } from '@/i18n';

/** Running the business: start and stop serving, pick what to push, set the pull-up spot. */
export function Hustle() {
  const t = useI18n();
  const state = usePhone(s => s.state)!;
  const setup = usePhone(s => s.setup)!;
  const hustle = state.hustle;
  const [family, setFamily] = useState(hustle?.family ?? 'any');

  const active = hustle && hustle.mode !== 'idle';
  const choices = ['any', ...(hustle?.products ?? []).map(p => p.family)];
  const familyLabel = (id: string) => (id === 'any' ? t('ui.hustle.any') : setup.families[id]?.label ?? id);

  const actions: { id: string; row: Row }[] = [];

  if (active) {
    actions.push({ id: 'stop', row: { key: 'stop', label: t('ui.hustle.stop') } });
  } else {
    actions.push({ id: 'corner', row: { key: 'corner', label: t('ui.hustle.start_corner'), sub: t('ui.hustle.start_corner_sub') } });
    if (hustle?.dropsEnabled) {
      actions.push({ id: 'drops', row: { key: 'drops', label: t('ui.hustle.start_drops'), sub: t('ui.hustle.start_drops_sub') } });
    }
    actions.push({ id: 'family', row: { key: 'family', label: t('ui.hustle.product'), right: `< ${familyLabel(family)} >` } });
  }
  actions.push({
    id: 'spot',
    row: {
      key: 'spot',
      label: t('ui.hustle.spot'),
      sub: t(hustle?.spotSet ? 'ui.hustle.spot_set_sub' : 'ui.hustle.spot_none_sub'),
      right: t(hustle?.spotSet ? 'ui.hustle.spot_set' : 'ui.hustle.spot_none'),
    },
  });

  const nav = useListNav(actions.length);

  const cycle = (delta: number) => {
    const at = Math.max(0, choices.indexOf(family));
    setFamily(choices[(at + delta + choices.length) % choices.length]);
  };

  const run = (id: string) => {
    if (id === 'stop') void act('trap:hustle:stop', undefined, t('ui.hustle.stopped'));
    else if (id === 'corner' || id === 'drops') void act('trap:hustle:start', { mode: id, family }, t('ui.hustle.started'));
    else if (id === 'family') cycle(1);
    else if (id === 'spot') {
      if (hustle?.spotSet) void act('trap:hustle:clearSpot', undefined, t('ui.hustle.spot_cleared'));
      else void act('trap:hustle:setSpot', undefined, t('ui.hustle.spot_saved'));
    }
  };

  useKeys(key => {
    if (nav.handle(key)) return;
    const id = actions[nav.index]?.id;
    if ((key === 'left' || key === 'right') && id === 'family') cycle(key === 'left' ? -1 : 1);
    else if (key === 'ok' || key === 'softL') run(id);
    else if (key === 'softR') pop();
  });

  const title = active
    ? t(hustle.mode === 'corner' ? 'ui.hustle.serving' : 'ui.hustle.taking_orders')
    : t('ui.app.hustle');

  return (
    <Frame title={title} softL={t('ui.select')} softR={t('ui.back')}>
      {hustle?.blocked && !active && <p className="section">{hustle.blocked}</p>}
      {active && hustle.mode === 'drops' && <p className="section">{t('ui.hustle.queue', hustle.queue)}</p>}
      <List rows={actions.map(a => a.row)} index={nav.index} onPick={i => { nav.setIndex(i); run(actions[i].id); }} />
      <p className="section">{t('ui.hustle.holding')}</p>
      <div className="pad">
        {(hustle?.products ?? []).length === 0 && <div>{t('ui.hustle.nothing')}</div>}
        {(hustle?.products ?? []).flatMap(p =>
          p.items.map(it => (
            <div className="kv" key={it.item}>
              <span><span className="row-swatch" style={{ display: 'inline-block', background: p.color, marginRight: 5 }} />{p.label} {setup.units[it.unit]?.short ?? it.unit}</span>
              <b>{it.count}</b>
            </div>
          )),
        )}
      </div>
    </Frame>
  );
}

/** Where you are standing: whose ground it is, how they see you, and what sells here. */
export function Turf() {
  const t = useI18n();
  const turf = usePhone(s => s.state)!.turf;
  const [now, setNow] = useState(serverNow());

  const refresh = async (loud: boolean) => {
    const reply = loud ? await act<TurfData>('trap:turf:refresh') : await call<TurfData>('trap:turf:refresh');
    if (reply.ok && reply.data) patchState({ turf: reply.data });
    setNow(serverNow());
  };

  useEffect(() => {
    void refresh(false);
    // Once, when the app opens.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useKeys(key => {
    if (key === 'softL' || key === 'ok') void refresh(true);
    else if (key === 'softR') pop();
  });

  if (!turf) {
    return (
      <Frame title={t('ui.app.turf')} softL={t('ui.refresh')} softR={t('ui.back')}>
        <p className="empty">{t('ui.loading')}</p>
      </Frame>
    );
  }

  const protectedFor = turf.gang?.protectedUntil ? turf.gang.protectedUntil - now : 0;

  return (
    <Frame title={turf.zone.label} softL={t('ui.refresh')} softR={t('ui.back')}>
      <div className="pad">
        <div className="kv"><span>{t('ui.turf.money')}</span><b>{turf.zone.wealthLabel}</b></div>
        <div className="kv">
          <span>{t('ui.turf.run_by')}</span>
          <b style={turf.gang ? { borderBottom: `3px solid ${turf.gang.color}` } : undefined}>{turf.gang?.label ?? t('ui.turf.nobody')}</b>
        </div>
        {turf.gang && <div className="kv"><span>{t('ui.turf.standing')}</span><b>{turf.gang.standingLabel}</b></div>}
        {turf.gang && (
          <div className="kv">
            <span>{t('ui.turf.protection')}</span>
            <b>{protectedFor > 0 ? countdown(protectedFor) : t('ui.turf.none')}</b>
          </div>
        )}
        <div style={{ marginTop: 6 }}>{t('ui.turf.heat')}</div>
        <div className="meter"><i style={{ width: `${Math.max(0, Math.min(100, turf.heat))}%` }} /></div>
      </div>
      <p className="section">{t('ui.turf.demand')}</p>
      <div className="pad">
        {turf.demand.map(d => (
          <div className="kv" key={d.family}>
            <span><span className="row-swatch" style={{ display: 'inline-block', background: d.color, marginRight: 5 }} />{d.label}</span>
            <b className={d.level === 'high' ? 'tag-good' : d.level === 'low' ? 'tag-bad' : ''}>{t(`ui.turf.level_${d.level}`)}</b>
          </div>
        ))}
      </div>
    </Frame>
  );
}

/** How far the business has come. */
export function Status() {
  const t = useI18n();
  const state = usePhone(s => s.state)!;

  useKeys(key => {
    if (key === 'softR' || key === 'ok') pop();
  });

  return (
    <Frame title={t('ui.app.status')} softR={t('ui.back')}>
      <p className="section">{t('ui.status.name')}</p>
      <div className="pad">
        {(state.rep ?? []).map(r => (
          <div className="kv" key={r.family}>
            <span><span className="row-swatch" style={{ display: 'inline-block', background: r.color, marginRight: 5 }} />{r.label}</span>
            <span>{r.title}{r.level ? ` ${r.level}` : ''} <Bars value={r.bars} /></span>
          </div>
        ))}
      </div>
      <p className="section">{t('ui.status.books')}</p>
      <div className="pad">
        <div className="kv"><span>{t('ui.status.sales')}</span><b>{state.stats.sales}</b></div>
        <div className="kv"><span>{t('ui.status.drops')}</span><b>{state.stats.drops}</b></div>
        <div className="kv"><span>{t('ui.status.earned')}</span><b>{money(state.stats.earned)}</b></div>
        <div className="kv"><span>{t('ui.status.number')}</span><b>{state.phone.number}</b></div>
      </div>
    </Frame>
  );
}
