import { useEffect, useRef } from 'react';
import { flashKey, usePhone } from '@/store/phone';
import { keyBeep } from './sound';

export type Key =
  | 'up' | 'down' | 'left' | 'right' | 'ok'
  | 'softL' | 'softR' | 'call' | 'end'
  | '0' | '1' | '2' | '3' | '4' | '5' | '6' | '7' | '8' | '9' | '*' | '#';

/** A screen's key handler. Only the screen on top of the stack has one mounted. */
type Handler = (key: Key) => void;

/** Receives typed characters while a text field is open. */
export interface TextSink {
  char: (ch: string) => void;
  backspace: () => void;
}

let handler: Handler | null = null;
let globalHandler: Handler | null = null;
let sink: TextSink | null = null;

/** Press a handset key, from the mouse or the keyboard. */
export function press(key: Key): void {
  flashKey(key);
  keyBeep(key);

  if (key === 'end') {
    globalHandler?.(key);
    return;
  }

  handler?.(key);
}

/** The one handler for keys no screen owns (the red key puts the phone away). */
export function setGlobalHandler(fn: Handler | null): void {
  globalHandler = fn;
}

/** Mount a key handler for the lifetime of a screen. */
export function useKeys(fn: Handler): void {
  const saved = useRef(fn);
  saved.current = fn;

  useEffect(() => {
    const mine: Handler = key => saved.current(key);
    handler = mine;
    return () => {
      if (handler === mine) handler = null;
    };
  }, []);
}

/** Route real keyboard typing into a text field while it is mounted. */
export function useTextSink(next: TextSink): void {
  const saved = useRef(next);
  saved.current = next;

  useEffect(() => {
    const mine: TextSink = {
      char: ch => saved.current.char(ch),
      backspace: () => saved.current.backspace(),
    };
    sink = mine;
    return () => {
      if (sink === mine) sink = null;
    };
  }, []);
}

const KEYBOARD: Record<string, Key> = {
  ArrowUp: 'up',
  ArrowDown: 'down',
  ArrowLeft: 'left',
  ArrowRight: 'right',
  Enter: 'ok',
  Backspace: 'softR',
  Escape: 'end',
  PageUp: 'softL',
  PageDown: 'softR',
};

/** Listen to the real keyboard while the handset is out. */
export function useKeyboard(): void {
  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if (!usePhone.getState().open) return;
      if (event.ctrlKey || event.altKey || event.metaKey) return;

      if (sink) {
        if (event.key === 'Backspace') {
          event.preventDefault();
          sink.backspace();
          return;
        }
        if (event.key.length === 1) {
          event.preventDefault();
          sink.char(event.key);
          return;
        }
      }

      const mapped = KEYBOARD[event.key] ?? (/^[0-9*#]$/.test(event.key) ? (event.key as Key) : null);
      if (!mapped) return;

      event.preventDefault();
      press(mapped);
    };

    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);
}

/** What multi-tap gives for each keypad key, in order. */
export const MULTITAP: Record<string, string> = {
  '1': '.,?!1',
  '2': 'abc2',
  '3': 'def3',
  '4': 'ghi4',
  '5': 'jkl5',
  '6': 'mno6',
  '7': 'pqrs7',
  '8': 'tuv8',
  '9': 'wxyz9',
  '0': ' 0',
};

/** The small letters printed under each keypad digit. */
export const KEY_LETTERS: Record<string, string> = {
  '1': '.,?',
  '2': 'abc',
  '3': 'def',
  '4': 'ghi',
  '5': 'jkl',
  '6': 'mno',
  '7': 'pqrs',
  '8': 'tuv',
  '9': 'wxyz',
  '0': '+',
  '*': '',
  '#': '',
};
