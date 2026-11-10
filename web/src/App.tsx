import { useEffect, useMemo, useRef } from 'react';
import Handset, { HandsetBack } from '@/device/Handset';
import Display from '@/device/Display';
import { setGlobalHandler, useKeyboard } from '@/device/keys';
import { playAlert } from '@/device/sound';
import { useNuiEvent } from '@/hooks/useNuiEvent';
import { fetchNui, isEnvBrowser } from '@/nui/bridge';
import { MOCK_SETUP, MOCK_STATE } from '@/nui/mock';
import { setLocale } from '@/i18n';
import {
  closePhone, goHome, openPhone, patchState, push, receiveMessage, receiveOffer, setClock, showPeek, showToast, usePhone,
} from '@/store/phone';
import type { Clock, MessagePayload, OfferPayload, PhoneState, Setup } from '@/store/types';

/** The website's browser demo (`vite build --mode demo`): the handset alone, on sample data. */
const DEMO = import.meta.env.MODE === 'demo';

/** Fit the handset to the screen: it takes about seven tenths of the screen height at any resolution. */
function useStageScale(): void {
  useEffect(() => {
    const fit = () => {
      // In game the handset takes about seven tenths of the screen height. In the demo it is
      // the whole page, so it fills whatever frame it is given.
      const scale = DEMO
        ? Math.min(window.innerHeight / 740, window.innerWidth / 330)
        : Math.min(1.5, window.innerHeight / 1000);
      document.documentElement.style.setProperty('--s', String(scale));
    };
    fit();
    window.addEventListener('resize', fit);
    return () => window.removeEventListener('resize', fit);
  }, []);
}

export default function App() {
  const open = usePhone(s => s.open);
  const peek = usePhone(s => s.peek);
  const shell = usePhone(s => s.state?.phone.shell ?? 'graphite');
  const peekTimer = useRef(0);
  const capture = useMemo(() => {
    if (!isEnvBrowser()) return null;

    // #shot=<colour>:<screen>[:<argument>] is the same flat handset on any screen, with the
    // sample data left in, for the pictures in the README.
    const shot = /^#shot=(\w+):(\w+)(?::([\w-]+))?$/.exec(window.location.hash);
    if (shot) return { back: false, shell: shot[1], screen: shot[2], arg: shot[3] };

    const m = /^#prop(back)?=(\w+)$/.exec(window.location.hash);
    return m ? { back: Boolean(m[1]), shell: m[2] } : null;
  }, []);

  useStageScale();
  useKeyboard();

  useNuiEvent<{ state: PhoneState; setup: Setup; clock: Clock }>('trap:open', d => openPhone(d.state, d.setup, d.clock));
  useNuiEvent('trap:close', () => closePhone());
  useNuiEvent<Partial<PhoneState>>('trap:state', patch => patchState(patch));
  useNuiEvent<Clock>('trap:clock', clock => setClock(clock));
  useNuiEvent<OfferPayload>('trap:offer', payload => receiveOffer(payload));
  useNuiEvent<{ text: string; tone?: 'info' | 'good' | 'bad' }>('trap:toast', d => showToast(d.text, d.tone ?? 'info'));

  useNuiEvent<MessagePayload>('trap:message', payload => {
    receiveMessage(payload);
    if (payload.silent) return;

    playAlert();

    // Before the phone has been opened this session there is no setup yet: still show the
    // preview, with the default timing. The message itself comes with the state on open.
    const { open: isOpen, setup } = usePhone.getState();
    if (isOpen) {
      showToast(`${payload.name}: ${payload.msg.text}`);
    } else if (setup?.peek ?? true) {
      showPeek(payload);
      window.clearTimeout(peekTimer.current);
      peekTimer.current = window.setTimeout(() => showPeek(null), (setup?.peekSeconds ?? 5) * 1000);
    }
  });

  useEffect(() => {
    void fetchNui<{ strings: Record<string, unknown> }>('trap:ui:locale').then(r => {
      if (r?.strings) setLocale(r.strings);
    });

    // The red key: from any screen it goes back to the clock, and from the clock it puts the phone away.
    setGlobalHandler(() => {
      if (usePhone.getState().stack.length > 1 || DEMO) {
        goHome();
        return;
      }
      closePhone();
      void fetchNui('trap:close');
    });

    return () => setGlobalHandler(null);
  }, []);

  useEffect(() => {
    if (!isEnvBrowser()) return;

    // tools/build_prop.py captures the handset from here: #prop=<colour> is the face,
    // #propback=<colour> the back, both flat, at rest and with nothing animating.
    if (capture?.screen) {
      openPhone({ ...MOCK_STATE, phone: { ...MOCK_STATE.phone, shell: capture.shell } }, MOCK_SETUP, { h: 21, m: 47 });
      usePhone.setState({ booted: true });
      if (capture.screen !== 'idle') push(capture.screen, capture.arg ? { number: capture.arg } : undefined);
      return;
    }

    if (capture) {
      openPhone(
        { ...MOCK_STATE, phone: { ...MOCK_STATE.phone, shell: capture.shell }, threads: [], hustle: { ...MOCK_STATE.hustle!, mode: 'idle' } },
        MOCK_SETUP,
        { h: 4, m: 20 },
      );
      usePhone.setState({ booted: true });
      return;
    }

    // The website's demo: the handset alone in the middle of a clear page, idle, in the colour
    // the address asks for. The page around it can change the colour by posting a message.
    if (DEMO) {
      const wanted = new URLSearchParams(window.location.search).get('shell') ?? 'graphite';
      const fresh = (shell: string) => ({
        ...MOCK_STATE,
        phone: { ...MOCK_STATE.phone, shell },
        hustle: { ...MOCK_STATE.hustle!, mode: 'idle' as const },
      });

      openPhone(fresh(wanted), MOCK_SETUP, { h: 21, m: 47 });

      const onMessage = (event: MessageEvent) => {
        const data = event.data as { type?: string; shell?: string } | null;
        const current = usePhone.getState().state;
        if (event.origin !== window.location.origin || data?.type !== 'trap:shell' || !current) return;
        if (typeof data.shell === 'string' && /^[a-z]+$/.test(data.shell)) {
          patchState({ phone: { ...current.phone, shell: data.shell } });
        }
      };

      window.addEventListener('message', onMessage);
      return () => window.removeEventListener('message', onMessage);
    }

    // Working on the page in a browser: a game-ish backdrop and the mock phone, already open.
    document.body.style.background = 'linear-gradient(160deg, #3b4a5c, #1b2028)';
    openPhone(MOCK_STATE, MOCK_SETUP, { h: 21, m: 47 });
  }, [capture]);

  if (capture) {
    return (
      <div className={`stage stage-capture shell-${capture.shell}${capture.screen ? '' : ' stage-flat'}`}>
        {capture.back ? <HandsetBack shell={capture.shell} /> : <Handset shell={capture.shell}><Display /></Handset>}
      </div>
    );
  }

  return (
    <div className={`stage${DEMO ? ' stage-demo' : ''}${open ? ' stage-open' : peek ? ' stage-peek' : ''}`}>
      <Handset shell={shell}>
        <Display />
      </Handset>
    </div>
  );
}
