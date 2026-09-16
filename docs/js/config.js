/**
 * config.js — the one place to edit URLs and endpoints.
 *
 * Nothing secret belongs in this file. It ships to every visitor's browser.
 * The signup endpoint below is a public Google Apps Script web-app URL; the
 * Sheet credentials live inside the Apps Script deployment, never here.
 * See ../../google-apps-script/README.md.
 */

export const CONFIG = {
  /* ---------------------------------------------------------------- links */
  /* TODO: replace the empty strings with real URLs.
     Any link left empty renders as a disabled placeholder rather than a
     broken link, so the site is safe to deploy before these are decided. */
  links: {
    ohdsi:        'https://ohdsi.org',
    ohdsiForums:  'https://forums.ohdsi.org',
    github:       '',   // e.g. https://github.com/<org>/<repo>
    runAStudy:    '',   // "Help us run a study"
    proposeQuestion: '', // "Propose a question"
    calendar:     '',   // optional: meetup / calendar link
    contactEmail: ''    // optional: shown as a fallback if signup fails
  },

  /* --------------------------------------------------------------- signup */
  signup: {
    /* Apps Script web-app URL, ending in /exec. Empty = form is disabled and
       says so, instead of silently dropping addresses. */
    endpoint: '',

    /* Sent along with the address so one Sheet can serve several forms. */
    source: 'ohdsi-boston-web',

    /* Anti-abuse. These are usability guards, not security — see README. */
    honeypotField: 'organisation-website',
    minFillSeconds: 2,        // faster submissions are delayed, never dropped
    storageKey: 'ohdsi-boston:subscribed',
    timeoutMs: 15000
  },

  /* ---------------------------------------------------------- story tuning */
  story: {
    /* Fraction of each step's scroll distance spent holding the scene
       (split between its start and end); the rest is the transition. */
    hold: 0.34,
    /* Exponential smoothing applied to scroll progress. 0 = no smoothing. */
    smoothing: 0.16,
    /* Cast sizes. The narrow variant is used below `narrowBreakpoint`. */
    cast:       { people: 14, quanta: 9, sites: 8, archive: 30 },
    castNarrow: { people: 10, quanta: 9, sites: 6, archive: 18 },
    narrowBreakpoint: 700
  }
};

/** True when the visitor has asked the OS for reduced motion. */
export const prefersReducedMotion = () =>
  window.matchMedia('(prefers-reduced-motion: reduce)').matches;
