import type { ReactNode } from 'react';
import { KEY_LETTERS, press, type Key } from './keys';
import { usePhone } from '@/store/phone';

const DIGITS: Key[] = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '*', '0', '#'];

function KeyButton({ k, className, label, children }: { k: Key; className: string; label: string; children?: ReactNode }) {
  const down = usePhone(s => s.pressed === k);

  return (
    <button
      type="button"
      aria-label={label}
      className={`${className}${down ? ' key-down' : ''}`}
      // Keep keyboard focus off the plastic: a focused button would swallow Enter and Space.
      onMouseDown={e => e.preventDefault()}
      onClick={() => press(k)}
    >
      {children}
    </button>
  );
}

const Arrow = ({ turn }: { turn: number }) => (
  <svg width="12" height="9" viewBox="0 0 12 9" style={{ transform: `rotate(${turn}deg)` }} aria-hidden="true">
    <path d="M6 0 12 9H0z" fill="currentColor" />
  </svg>
);

const Receiver = ({ down }: { down?: boolean }) => (
  <svg width="22" height="12" viewBox="0 0 22 12" style={down ? { transform: 'rotate(135deg)' } : undefined} aria-hidden="true">
    <path d="M1 9c0-9 20-9 20 0v2h-6V8c-2-1-6-1-8 0v3H1z" fill="currentColor" />
  </svg>
);

/** The plastic: faceplate, lens, d-pad and keypad. The display is passed in as children. */
export default function Handset({ shell, children }: { shell: string; children: ReactNode }) {
  return (
    <div className={`handset shell-${shell}`}>
      <div className="hs-body">
        <div className="hs-ear" />

        <div className="hs-lens">
          <div className="hs-brand">KOLT</div>
          <div className="hs-screen">{children}</div>
          <div className="hs-model">T9 TRAPLINE</div>
        </div>

        <div className="hs-nav">
          <KeyButton k="softL" className="key key-soft" label="Left soft key" />
          <div className="dpad">
            <KeyButton k="up" className="dpad-dir dpad-up" label="Up"><Arrow turn={0} /></KeyButton>
            <KeyButton k="down" className="dpad-dir dpad-down" label="Down"><Arrow turn={180} /></KeyButton>
            <KeyButton k="left" className="dpad-dir dpad-left" label="Left"><Arrow turn={270} /></KeyButton>
            <KeyButton k="right" className="dpad-dir dpad-right" label="Right"><Arrow turn={90} /></KeyButton>
            <KeyButton k="ok" className="key dpad-ok" label="Select">OK</KeyButton>
          </div>
          <KeyButton k="softR" className="key key-soft key-soft-r" label="Right soft key" />
          <KeyButton k="call" className="key key-call" label="Call"><Receiver /></KeyButton>
          <KeyButton k="end" className="key key-end" label="End"><Receiver down /></KeyButton>
        </div>

        <div className="hs-pad">
          {DIGITS.map(d => (
            <KeyButton key={d} k={d} className="key key-digit" label={d}>
              <span className="key-num">{d}</span>
              <span className="key-abc">{KEY_LETTERS[d]}</span>
            </KeyButton>
          ))}
        </div>

        <div className="hs-mic" />
      </div>
    </div>
  );
}

/** The back of the handset. Never shown in game: it is captured once per colour for the prop's texture. */
export function HandsetBack({ shell }: { shell: string }) {
  return (
    <div className={`handset handset-back shell-${shell}`}>
      <div className="hs-body">
        <div className="hs-back-cam" />
        <div className="hs-back-mirror" />
        <div className="hs-back-speaker" />
        <div className="hs-back-door" />
        <div className="hs-back-latch" />
        <div className="hs-back-logo">KOLT</div>
        <div className="hs-back-small">T9 TRAPLINE</div>
      </div>
    </div>
  );
}
