import { fetchNui, isEnvBrowser } from './bridge';
import { mockReply } from './mock';
import { showToast } from '@/store/phone';
import { playBad, playGood } from '@/device/sound';
import { t } from '@/i18n';
import type { Reply } from '@/store/types';

/** Ask Lua for something. In a plain browser the mock answers, so the page can be worked on alone. */
export async function call<T = unknown>(name: string, body?: unknown): Promise<Reply<T>> {
  if (isEnvBrowser()) return mockReply(name, body) as Reply<T>;

  const reply = await fetchNui<Reply<T>>(name, body);

  return reply ?? { ok: false, error: t('ui.no_answer') };
}

/** Ask, then say how it went on the screen: the error when it failed, `done` when it worked. */
export async function act<T = unknown>(name: string, body?: unknown, done?: string): Promise<Reply<T>> {
  const reply = await call<T>(name, body);

  if (!reply.ok) {
    playBad();
    showToast(reply.error ?? t('ui.failed'), 'bad');
  } else if (done) {
    playGood();
    showToast(done, 'good');
  }

  return reply;
}
