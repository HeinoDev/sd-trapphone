import { usePhone } from '@/store/phone';

// Everything the handset plays is synthesised: one square-wave voice, like a phone of its
// time. No audio files ship with the resource.

let ctx: AudioContext | null = null;

function audio(): AudioContext | null {
  try {
    ctx ??= new AudioContext();
    if (ctx.state === 'suspended') void ctx.resume();
    return ctx;
  } catch {
    return null;
  }
}

const volume = (): number => usePhone.getState().state?.settings.volume ?? 0.5;

function tone(freq: number, startAt: number, ms: number, gain: number): void {
  const ac = audio();
  if (!ac || freq <= 0 || gain <= 0) return;

  const osc = ac.createOscillator();
  const amp = ac.createGain();
  const t0 = ac.currentTime + startAt / 1000;
  const t1 = t0 + ms / 1000;

  osc.type = 'square';
  osc.frequency.value = freq;
  amp.gain.setValueAtTime(0, t0);
  amp.gain.linearRampToValueAtTime(gain, t0 + 0.004);
  amp.gain.setValueAtTime(gain, Math.max(t0 + 0.004, t1 - 0.012));
  amp.gain.linearRampToValueAtTime(0, t1);
  osc.connect(amp).connect(ac.destination);
  osc.start(t0);
  osc.stop(t1 + 0.02);
}

// Each digit gets its own pitch, so dialling sounds like dialling.
const KEY_PITCH: Record<string, number> = {
  '1': 1209, '2': 1336, '3': 1477, '4': 1209, '5': 1336, '6': 1477,
  '7': 1209, '8': 1336, '9': 1477, '*': 1209, '0': 1336, '#': 1477,
};

export function keyBeep(key: string): void {
  tone(KEY_PITCH[key] ?? 1640, 0, 34, 0.035 * volume());
}

const N: Record<string, number> = {
  C4: 261.6, D4: 293.7, E4: 329.6, F4: 349.2, G4: 392.0, A4: 440.0, B4: 493.9,
  C5: 523.3, D5: 587.3, E5: 659.3, F5: 698.5, G5: 784.0, A5: 880.0, B5: 987.8,
  C6: 1046.5, D6: 1174.7, E6: 1318.5, R: 0,
};

type Step = [note: keyof typeof N, ms: number];

/** ids match config.Phone.Ringtones. */
export const RINGTONES: Record<string, Step[]> = {
  trapline: [['E5', 110], ['R', 30], ['E5', 110], ['G5', 110], ['R', 30], ['A5', 160], ['G5', 110], ['E5', 220]],
  pager: [['B5', 90], ['R', 60], ['B5', 90], ['R', 60], ['B5', 90], ['R', 220], ['B5', 90], ['R', 60], ['B5', 90]],
  ascend: [['C5', 90], ['E5', 90], ['G5', 90], ['C6', 90], ['E6', 200]],
  lowrider: [['G4', 160], ['B4', 110], ['D5', 110], ['G4', 160], ['R', 40], ['D5', 110], ['B4', 220]],
  silent: [],
};

export function playRingtone(id: string | undefined, scale = 1): void {
  const steps = RINGTONES[id ?? ''] ?? RINGTONES.trapline;
  let at = 0;

  for (const [note, ms] of steps) {
    tone(N[note], at, ms, 0.06 * volume() * scale);
    at += ms;
  }
}

export function playAlert(): void {
  playRingtone(usePhone.getState().state?.settings.ringtone);
}

export function playGood(): void {
  tone(N.G5, 0, 70, 0.05 * volume());
  tone(N.C6, 80, 120, 0.05 * volume());
}

export function playBad(): void {
  tone(N.E4, 0, 110, 0.05 * volume());
  tone(N.C4, 120, 180, 0.05 * volume());
}
