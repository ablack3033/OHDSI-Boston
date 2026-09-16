/**
 * signup.js — the "Join OHDSI Boston" form.
 *
 * Architecture note: this site is static. There is no server of ours. The form
 * POSTs to a Google Apps Script web app (see ../../google-apps-script/), which
 * is the only thing holding credentials for the Sheet. Nothing secret can live
 * in this file, and nothing secret does.
 *
 * The request is deliberately sent as `text/plain` so the browser treats it as
 * a simple request and skips the CORS preflight, which Apps Script does not
 * answer. The body is still JSON; the Apps Script parses it from postData.
 *
 * Anti-abuse here is best-effort and client-side only: a honeypot field, a
 * minimum fill time and a local duplicate check. All three run on the
 * visitor's own machine, so all three are trivially bypassed by anyone who
 * wants to. Real protection has to live in the Apps Script. This is
 * documented, not pretended away.
 *
 * One rule shapes the order of the checks below: never fake a success. A guard
 * that silently swallows a legitimate address is worse than a bot getting
 * through, because the person walks away believing they signed up.
 */

import { CONFIG } from './config.js';

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

const MESSAGES = {
  empty:      'Please enter an email address.',
  invalid:    'That does not look like an email address.',
  offline:    'Signup is not configured yet. ',
  network:    'We could not reach the signup service. Please try again.',
  server:     'Something went wrong at our end. Please try again in a moment.',
  success:    'Thank you — you are on the list. We will be in touch before the first meeting.',
  already:    'You are already on the list. Nothing more to do.',
  duplicate:  'You have already signed up from this browser.'
};

/**
 * Attach signup behaviour to a form.
 * @param {HTMLFormElement} form must contain input[type=email][name=email],
 *        a honeypot input, a submit button and an element [data-signup-status].
 */
export function attachSignup(form) {
  if (!form) return null;

  const input  = form.querySelector('input[type="email"]');
  const button = form.querySelector('button[type="submit"]');
  const status = form.querySelector('[data-signup-status]');
  const honey  = form.querySelector(`input[name="${CONFIG.signup.honeypotField}"]`);
  const openedAt = Date.now();

  let state = 'idle';

  const setState = (next, message) => {
    state = next;
    form.dataset.state = next;
    button.disabled = next === 'submitting' || next === 'success' || next === 'already';
    if (next === 'submitting') button.setAttribute('aria-busy', 'true');
    else button.removeAttribute('aria-busy');
    /* The status element keeps role="status" for its whole life. Swapping
       roles at runtime is unreliable across screen readers, and a polite
       announcement is right for every state here. */
    if (status) status.textContent = message || '';
    input.setAttribute('aria-invalid', next === 'invalid' ? 'true' : 'false');
  };

  /* `submitting` and the terminal states disable the button, so a second
     click cannot fire a duplicate request. */
  const alreadyLocally = () => {
    try {
      return localStorage.getItem(CONFIG.signup.storageKey) === 'true';
    } catch { return false; }
  };
  const rememberLocally = () => {
    try { localStorage.setItem(CONFIG.signup.storageKey, 'true'); } catch { /* private mode */ }
  };

  if (alreadyLocally()) setState('already', MESSAGES.duplicate);
  else setState('idle', '');

  input.addEventListener('input', () => {
    if (state === 'invalid' || state === 'error') setState('idle', '');
  });

  form.addEventListener('submit', async (event) => {
    event.preventDefault();
    if (state === 'submitting' || state === 'success') return;

    /* Honeypot first: a real person never fills a field they cannot see, so
       this is the one signal we trust enough to drop the submission on. Fail
       silently, so a bot learns nothing from the response. */
    if (honey && honey.value.trim() !== '') {
      setState('success', MESSAGES.success);
      return;
    }

    /* Validation comes BEFORE any anti-abuse timing, so a real person always
       gets real feedback about their own input. */
    const email = input.value.trim();
    if (!email) { setState('invalid', MESSAGES.empty); input.focus(); return; }
    if (!EMAIL_RE.test(email)) { setState('invalid', MESSAGES.invalid); input.focus(); return; }

    if (!CONFIG.signup.endpoint) {
      const mail = CONFIG.links.contactEmail;
      setState('error', MESSAGES.offline + (mail ? `Please email ${mail}.` : 'Please check back shortly.'));
      return;
    }

    setState('submitting', 'Sending…');

    /* A submission faster than a human could manage is throttled, not thrown
       away. Discarding it would silently lose the address of anyone who
       pastes and hits Join quickly — a far worse failure than letting a
       hurried bot through a second later. */
    const elapsed = (Date.now() - openedAt) / 1000;
    if (elapsed < CONFIG.signup.minFillSeconds) {
      await new Promise((r) => setTimeout(r, (CONFIG.signup.minFillSeconds - elapsed) * 1000));
    }

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), CONFIG.signup.timeoutMs);

    try {
      const response = await fetch(CONFIG.signup.endpoint, {
        method: 'POST',
        /* text/plain keeps this a "simple request": no preflight for Apps
           Script to fail to answer. The body is still JSON. */
        headers: { 'Content-Type': 'text/plain;charset=utf-8' },
        body: JSON.stringify({ email, source: CONFIG.signup.source }),
        signal: controller.signal,
        redirect: 'follow'
      });
      clearTimeout(timer);

      if (!response.ok) { setState('error', MESSAGES.server); return; }

      let payload = {};
      try { payload = JSON.parse(await response.text()); } catch { /* fall through */ }

      if (payload.status === 'already') {
        rememberLocally();
        setState('already', MESSAGES.already);
      } else if (payload.ok) {
        rememberLocally();
        setState('success', MESSAGES.success);
      } else {
        setState('error', payload.message || MESSAGES.server);
      }
    } catch (error) {
      clearTimeout(timer);
      setState('error', MESSAGES.network);
    }
  });

  return { get state() { return state; } };
}
