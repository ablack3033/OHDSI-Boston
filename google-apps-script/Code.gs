/**
 * Code.gs — signup endpoint for the OHDSI Boston site.
 *
 * THIS FILE IS NOT PART OF THE WEBSITE. It is deployment/reference code that
 * you paste into a Google Apps Script project bound to a Google Sheet, and
 * deploy as a web app. GitHub Pages never serves it.
 *
 * It exists because the site is static: it has no server of its own, and the
 * Sheet's credentials must not be in browser code. This script runs as *you*,
 * under Google's authentication, and is the only thing that can write to the
 * Sheet. The browser only ever sees its public /exec URL.
 *
 * Setup is in README.md in this directory.
 */

/* ----------------------------------------------------------------- config */

var CONFIG = {
  /* Tab within the bound spreadsheet. Created automatically if missing. */
  SHEET_NAME: 'signups',

  /* Only accept posts from these origins. This is a courtesy check, not a
     security boundary — Origin is trivially forged outside a browser. Leave
     the array empty to accept any origin. */
  ALLOWED_ORIGINS: [
    // 'https://your-org.github.io',
    // 'https://ohdsiboston.org'
  ],

  /* Reject a second signup from the same address. */
  DEDUPE: true,

  /* Crude flood guard: refuse if more than this many rows were written in the
     last minute, from any source. Protects the Sheet, not the mailing list. */
  MAX_WRITES_PER_MINUTE: 20,

  MAX_EMAIL_LENGTH: 254
};

/* ------------------------------------------------------------------ entry */

function doPost(e) {
  try {
    var body = parseBody_(e);
    if (!body) return json_({ ok: false, message: 'Malformed request.' });

    if (!originAllowed_(e)) return json_({ ok: false, message: 'Origin not allowed.' });

    var email = normaliseEmail_(body.email);
    if (!email) return json_({ ok: false, message: 'Please provide a valid email address.' });

    /* Server-side honeypot, in case the client one is bypassed. */
    if (body['organisation-website']) return json_({ ok: true, status: 'subscribed' });

    var lock = LockService.getScriptLock();
    if (!lock.tryLock(10000)) return json_({ ok: false, message: 'Busy, please retry.' });

    try {
      var sheet = getSheet_();

      if (rateLimited_(sheet)) return json_({ ok: false, message: 'Too many signups right now. Please try again shortly.' });

      if (CONFIG.DEDUPE && hasEmail_(sheet, email)) {
        return json_({ ok: true, status: 'already' });
      }

      sheet.appendRow([
        new Date(),
        email,
        String(body.source || '').slice(0, 64),
        String((e && e.parameter && e.parameter.ref) || '').slice(0, 128)
      ]);
      return json_({ ok: true, status: 'subscribed' });
    } finally {
      lock.releaseLock();
    }
  } catch (err) {
    console.error(err);
    return json_({ ok: false, message: 'Server error.' });
  }
}

/** A GET returns a health check, which makes the deployment easy to verify. */
function doGet() {
  return json_({ ok: true, service: 'ohdsi-boston-signup' });
}

/* ------------------------------------------------------------- internals */

function parseBody_(e) {
  if (!e) return null;
  /* The site posts JSON with a text/plain content type, so the browser treats
     it as a simple request and skips the CORS preflight that Apps Script does
     not answer. Form-encoded posts are accepted too. */
  if (e.postData && e.postData.contents) {
    try { return JSON.parse(e.postData.contents); } catch (ignore) { /* fall through */ }
  }
  if (e.parameter && e.parameter.email) return e.parameter;
  return null;
}

function originAllowed_(e) {
  if (!CONFIG.ALLOWED_ORIGINS.length) return true;
  var origin = (e && e.parameter && e.parameter.origin) || '';
  if (!origin) return true;   // Apps Script does not expose request headers
  return CONFIG.ALLOWED_ORIGINS.indexOf(origin) !== -1;
}

function normaliseEmail_(value) {
  if (typeof value !== 'string') return null;
  var email = value.trim().toLowerCase();
  if (!email || email.length > CONFIG.MAX_EMAIL_LENGTH) return null;
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email)) return null;
  return email;
}

function getSheet_() {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheet = ss.getSheetByName(CONFIG.SHEET_NAME);
  if (!sheet) {
    sheet = ss.insertSheet(CONFIG.SHEET_NAME);
    sheet.appendRow(['timestamp', 'email', 'source', 'ref']);
    sheet.setFrozenRows(1);
  }
  return sheet;
}

function hasEmail_(sheet, email) {
  var last = sheet.getLastRow();
  if (last < 2) return false;
  var values = sheet.getRange(2, 2, last - 1, 1).getValues();
  for (var i = 0; i < values.length; i++) {
    if (String(values[i][0]).trim().toLowerCase() === email) return true;
  }
  return false;
}

function rateLimited_(sheet) {
  var last = sheet.getLastRow();
  if (last < 2) return false;
  var n = Math.min(CONFIG.MAX_WRITES_PER_MINUTE, last - 1);
  var stamps = sheet.getRange(last - n + 1, 1, n, 1).getValues();
  if (stamps.length < CONFIG.MAX_WRITES_PER_MINUTE) return false;
  var oldest = new Date(stamps[0][0]).getTime();
  return (Date.now() - oldest) < 60 * 1000;
}

function json_(payload) {
  return ContentService
    .createTextOutput(JSON.stringify(payload))
    .setMimeType(ContentService.MimeType.JSON);
}
