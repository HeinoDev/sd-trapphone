import { useCallback, useEffect, useRef, useState, type ReactNode } from 'react';
import { MULTITAP, press, useTextSink, type Key } from '@/device/keys';
import { fetchNui } from '@/nui/bridge';

// The few pieces every screen is built from: the titled frame with its two soft keys, a
// list you move through with the d-pad, and a text field fed by the keypad or the keyboard.

interface FrameProps {
  title?: string;
  softL?: string;
  softR?: string;
  /** Small hint between the soft keys (what the centre key does). */
  center?: string;
  /** No title bar and no panel: the wallpaper shows through (idle screen, menu). */
  bare?: boolean;
  children: ReactNode;
}

export function Frame({ title, softL, softR, center, bare, children }: FrameProps) {
  return (
    <div className={`frame${bare ? ' frame-bare' : ''}`}>
      {title !== undefined && <div className="frame-title">{title}</div>}
      <div className="frame-body">{children}</div>
      <div className="softbar">
        <button type="button" className="softbar-key" onClick={() => press('softL')}>{softL ?? ''}</button>
        <span className="softbar-mid">{center ?? ''}</span>
        <button type="button" className="softbar-key softbar-key-r" onClick={() => press('softR')}>{softR ?? ''}</button>
      </div>
    </div>
  );
}

/** Up/down through `count` rows, wrapping at the ends. */
export function useListNav(count: number, initial = 0) {
  const [index, setIndex] = useState(initial);
  const safe = count === 0 ? 0 : Math.min(index, count - 1);

  const handle = useCallback(
    (key: Key): boolean => {
      if (count === 0) return false;
      if (key === 'up') {
        setIndex(i => (Math.min(i, count - 1) - 1 + count) % count);
        return true;
      }
      if (key === 'down') {
        setIndex(i => (Math.min(i, count - 1) + 1) % count);
        return true;
      }
      return false;
    },
    [count],
  );

  return { index: safe, setIndex, handle };
}

export interface Row {
  key: string;
  label: string;
  sub?: string;
  right?: string;
  /** A coloured square before the label (a product's colour, a gang's colour). */
  swatch?: string;
  dot?: boolean;
  dim?: boolean;
}

interface ListProps {
  rows: Row[];
  index: number;
  onPick: (index: number) => void;
  empty?: string;
}

/** A scrolling list. Clicking a row selects it and presses the centre key. */
export function List({ rows, index, onPick, empty }: ListProps) {
  const active = useRef<HTMLButtonElement | null>(null);

  useEffect(() => {
    active.current?.scrollIntoView({ block: 'nearest' });
  }, [index, rows.length]);

  if (rows.length === 0) return <p className="empty">{empty ?? ''}</p>;

  return (
    <div className="list">
      {rows.map((row, i) => (
        <button
          type="button"
          key={row.key}
          ref={i === index ? active : undefined}
          className={`row${i === index ? ' row-on' : ''}${row.dim ? ' row-dim' : ''}`}
          onClick={() => onPick(i)}
        >
          {row.swatch && <span className="row-swatch" style={{ background: row.swatch }} />}
          <span className="row-text">
            <span className="row-label">
              {row.dot && <span className="row-dot" />}
              {row.label}
            </span>
            {row.sub && <span className="row-sub">{row.sub}</span>}
          </span>
          {row.right && <span className="row-right">{row.right}</span>}
        </button>
      ))}
    </div>
  );
}

/** A row of five blocks, as phones of the time drew signal and battery. */
export function Bars({ value, of = 5, color }: { value: number; of?: number; color?: string }) {
  return (
    <span className="bars" aria-label={`${value} of ${of}`}>
      {Array.from({ length: of }, (_, i) => (
        <span key={i} className={`bars-cell${i < value ? ' bars-on' : ''}`} style={i < value && color ? { background: color } : undefined} />
      ))}
    </span>
  );
}

type Mode = 'abc' | 'Abc' | '123';

interface TextOptions {
  initial?: string;
  max: number;
  /** Digits only (prices, phone numbers). `allow` adds extra characters, e.g. '-'. */
  numeric?: boolean;
  allow?: string;
}

