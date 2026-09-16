/**
 * main.js — wiring only.
 *
 * Everything with behaviour lives in its own module; this file connects them
 * and does nothing clever. In particular it is the ONLY place where the
 * scroll director and the scene graph meet, and they meet through a single
 * number (`progress`).
 */

import { CONFIG, prefersReducedMotion } from './config.js';
import { SCENES } from './story.js';
import { createSceneGraph } from './scene-graph.js';
import { createScrollDirector } from './scroll-director.js';
import { attachSignup } from './signup.js';

document.documentElement.classList.remove('no-js');
document.documentElement.classList.add('js');

/* ------------------------------------------------------------------ links */

function applyLinks() {
  document.querySelectorAll('[data-link]').forEach((node) => {
    const url = CONFIG.links[node.dataset.link];
    if (url) {
      node.setAttribute('href', url);
      if (/^https?:/i.test(url) && !url.startsWith(location.origin)) {
        node.setAttribute('rel', 'noopener');
      }
    } else {
      /* Unconfigured links become inert rather than broken. */
      node.removeAttribute('href');
      node.setAttribute('aria-disabled', 'true');
      node.classList.add('is-unconfigured');
      if (!node.querySelector('.sr-only')) {
        const note = document.createElement('span');
        note.className = 'sr-only';
        note.textContent = ' (link coming soon)';
        node.appendChild(note);
      }
    }
  });
}

/* ------------------------------------------------------------------ story */

function initStory() {
  const section = document.querySelector('[data-story]');
  if (!section) return;

  const svg = section.querySelector('[data-story-svg]');
  const track = section.querySelector('[data-story-steps]');
  const steps = Array.from(section.querySelectorAll('[data-scene]'));
  if (!svg || !track || steps.length === 0) return;

  /* The DOM and story.js must agree on scene order; say so loudly if not. */
  const domIds = steps.map((s) => s.dataset.scene);
  const jsIds = SCENES.map((s) => s.id);
  if (domIds.join('|') !== jsIds.join('|')) {
    console.warn('[ohdsi-boston] scene mismatch.\n  index.html:', domIds, '\n  story.js:  ', jsIds);
  }

  const narrow = window.matchMedia(`(max-width: ${CONFIG.story.narrowBreakpoint}px)`).matches;
  const viz = createSceneGraph(svg, {
    cast: narrow ? CONFIG.story.castNarrow : CONFIG.story.cast,
    hold: CONFIG.story.hold,
    reducedMotion: prefersReducedMotion()
  });

  const counter = section.querySelector('[data-story-counter]');
  const progressBar = section.querySelector('[data-story-progress]');

  const director = createScrollDirector({
    track,
    steps,
    sceneCount: SCENES.length,
    smoothing: CONFIG.story.smoothing,
    reducedMotion: prefersReducedMotion(),
    onProgress(p) {
      viz.render(p);
      if (progressBar) {
        progressBar.style.setProperty('--story-progress', (p / (SCENES.length - 1)).toFixed(4));
      }
    },
    onScene(i) {
      steps.forEach((step, k) => step.classList.toggle('is-active', k === i));
      if (counter) {
        counter.textContent = `${String(i + 1).padStart(2, '0')} / ${String(SCENES.length).padStart(2, '0')}`;
      }
      section.dataset.activeScene = SCENES[i] ? SCENES[i].id : '';
    }
  });

  director.start();

  /* Honour a change of the OS setting without a reload. */
  const motionQuery = window.matchMedia('(prefers-reduced-motion: reduce)');
  const onMotionChange = () => {
    viz.setReducedMotion(motionQuery.matches);
    director.setReducedMotion(motionQuery.matches);
  };
  if (motionQuery.addEventListener) motionQuery.addEventListener('change', onMotionChange);

  return { viz, director };
}

/* ------------------------------------------------------------- reveal-ins */

function initReveals() {
  const targets = document.querySelectorAll('[data-reveal]');
  if (!targets.length) return;
  if (prefersReducedMotion()) {
    targets.forEach((t) => t.classList.add('is-revealed'));
    return;
  }
  const io = new IntersectionObserver((entries) => {
    for (const e of entries) {
      if (e.isIntersecting) { e.target.classList.add('is-revealed'); io.unobserve(e.target); }
    }
  }, { rootMargin: '0px 0px -12% 0px', threshold: 0.12 });
  targets.forEach((t) => io.observe(t));
}

/* ------------------------------------------------------------------- boot */

applyLinks();
document.querySelectorAll('form[data-signup]').forEach(attachSignup);
initStory();
initReveals();

const year = document.querySelector('[data-year]');
if (year) year.textContent = String(new Date().getFullYear());
