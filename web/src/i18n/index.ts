import { useEffect, useState } from 'react';
import en from '../../../locales/en.json';

type Dict = { [k: string]: string | Dict };

const EN = en as unknown as Dict;
const clone = (d: Dict): Dict => JSON.parse(JSON.stringify(d));

let active: Dict = EN;
const listeners = new Set<() => void>();

const resolve = (dict: Dict, path: string): string | Dict | undefined =>
  path.split('.').reduce<string | Dict | undefined>(
    (o, k) => (o && typeof o === 'object' ? (o as Dict)[k] : undefined),
    dict,
  );

const format = (str: string, args: unknown[]): string => {
  let i = 0;
  return str.replace(/%[sd%]/g, m => (m === '%%' ? '%' : String(args[i++] ?? '')));
};

export function t(path: string, ...args: unknown[]): string {
  const v = resolve(active, path);
  const s = typeof v === 'string' ? v : path;
  return args.length ? format(s, args) : s;
}

const deepMerge = (base: Dict, over: Dict): Dict => {
  for (const k of Object.keys(over)) {
    const ov = over[k];
    const bv = base[k];
    if (ov && typeof ov === 'object' && bv && typeof bv === 'object') deepMerge(bv as Dict, ov as Dict);
    else base[k] = ov;
  }
  return base;
};

export function setLocale(strings?: Record<string, unknown> | null): void {
  active = strings && typeof strings === 'object' ? deepMerge(clone(EN), strings as Dict) : EN;
  listeners.forEach(fn => fn());
}

export function useI18n(): typeof t {
  const [, force] = useState(0);
  useEffect(() => {
    const fn = () => force(n => n + 1);
    listeners.add(fn);
    return () => { listeners.delete(fn); };
  }, []);
  return t;
}
