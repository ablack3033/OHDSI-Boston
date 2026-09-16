# Signup endpoint (Google Apps Script)

**This directory is not part of the website.** GitHub Pages serves `docs/` only.
The code here is deployed to Google, not to Pages.

## Why it exists

The site is static. It has no server of ours, and a Google Sheet cannot be
written to from browser JavaScript without credentials — which must never ship
to a browser. So the browser posts to a Google Apps Script web app, which runs
under *your* Google account and is the only thing that can touch the Sheet.

```
browser  ──POST──▶  Apps Script /exec  ──▶  Google Sheet
(no secrets)        (runs as you)           (private)
```

## Setup

1. **Create the Sheet.** A new Google Sheet; name it whatever you like. The
   script creates a `signups` tab with headers on first write.

2. **Open the script editor.** In the Sheet: *Extensions → Apps Script*. Using
   a *bound* script (opened from the Sheet) means `getActiveSpreadsheet()`
   resolves without hard-coding an ID.

3. **Paste `Code.gs`** over the contents of `Code.gs` in the editor. Save.

4. **Optional hardening.** In the `CONFIG` block at the top, add your published
   origin to `ALLOWED_ORIGINS`. Read the caveat in the code first: Apps Script
   does not expose request headers, so this only ever sees an origin the client
   chose to send. It is a courtesy check.

5. **Deploy.** *Deploy → New deployment → Web app*:
   - **Execute as:** Me
   - **Who has access:** Anyone
   Both are required. "Anyone" governs who may call the URL, not who may read
   the Sheet — the Sheet stays private.

6. **Authorise** when prompted. The warning screen is expected for a personal
   script: *Advanced → Go to (project) → Allow*.

7. **Copy the `/exec` URL** into `docs/js/config.js`:

   ```js
   signup: { endpoint: 'https://script.google.com/macros/s/AKfy…/exec', … }
   ```

8. **Verify.** Open the `/exec` URL in a browser. You should see
   `{"ok":true,"service":"ohdsi-boston-signup"}`. Then submit the real form and
   check the Sheet.

**Redeploy after every edit.** Apps Script serves the last *deployed* version,
not the last saved one. Use *Deploy → Manage deployments → edit → New version*
to keep the same URL; a brand new deployment issues a new URL and silently
breaks the form.

## Responses

The script always replies with JSON:

| Response | Meaning | What the form shows |
| --- | --- | --- |
| `{"ok":true,"status":"subscribed"}` | Row appended | Success |
| `{"ok":true,"status":"already"}` | Address already present | "Already on the list" |
| `{"ok":false,"message":"…"}` | Rejected | The message, with retry |

## What this architecture does and does not protect

**Does:** keeps Sheet credentials off the client entirely; dedupes addresses;
serialises writes with a lock; caps the write rate; validates and normalises
the address server-side; repeats the honeypot check server-side.

**Does not:** stop a determined abuser. The endpoint is public by necessity —
anyone who views the site can read the URL out of `config.js` and post to it
directly with `curl`. The honeypot, the minimum fill time and the duplicate
check in `docs/js/signup.js` are usability guards that stop naive bots; they
are not a security boundary, because every one of them runs on the attacker's
machine.

If the endpoint is abused, the options that actually work are:

- add a CAPTCHA (Cloudflare Turnstile or reCAPTCHA) and verify the token inside
  this script with `UrlFetchApp` — the verification secret stays in
  [Script Properties](https://developers.google.com/apps-script/guides/properties),
  never in the browser;
- tighten `MAX_WRITES_PER_MINUTE`;
- send signups to a holding tab and confirm by email before adding anyone to
  the real list;
- or move to a hosted form provider, accepting the loss of control that implies.

Do not attempt to fix abuse by putting a "secret" key in `config.js`. Anything
the browser can send, an attacker can read and replay.

## Privacy

The script stores a timestamp, the address, and which form it came from. It does
not log IP addresses or user agents — Apps Script does not expose them, and we
would not want them. Deleting a row is the whole unsubscribe mechanism; make
sure whoever runs the list knows that.