/**
 * A text field. Typing on the real keyboard goes straight in; clicking the keypad multi-taps
 * the way it did on the handset. While it is mounted the game gives the keyboard to the page.
 */
export function useTextField({ initial = '', max, numeric, allow = '' }: TextOptions) {
  const [value, setValue] = useState(initial);
  const [mode, setMode] = useState<Mode>(numeric ? '123' : 'abc');
  const tap = useRef<{ key: string; index: number; at: number } | null>(null);

  useEffect(() => {
    void fetchNui('trap:typing', { on: true });
    return () => {
      void fetchNui('trap:typing', { on: false });
    };
  }, []);

  const accepts = useCallback(
    (ch: string) => (numeric ? /[0-9]/.test(ch) || allow.includes(ch) : ch >= ' ' && ch !== '\u007f'),
    [numeric, allow],
  );

  const backspace = useCallback(() => {
    tap.current = null;
    setValue(v => v.slice(0, -1));
  }, []);

  useTextSink({
    char: ch => {
      tap.current = null;
      if (accepts(ch)) setValue(v => (v.length < max ? v + ch : v));
    },
    backspace,
  });

  /** Feed a keypad key. Returns true when the field used it. */
  const handle = useCallback(
    (key: Key): boolean => {
      if (key === '#' && !numeric) {
        tap.current = null;
        setMode(m => (m === 'abc' ? 'Abc' : m === 'Abc' ? '123' : 'abc'));
        return true;
      }
      if (key === '*') {
        if (numeric && !allow.includes('-')) return true;
        tap.current = null;
        setValue(v => (v.length < max ? v + (numeric ? '-' : '*') : v));
        return true;
      }
      if (!/^[0-9]$/.test(key)) return false;

      if (numeric || mode === '123') {
        tap.current = null;
        setValue(v => (v.length < max ? v + key : v));
        return true;
      }

      const letters = MULTITAP[key];
      const now = Date.now();
      const last = tap.current;
      const again = last && last.key === key && now - last.at < 800;
      const index = again ? (last.index + 1) % letters.length : 0;
      const upper = mode === 'Abc';
      const ch = upper ? letters[index].toUpperCase() : letters[index];

      tap.current = { key, index, at: now };
      setValue(v => (again ? v.slice(0, -1) + ch : v.length < max ? v + ch : v));
      return true;
    },
    [numeric, allow, mode, max],
  );

  return { value, setValue, mode, handle, backspace };
}

/** The field as drawn: the text, a blinking caret, and the input mode in the corner. */
export function TextBox({ value, mode, label, prefix }: { value: string; mode?: string; label?: string; prefix?: string }) {
  return (
    <div className="textbox">
      {label && <div className="textbox-label">{label}</div>}
      <div className="textbox-field">
        {prefix}
        {value}
        <span className="caret" />
      </div>
      {mode && <div className="textbox-mode">{mode}</div>}
    </div>
  );
}

/** A yes/no question over the current screen. The screen's own key handler answers it. */
export function Confirm({ text, detail }: { text: string; detail?: string }) {
  return (
    <div className="confirm">
      <div className="confirm-card">
        <p className="confirm-text">{text}</p>
        {detail && <p className="confirm-detail">{detail}</p>}
      </div>
    </div>
  );
}

export const money = (n: number): string => `$${Math.round(n).toLocaleString('en-US')}`;

/** "now", "5m", "2h", "3d": how long ago a server timestamp was. */
export function ago(ts: number, now: number): string {
  const s = Math.max(0, now - ts);
  if (s < 60) return 'now';
  if (s < 3600) return `${Math.floor(s / 60)}m`;
  if (s < 86400) return `${Math.floor(s / 3600)}h`;
  return `${Math.floor(s / 86400)}d`;
}

/** "1:05" from seconds, or "2h 10m" for long waits. */
export function countdown(seconds: number): string {
  const s = Math.max(0, Math.floor(seconds));
  if (s >= 3600) return `${Math.floor(s / 3600)}h ${Math.floor((s % 3600) / 60)}m`;
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
}
