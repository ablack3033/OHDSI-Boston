/**
 * scroll-director.js — turns scroll position into story progress.
 *
 * This is the only module that reads the scroll position, and it does so once
 * per animation frame rather than on every scroll event. It converts the
 * geometry of the step column into a single continuous number:
 *
 *     progress ∈ [0, sceneCount - 1]
 *
 * where an integer means "scene N is centred" and the fraction between two
 * integers is the transition. Everything downstream — the SVG, the active-step
 * highlight, the progress readout — consumes that one number, so the narrative
 * text and the diagram stay completely decoupled.
 *
 *     const director = createScrollDirector({ track, steps, sceneCount, ... });
 *     director.start();  director.stop();  director.progress();
 */

const clamp = (v, lo, hi) => (v < lo ? lo : v > hi ? hi : v);

export function createScrollDirector(options) {
  const {
    track,                    // the element containing the step sections
    steps,                    // NodeList/array of step elements
    sceneCount,
    onProgress = () => {},
    onScene = () => {},
    smoothing = 0.16
  } = options;

  let reducedMotion = !!options.reducedMotion;
  let raf = 0;
  let running = false;
  let visible = false;
  let target = 0;
  let shown = 0;
  let activeScene = -1;
  let metrics = { top: 0, step: 1 };

  function measure() {
    const rect = track.getBoundingClientRect();
    metrics.top = rect.top + window.scrollY;
    metrics.step = Math.max(1, track.offsetHeight / sceneCount);
  }

  function computeTarget() {
    /* A scene is "centred" when the middle of the viewport reaches the middle
       of its step, which is what makes the diagram feel attached to the text. */
    const centre = window.scrollY + window.innerHeight / 2;
    const p = (centre - metrics.top) / metrics.step - 0.5;
    return clamp(p, 0, sceneCount - 1);
  }

  function emit(p) {
    onProgress(p);
    const scene = Math.round(p);
    if (scene !== activeScene) {
      activeScene = scene;
      onScene(scene);
    }
  }

  function frame() {
    if (!running) return;
    target = computeTarget();
    /* Critically damped-ish easing: snappy when scrolling, still when idle. */
    shown += (target - shown) * (smoothing || 1);
    if (Math.abs(target - shown) < 0.0004) shown = target;
    emit(shown);
    raf = requestAnimationFrame(frame);
  }

  /* Reduced motion: no tweening and no animation loop. The active step is
     observed directly and the diagram snaps to that scene. */
  const stepObserver = new IntersectionObserver((entries) => {
    if (!reducedMotion) return;
    let best = null;
    for (const e of entries) if (e.isIntersecting && (!best || e.intersectionRatio > best.intersectionRatio)) best = e;
    if (!best) return;
    const i = steps.indexOf ? steps.indexOf(best.target) : Array.prototype.indexOf.call(steps, best.target);
    if (i >= 0) { shown = target = i; emit(i); }
  }, { threshold: [0.5], rootMargin: '-25% 0px -25% 0px' });

  /* Only animate while the story is actually on screen. */
  const sectionObserver = new IntersectionObserver((entries) => {
    visible = entries.some((e) => e.isIntersecting);
    if (visible && !reducedMotion) startLoop(); else stopLoop();
  }, { rootMargin: '10% 0px 10% 0px' });

  function startLoop() {
    if (running) return;
    running = true;
    measure();
    raf = requestAnimationFrame(frame);
  }
  function stopLoop() {
    running = false;
    if (raf) cancelAnimationFrame(raf);
    raf = 0;
  }

  const onResize = () => {
    measure();
    if (!running) { shown = target = computeTarget(); emit(shown); }
  };

  return {
    start() {
      measure();
      Array.prototype.forEach.call(steps, (s) => stepObserver.observe(s));
      sectionObserver.observe(track);
      window.addEventListener('resize', onResize, { passive: true });
      window.addEventListener('orientationchange', onResize, { passive: true });
      /* Fonts and images change layout height; re-measure when they land. */
      if (document.fonts && document.fonts.ready) document.fonts.ready.then(onResize);
      shown = target = computeTarget();
      emit(shown);
      if (!reducedMotion) startLoop();
    },
    stop() {
      stopLoop();
      stepObserver.disconnect();
      sectionObserver.disconnect();
      window.removeEventListener('resize', onResize);
      window.removeEventListener('orientationchange', onResize);
    },
    setReducedMotion(v) {
      reducedMotion = !!v;
      if (reducedMotion) { stopLoop(); shown = target = Math.round(computeTarget()); emit(shown); }
      else if (visible) startLoop();
    },
    progress: () => shown,
    remeasure: onResize
  };
}
