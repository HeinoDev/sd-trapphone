import { useEffect, useRef, useState } from 'react';
import { useKeys, type Key } from '@/device/keys';
import { playBad, playGood, playRingtone } from '@/device/sound';
import { call } from '@/nui/call';
import { patchState, pop, usePhone } from '@/store/phone';
import type { Settings } from '@/store/types';
import { Frame, List, useListNav, type Row } from '@/ui/kit';
import { useI18n } from '@/i18n';

/** Save one setting: the screen follows straight away, the server is told behind it. */
function setSetting<K extends keyof Settings>(key: K, value: Settings[K]): void {
  const state = usePhone.getState().state;
  if (!state) return;

  patchState({ settings: { ...state.settings, [key]: value } });
  void call('trap:settings:set', { key, value });
}

/** Ringtones and volume. Moving onto a tone plays it. */
export function Tones() {
  const t = useI18n();
  const settings = usePhone(s => s.state)!.settings;
  const tones = usePhone(s => s.setup)!.ringtones;
  const nav = useListNav(tones.length + 1, Math.max(0, tones.indexOf(settings.ringtone)) + 1);
  const steps = Math.round(settings.volume * 5);

  useEffect(() => {
    if (nav.index > 0) playRingtone(tones[nav.index - 1]);
  }, [nav.index, tones]);

  const volume = (delta: number) => {
    setSetting('volume', Math.max(0, Math.min(5, steps + delta)) / 5);
    window.setTimeout(() => playRingtone(settings.ringtone), 30);
  };

  useKeys(key => {
    if (nav.handle(key)) return;
    if (nav.index === 0 && (key === 'left' || key === 'right')) volume(key === 'left' ? -1 : 1);
    else if ((key === 'ok' || key === 'softL') && nav.index > 0) setSetting('ringtone', tones[nav.index - 1]);
    else if (key === 'softR') pop();
  });

  const rows: Row[] = [
    { key: 'volume', label: t('ui.tones.volume'), right: `< ${steps}/5 >` },
    ...tones.map(id => ({ key: id, label: t(`ui.tones.${id}`), right: id === settings.ringtone ? t('ui.on') : '' })),
  ];

  return (
    <Frame title={t('ui.app.tones')} softL={nav.index > 0 ? t('ui.select') : ''} softR={t('ui.back')}>
      <List rows={rows} index={nav.index} onPick={i => { nav.setIndex(i); if (i > 0) setSetting('ringtone', tones[i - 1]); }} />
    </Frame>
  );
}

/** Wallpaper. The faceplate is not here: it is the colour of the phone you bought. */
export function Themes() {
  const t = useI18n();
  const settings = usePhone(s => s.state)!.settings;
  const options = usePhone(s => s.setup)!.wallpapers;
  const index = Math.max(0, options.indexOf(settings.wallpaper));

  const step = (delta: number) => setSetting('wallpaper', options[(index + delta + options.length) % options.length]);

  useKeys(key => {
    if (key === 'left' || key === 'up') step(-1);
    else if (key === 'right' || key === 'down' || key === 'softL') step(1);
    else if (key === 'softR' || key === 'ok') pop();
  });

  return (
    <Frame title={t('ui.themes.wallpaper')} softL={t('ui.next')} softR={t('ui.back')}>
      <div className="swatches">
        {options.map(id => (
          <button
            type="button"
            key={id}
            aria-label={t(`ui.themes.wallpaper_${id}`)}
            className={`swatch wp-${id}${id === settings.wallpaper ? ' swatch-on' : ''}`}
            onClick={() => setSetting('wallpaper', id)}
          />
        ))}
      </div>
      <div className="swatch-name">{`< ${t(`ui.themes.wallpaper_${settings.wallpaper}`)} >`}</div>
    </Frame>
  );
}

const HELP_PAGES = 6;

/** A few pages on how the phone runs the business. */
export function Help() {
  const t = useI18n();
  const [page, setPage] = useState(1);

  useKeys(key => {
    if (key === 'right' || key === 'ok' || key === 'softL' || key === 'down') setPage(p => (p % HELP_PAGES) + 1);
    else if (key === 'left' || key === 'up') setPage(p => ((p + HELP_PAGES - 2) % HELP_PAGES) + 1);
    else if (key === 'softR') pop();
  });

  return (
    <Frame title={t(`ui.help.title_${page}`)} softL={t('ui.next')} center={`${page}/${HELP_PAGES}`} softR={t('ui.back')}>
      <div className="pad">{t(`ui.help.body_${page}`)}</div>
    </Frame>
  );
}

const COLS = 19;
const ROWS = 17;
const DIRS: Partial<Record<Key, [number, number]>> = {
  up: [0, -1], '2': [0, -1],
  down: [0, 1], '8': [0, 1],
  left: [-1, 0], '4': [-1, 0],
  right: [1, 0], '6': [1, 0],
};

interface Game {
  body: [number, number][];
  dir: [number, number];
  next: [number, number];
  food: [number, number];
  /** A bonus crumb that vanishes if you are slow. */
  bonus: { at: [number, number]; ticks: number } | null;
  score: number;
  over: boolean;
}

const freeCell = (body: [number, number][]): [number, number] => {
  for (;;) {
    const cell: [number, number] = [Math.floor(Math.random() * COLS), Math.floor(Math.random() * ROWS)];
    if (!body.some(b => b[0] === cell[0] && b[1] === cell[1])) return cell;
  }
};

const newGame = (): Game => {
  const body: [number, number][] = [[9, 8], [8, 8], [7, 8]];
  return { body, dir: [1, 0], next: [1, 0], food: freeCell(body), bonus: null, score: 0, over: false };
};

/** Worm: steer with the d-pad or 2 4 6 8. It speeds up as it grows, and the walls wrap. */
export function Worm() {
  const t = useI18n();
  const best = usePhone(s => s.state)!.scores.worm ?? 0;
  const canvas = useRef<HTMLCanvasElement | null>(null);
  const game = useRef<Game>(newGame());
  const [running, setRunning] = useState(false);
  const [score, setScore] = useState(0);
  const [over, setOver] = useState(false);

  const draw = () => {
    const el = canvas.current;
    const g = el?.getContext('2d');
    if (!el || !g) return;

    const cell = Math.floor(Math.min(el.width / COLS, el.height / ROWS));
    const ox = Math.floor((el.width - cell * COLS) / 2);
    const oy = Math.floor((el.height - cell * ROWS) / 2);
    const state = game.current;

    g.fillStyle = '#9bbc0f';
    g.fillRect(0, 0, el.width, el.height);
    g.fillStyle = '#8bac0f';
    g.fillRect(ox, oy, cell * COLS, cell * ROWS);

    g.fillStyle = '#0f380f';
    state.body.forEach(([x, y]) => g.fillRect(ox + x * cell + 1, oy + y * cell + 1, cell - 2, cell - 2));

    g.fillStyle = '#306230';
    g.fillRect(ox + state.food[0] * cell + 3, oy + state.food[1] * cell + 3, cell - 6, cell - 6);

    if (state.bonus && state.bonus.ticks % 2 === 0) {
      g.fillStyle = '#0f380f';
      g.fillRect(ox + state.bonus.at[0] * cell + 2, oy + state.bonus.at[1] * cell + 5, cell - 4, 2);
      g.fillRect(ox + state.bonus.at[0] * cell + 5, oy + state.bonus.at[1] * cell + 2, 2, cell - 4);
    }
  };

  const finish = () => {
    const state = game.current;
    state.over = true;
    setRunning(false);
    setOver(true);

    if (state.score > best) {
      playGood();
      patchState({ scores: { ...usePhone.getState().state!.scores, worm: state.score } });
    } else {
      playBad();
    }
    void call('trap:score:submit', { game: 'worm', score: state.score });
  };

  const tick = () => {
    const state = game.current;
    state.dir = state.next;

    const head: [number, number] = [
      (state.body[0][0] + state.dir[0] + COLS) % COLS,
      (state.body[0][1] + state.dir[1] + ROWS) % ROWS,
    ];

    if (state.body.some(b => b[0] === head[0] && b[1] === head[1])) {
      finish();
      return;
    }

    state.body.unshift(head);

    if (head[0] === state.food[0] && head[1] === state.food[1]) {
      state.score += 10;
      state.food = freeCell(state.body);
      if (!state.bonus && Math.random() < 0.25) state.bonus = { at: freeCell(state.body), ticks: 34 };
    } else if (state.bonus && head[0] === state.bonus.at[0] && head[1] === state.bonus.at[1]) {
      state.score += 10 + state.bonus.ticks;
      state.bonus = null;
      state.body.pop();
    } else {
      state.body.pop();
    }

    if (state.bonus && --state.bonus.ticks <= 0) state.bonus = null;

    setScore(state.score);
    draw();
  };

  useEffect(() => {
    const el = canvas.current;
    if (el) {
      el.width = el.clientWidth;
      el.height = el.clientHeight;
    }
    draw();
    // Size the canvas once it is laid out.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    if (!running) return;

    let timer = 0;
    const loop = () => {
      tick();
      if (!game.current.over) timer = window.setTimeout(loop, Math.max(70, 170 - game.current.body.length * 3));
    };
    timer = window.setTimeout(loop, 170);

    return () => window.clearTimeout(timer);
    // The loop reads the game through a ref, so it only restarts on pause and resume.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [running]);

  const start = () => {
    if (over || game.current.over) {
      game.current = newGame();
      setScore(0);
      setOver(false);
      draw();
    }
    setRunning(r => !r);
  };

  useKeys(key => {
    const dir = DIRS[key];
    if (dir && running) {
      const cur = game.current.dir;
      if (cur[0] + dir[0] !== 0 || cur[1] + dir[1] !== 0) game.current.next = dir;
      return;
    }
    if (key === 'softL' || key === 'ok' || key === '5') start();
    else if (key === 'softR') pop();
  });

  return (
    <Frame softL={running ? t('ui.worm.pause') : over ? t('ui.worm.again') : t('ui.worm.start')} softR={t('ui.back')}>
      <div className="worm-wrap">
        <div className="worm-hud">
          <span>{over ? t('ui.worm.over') : t('ui.app.games')}</span>
          <span>{score} / {Math.max(best, score)}</span>
        </div>
        <canvas className="worm-canvas" ref={canvas} />
      </div>
    </Frame>
  );
}
