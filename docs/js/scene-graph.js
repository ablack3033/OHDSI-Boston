/**
 * scene-graph.js — the persistent visual system.
 *
 * ONE cast of shapes exists for the whole story. Scenes never create or
 * destroy anything: each scene is a *layout*, a pure function that assigns
 * every member of the cast a target position, size, corner radius, colour and
 * opacity. Moving between scenes is interpolation between two layouts.
 *
 * That is the whole visual thesis. The same nine shapes are the questions in
 * scene 1, the protocol in scene 2, the code travelling to institutions in
 * scene 3, the aggregate result in scene 4, one tile of the evidence commons
 * in scene 5, and new questions again in scene 6. A rect with rx = half its
 * width is a circle, so a question dot can literally become a cell.
 *
 * Public interface (deliberately tiny — the rest of the site uses only this):
 *
 *     const viz = createSceneGraph(svgEl, { cast, reducedMotion });
 *     viz.render(progress);   // progress in [0, SCENES.length - 1]
 *     viz.setReducedMotion(bool);
 *     viz.destroy();
 *
 * Nothing outside this file touches the SVG.
 */

import { SCENES } from './story.js';
import { COAST_PATH, SITE_POINTS } from './coastline.js';

const SVG_NS = 'http://www.w3.org/2000/svg';
const VIEW = 100;                    // the diagram lives in a 0..100 square
const VIEW_BOX = '-4 -4 108 108';    // ...with a margin, so nothing overflows
const CENTRE = { x: 50, y: 50 };

const COLOUR = {
  navy:     [26, 60, 91],
  navySoft: [92, 122, 150],
  orange:   [239, 127, 27],
  amber:    [253, 197, 13]
};

/* ------------------------------------------------------------------ maths */

const lerp = (a, b, t) => a + (b - a) * t;
const clamp = (v, lo, hi) => (v < lo ? lo : v > hi ? hi : v);
const smoothstep = (t) => t * t * (3 - 2 * t);

/** Deterministic RNG, so the composition is identical on every load. */
function mulberry32(seed) {
  return function () {
    seed |= 0; seed = (seed + 0x6D2B79F5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const onRing = (i, n, r, phase = -Math.PI / 2) => {
  const a = phase + (i / n) * Math.PI * 2;
  return { x: CENTRE.x + r * Math.cos(a), y: CENTRE.y + r * Math.sin(a) };
};

const rgb = (c) => `rgb(${c[0] | 0},${c[1] | 0},${c[2] | 0})`;

/* --------------------------------------------------------- small SVG util */

function el(name, attrs) {
  const node = document.createElementNS(SVG_NS, name);
  for (const k in attrs) node.setAttribute(k, attrs[k]);
  return node;
}

/* ================================================================= layouts */
/*
 * Each layout receives a context of precomputed anchor positions and returns
 * target state. Layout ids must match the scene ids in story.js.
 *
 * Agent state: { x, y, s, rx, c, o }
 *   s  — side length in view units;  rx — corner radius as a fraction of s
 *        (0.5 = circle, 0 = square);  c — colour triple;  o — opacity.
 * Link state: { a, b, o, w, curve, dash }
 *   a/b are agent indices, or { x, y } for a fixed anchor.
 */

function buildLayouts(ctx) {
  const { idx, people, lattice, sites, studyTile, n } = ctx;
  const base = () => {
    /* Everything starts invisible and parked where it belongs, so anything a
       scene does not mention simply fades rather than flying in from 0,0. */
    const a = new Array(n);
    for (let i = 0; i < n; i++) a[i] = { x: CENTRE.x, y: CENTRE.y, s: 2, ar: 1, rx: 0.5, c: COLOUR.navy, o: 0 };
    idx.people.forEach((i, k) => Object.assign(a[i], people[k], { s: 2.4 }));
    idx.sites.forEach((i, k) => Object.assign(a[i], sites[k], { s: 5.2, rx: 0.22 }));
    idx.archive.forEach((i, k) => Object.assign(a[i], lattice[k], { s: 3.6, rx: 0.14, c: COLOUR.navySoft }));
    idx.quanta.forEach((i) => Object.assign(a[i], { s: 1.5, rx: 0.5, c: COLOUR.orange }));
    return a;
  };

  /* Which person each question belongs to, in scene 1 and again in scene 6.
     Different people the second time round: the questions have moved on. */
  const askerA = (j) => idx.people[(j * 3) % ctx.counts.people];
  const askerB = (j) => idx.people[(j * 3 + 5) % ctx.counts.people];

  const nearPerson = (agents, personIdx, spread) => {
    const p = agents[personIdx];
    const dx = p.x - CENTRE.x, dy = p.y - CENTRE.y;
    const m = Math.hypot(dx, dy) || 1;
    return { x: p.x + (dx / m) * spread, y: p.y + (dy / m) * spread };
  };

  return {
    /* ---------------------------------------------------- 01 · questions */
    questions() {
      const a = base();
      idx.people.forEach((i) => Object.assign(a[i], { o: 0.92, c: COLOUR.navy }));
      const links = [];
      idx.quanta.forEach((i, j) => {
        const owner = askerA(j);
        Object.assign(a[i], nearPerson(a, owner, 5.5 + (j % 3) * 1.6), { o: 0.95, s: 1.5 });
        links.push({ a: i, b: owner, o: 0.3, w: 0.22 });
      });
      return { agents: a, links, zoom: 1, props: { coast: 0, protocol: 0, result: 0, cores: 0 } };
    },

    /* -------------------------------------------------------- 02 · study */
    study() {
      const a = base();
      idx.people.forEach((i, k) => {
        const p = onRing(k, ctx.counts.people, 46);
        Object.assign(a[i], p, { o: 0.14, s: 1.7 });
      });
      /* Nine questions settle into a 3 x 3 block of study code inside the
         protocol card: the messy becomes systematic. */
      idx.quanta.forEach((i, j) => {
        const col = j % 3, row = (j / 3) | 0;
        Object.assign(a[i], {
          x: 43 + col * 7, y: 62.5 + row * 5.5,
          s: 3.4, rx: 0.12, o: 1
        });
      });
      return { agents: a, links: [], zoom: 1, props: { coast: 0, protocol: 1, protocolText: 1, result: 0, cores: 0 } };
    },

    /* ------------------------------------------------------ 03 · network */
    network() {
      const a = base();
      idx.people.forEach((i, k) => Object.assign(a[i], onRing(k, ctx.counts.people, 52), { o: 0, s: 1.4 }));
      idx.sites.forEach((i) => Object.assign(a[i], { o: 1 }));
      const links = [];
      idx.quanta.forEach((i, j) => {
        const site = sites[j % ctx.counts.sites];
        /* The travelling packet stops just short of the institution: the code
           arrives at the door, it does not merge with the data. */
        const t = 0.84, perp = ((j / ctx.counts.sites) | 0) === 0 ? 0 : 3.6;
        const dx = site.x - CENTRE.x, dy = site.y - CENTRE.y, m = Math.hypot(dx, dy) || 1;
        Object.assign(a[i], {
          x: lerp(CENTRE.x, site.x, t) + (-dy / m) * perp,
          y: lerp(CENTRE.y, site.y, t) + (dx / m) * perp,
          s: 1.8, rx: 0.5, o: 1
        });
      });
      idx.sites.forEach((i) => links.push({ a: CENTRE, b: i, o: 0.45, w: 0.28, curve: 0.18, dash: '1.6 1.8' }));
      return { agents: a, links, zoom: 1, props: { coast: 0.13, protocol: 0.4, protocolText: 0, protocolScale: 0.26, result: 0, cores: 1 } };
    },

    /* ----------------------------------------------------- 04 · evidence */
    evidence() {
      const a = base();
      idx.people.forEach((i, k) => Object.assign(a[i], onRing(k, ctx.counts.people, 52), { o: 0, s: 1.4 }));
      idx.sites.forEach((i) => Object.assign(a[i], { o: 0.34, s: 4.2 }));
      /* Three quanta become the header of the result; six become the point
         estimates of a small forest plot drawn on the card. */
      const rows = [
        [52.0, 47.5], [48.6, 53.0], [54.2, 58.5],
        [50.2, 64.0], [46.8, 69.5], [51.6, 75.0]
      ];
      idx.quanta.forEach((i, j) => {
        if (j < 3) {
          /* Metadata bars: same marks, stretched. */
          Object.assign(a[i], { x: 41.5 + j * 8.5, y: 41.2, s: 1.3, ar: 4.6, rx: 0.2, o: 0.85, c: COLOUR.amber });
        } else {
          const [x, y] = rows[j - 3];
          Object.assign(a[i], { x, y, s: 2.5, rx: 0.5, o: 1, c: COLOUR.orange });
        }
      });
      /* Returning results stop at the edge of the result card. They must never
         look like records pouring into one central store — the whole point is
         that they are aggregates, and that nothing central ingests the data. */
      const links = [];
      idx.sites.forEach((i, k) => {
        const p = sites[k];
        const dx = p.x - CENTRE.x, dy = p.y - CENTRE.y, m = Math.hypot(dx, dy) || 1;
        const stop = { x: CENTRE.x + (dx / m) * 23, y: CENTRE.y + (dy / m) * 23 };
        links.push({ a: i, b: stop, o: 0.5, w: 0.3, curve: -0.16, dash: '1.3 1.5' });
      });
      return { agents: a, links, zoom: 1, props: { coast: 0.03, protocol: 0, result: 1, cores: 0.45 } };
    },

    /* ------------------------------------------------------ 05 · commons */
    commons() {
      const a = base();
      idx.archive.forEach((i) => Object.assign(a[i], { o: 0.5 }));
      /* The result we just followed contracts into ONE tile of the lattice —
         still made of its nine parts, now one object among many. */
      const slot = studyTile;
      idx.quanta.forEach((i, j) => {
        const col = j % 3, row = (j / 3) | 0;
        Object.assign(a[i], {
          x: slot.x + (col - 1) * 1.45, y: slot.y + (row - 1) * 1.45,
          s: 1.3, rx: 0.1, o: 1, c: COLOUR.orange
        });
      });
      return { agents: a, links: ctx.commonsEdges, zoom: 0.62, props: { coast: 0.04, protocol: 0, result: 0, cores: 0 } };
    },

    /* --------------------------------------------------------- 06 · loop */
    loop() {
      const a = base();
      /* People return to exactly where they stood in scene 1. */
      idx.people.forEach((i) => Object.assign(a[i], { o: 0.92, c: COLOUR.navy }));
      /* What we learned contracts to a dense core of known evidence. */
      idx.archive.forEach((i, k) => Object.assign(a[i], {
        x: lerp(CENTRE.x, lattice[k].x, 0.26),
        y: lerp(CENTRE.y, lattice[k].y, 0.26),
        s: 1.8, rx: 0.16, o: 0.26
      }));
      const links = [];
      idx.quanta.forEach((i, j) => {
        const owner = askerB(j);
        Object.assign(a[i], nearPerson(a, owner, 5.5 + (j % 3) * 1.6), { o: 0.95, s: 1.5, rx: 0.5 });
        links.push({ a: i, b: owner, o: 0.3, w: 0.22 });
        if (j % 2 === 0) links.push({ a: CENTRE, b: owner, o: 0.16, w: 0.18, curve: 0.22, dash: '1.4 2' });
      });
      return { agents: a, links, zoom: 1, props: { coast: 0, protocol: 0, result: 0, cores: 0 } };
    }
  };
}

/* ================================================================ factory */

export function createSceneGraph(svg, options = {}) {
  const counts = Object.assign({ people: 14, quanta: 9, sites: 8, archive: 30 }, options.cast);
  /* Fraction of each step spent holding the scene rather than transitioning. */
  const HOLD = typeof options.hold === 'number' ? options.hold : 0.34;
  let reducedMotion = !!options.reducedMotion;

  /* ---------------------------------------------------- cast bookkeeping */
  const idx = { people: [], quanta: [], sites: [], archive: [] };
  let cursor = 0;
  for (const group of ['people', 'quanta', 'sites', 'archive']) {
    for (let k = 0; k < counts[group]; k++) idx[group].push(cursor++);
  }
  const n = cursor;

  /* ------------------------------------------------- precomputed anchors */
  const rnd = mulberry32(20260916);

  const people = Array.from({ length: counts.people }, (_, k) => {
    const p = onRing(k, counts.people, 33 + (rnd() - 0.5) * 7);
    return { x: p.x, y: p.y };
  });

  const sites = SITE_POINTS.slice(0, counts.sites).map((p) => ({ x: p.x, y: p.y }));

  /* Commons lattice: a jittered grid, one slot per archived study plus one
     for the study the visitor has just followed. */
  const slots = counts.archive + 1;
  const cols = Math.ceil(Math.sqrt(slots * 1.25));
  const rowsN = Math.ceil(slots / cols);
  const lattice = [];
  const dx = 62 / cols, dy = 62 / rowsN;
  for (let r = 0, k = 0; r < rowsN; r++) {
    const inRow = Math.min(cols, slots - k);          // centre a partial row
    for (let c = 0; c < inRow; c++, k++) {
      lattice.push({
        x: 50 + (c - (inRow - 1) / 2) * dx + (rnd() - 0.5) * 3.2,
        y: 50 + (r - (rowsN - 1) / 2) * dy + (rnd() - 0.5) * 3.2
      });
    }
  }
  /* Put the visitor's study slightly off-centre: found, not enthroned. */
  const studySlot = Math.min(lattice.length - 1, Math.floor(cols * Math.floor(rowsN / 2) + Math.floor(cols / 2) + 1));
  const archiveSlots = lattice.map((_, k) => k).filter((k) => k !== studySlot);
  const archiveAnchors = archiveSlots.map((k) => lattice[k]);

  /* Knowledge-graph edges: each tile linked to a couple of near neighbours. */
  const commonsEdges = [];
  for (let k = 0; k < archiveAnchors.length; k++) {
    const gi = idx.archive[k];
    const near = archiveAnchors
      .map((p, j) => ({ j, d: Math.hypot(p.x - archiveAnchors[k].x, p.y - archiveAnchors[k].y) }))
      .filter((o) => o.j > k)
      .sort((a, b) => a.d - b.d)
      .slice(0, rnd() > 0.45 ? 2 : 1);
    for (const o of near) {
      if (commonsEdges.length < 40) commonsEdges.push({ a: gi, b: idx.archive[o.j], o: 0.2, w: 0.16 });
    }
  }

  /* The archive fills every lattice slot except the one reserved for the
     study the visitor has just followed. */
  const LAYOUTS = buildLayouts({
    idx, n, counts, people, sites,
    lattice: archiveAnchors,
    studyTile: lattice[studySlot],
    commonsEdges
  });

  /* Resolve every scene once. Layouts are pure, so this never needs redoing. */
  const states = SCENES.map((scene) => {
    const fn = LAYOUTS[scene.id];
    if (!fn) throw new Error(`scene-graph: no layout for scene "${scene.id}"`);
    return fn();
  });
  const LAST = states.length - 1;

  /* ------------------------------------------------------- build the DOM */
  svg.setAttribute('viewBox', VIEW_BOX);
  svg.innerHTML = '';

  const defs = el('defs');
  svg.appendChild(defs);

  const ring = el('g', { class: 'sg-ring' });
  const RING_R = 46.5;
  const RING_C = 2 * Math.PI * RING_R;
  /* Two half arcs rather than a <circle>, because a circle's path direction is
     not something we can rely on and the arc must grow *clockwise* from the
     top: the ring is the story's progress, and it has to read as one turn. */
  const RING_D = `M50 ${50 - RING_R}A${RING_R} ${RING_R} 0 0 1 50 ${50 + RING_R}A${RING_R} ${RING_R} 0 0 1 50 ${50 - RING_R}`;
  const ringTrack = el('path', { d: RING_D, class: 'sg-ring__track' });
  const ringArc = el('path', { d: RING_D, class: 'sg-ring__arc', 'stroke-dasharray': `0 ${RING_C}` });
  const ringHead = el('circle', { r: 1.15, class: 'sg-ring__head' });
  ring.append(ringTrack, ringArc, ringHead);
  svg.appendChild(ring);

  /* Stage holds everything that zooms. */
  const stage = el('g', { class: 'sg-stage' });
  svg.appendChild(stage);

  const clip = el('clipPath', { id: 'sg-clip-square' });
  clip.appendChild(el('rect', { x: 0, y: 0, width: VIEW, height: VIEW }));
  defs.appendChild(clip);

  const coast = el('g', { class: 'sg-coast-wrap', opacity: 0, 'clip-path': 'url(#sg-clip-square)' });
  coast.appendChild(el('path', { d: COAST_PATH, class: 'sg-coast' }));
  stage.appendChild(coast);

  /* Protocol card — scene 2. */
  const protocol = el('g', { class: 'sg-card sg-card--protocol', opacity: 0 });
  protocol.appendChild(el('rect', { x: 33, y: 26, width: 34, height: 52, rx: 1.6, class: 'sg-card__body' }));
  const protocolText = el('g');
  ['Cohorts', 'Outcomes', 'Analysis', 'Diagnostics'].forEach((label, i) => {
    const y = 34.5 + i * 6;
    const row = el('g');
    const t = el('text', { x: 37.5, y: y + 0.9, class: 'sg-label sg-label--row' });
    t.textContent = label;
    row.append(el('line', { x1: 37.5, y1: y + 2.6, x2: 62.5, y2: y + 2.6, class: 'sg-rule' }), t);
    protocolText.appendChild(row);
  });
  const codeLabel = el('text', { x: 37.5, y: 59.5, class: 'sg-label sg-label--row' });
  codeLabel.textContent = 'Study code';
  protocolText.append(codeLabel);
  protocol.appendChild(protocolText);
  stage.appendChild(protocol);

  /* Result card — scene 4, with the forest-plot scaffolding drawn in. */
  const result = el('g', { class: 'sg-card sg-card--result', opacity: 0 });
  result.appendChild(el('rect', { x: 32, y: 30, width: 36, height: 52, rx: 1.6, class: 'sg-card__body' }));
  result.appendChild(el('line', { x1: 50, y1: 44, x2: 50, y2: 78, class: 'sg-rule sg-rule--axis' }));
  [47.5, 53.0, 58.5, 64.0, 69.5, 75.0].forEach((y, i) => {
    const half = 5.5 + (i % 3) * 1.8;
    const cx = [52.0, 48.6, 54.2, 50.2, 46.8, 51.6][i];
    result.appendChild(el('line', { x1: cx - half, y1: y, x2: cx + half, y2: y, class: 'sg-whisker' }));
  });
  const resultTitle = el('text', { x: 50, y: 36.4, class: 'sg-label sg-label--row', 'text-anchor': 'middle' });
  resultTitle.textContent = 'Aggregate result';
  result.appendChild(resultTitle);
  stage.appendChild(result);

  /* Institution "cores": the data that never moves. */
  /* Links, then agents on top. */
  const MAX_LINKS = Math.max(40, ...states.map((s) => s.links.length));
  const linkLayer = el('g', { class: 'sg-links' });
  const linkNodes = Array.from({ length: MAX_LINKS }, () => {
    const p = el('path', { class: 'sg-link', opacity: 0 });
    linkLayer.appendChild(p);
    return p;
  });
  stage.appendChild(linkLayer);

  const agentLayer = el('g', { class: 'sg-agents' });
  const agentNodes = Array.from({ length: n }, () => {
    const r = el('rect', { class: 'sg-agent' });
    agentLayer.appendChild(r);
    return r;
  });
  stage.appendChild(agentLayer);

  /* Institution "cores": the records that never move. Drawn after the agents
     so they sit on top of the institution marks rather than behind them. */
  const cores = el('g', { class: 'sg-cores', opacity: 0 });
  sites.forEach((p) => cores.appendChild(el('rect', {
    x: p.x - 0.6, y: p.y - 0.6, width: 1.2, height: 1.2, rx: 0.28, class: 'sg-core'
  })));
  stage.appendChild(cores);

  /* Per-scene caption groups. Decorative: the same words are in the prose. */
  const captionLayer = el('g', { class: 'sg-captions' });
  const CAPTION_POS = {
    questions: [[24, 22], [70, 28], [22, 74], [72, 76]],
    study: [[50, 20]],
    network: [[50, 8], [50, 92]],
    evidence: [[50, 22]],
    commons: [[50, 14]],
    loop: [[50, 20]]
  };
  const captionGroups = {};
  SCENES.forEach((scene) => {
    const g = el('g', { opacity: 0 });
    const spots = CAPTION_POS[scene.id] || [];
    const texts = scene.captions || [];
    spots.forEach((pos, i) => {
      if (!texts[i]) return;
      const t = el('text', { x: pos[0], y: pos[1], class: 'sg-label sg-label--aside' });
      t.setAttribute('text-anchor', pos[0] === 50 ? 'middle' : pos[0] < 50 ? 'start' : 'end');
      t.textContent = texts[i];
      g.appendChild(t);
    });
    captionGroups[scene.id] = g;
    captionLayer.appendChild(g);
  });
  svg.appendChild(captionLayer);

  /* ------------------------------------------------------------ renderer */
  const cur = Array.from({ length: n }, () => ({ x: 50, y: 50, s: 2, ar: 1, rx: 0.5, c: [0, 0, 0], o: 0 }));
  let lastKey = null;

  function blendAgents(A, B, t) {
    for (let i = 0; i < n; i++) {
      const a = A[i], b = B[i], o = cur[i];
      o.x = lerp(a.x, b.x, t);
      o.y = lerp(a.y, b.y, t);
      o.s = lerp(a.s, b.s, t);
      o.ar = lerp(a.ar ?? 1, b.ar ?? 1, t);
      o.rx = lerp(a.rx, b.rx, t);
      o.o = lerp(a.o, b.o, t);
      o.c[0] = lerp(a.c[0], b.c[0], t);
      o.c[1] = lerp(a.c[1], b.c[1], t);
      o.c[2] = lerp(a.c[2], b.c[2], t);
    }
  }

  function paintAgents() {
    for (let i = 0; i < n; i++) {
      const a = cur[i], node = agentNodes[i];
      if (a.o < 0.004) { node.setAttribute('opacity', 0); continue; }
      const h = a.s, w = a.s * a.ar;
      node.setAttribute('x', (a.x - w / 2).toFixed(2));
      node.setAttribute('y', (a.y - h / 2).toFixed(2));
      node.setAttribute('width', w.toFixed(2));
      node.setAttribute('height', h.toFixed(2));
      node.setAttribute('rx', (h * a.rx).toFixed(2));
      node.setAttribute('fill', rgb(a.c));
      node.setAttribute('opacity', a.o.toFixed(3));
    }
  }

  const anchor = (ref) => (typeof ref === 'number' ? cur[ref] : ref);

  function paintLink(node, link, opacity) {
    if (!link || opacity < 0.004) { node.setAttribute('opacity', 0); return; }
    const p = anchor(link.a), q = anchor(link.b);
    const curve = link.curve || 0;
    let d;
    if (curve) {
      const mx = (p.x + q.x) / 2, my = (p.y + q.y) / 2;
      const dx = q.x - p.x, dy = q.y - p.y;
      d = `M${p.x.toFixed(2)} ${p.y.toFixed(2)}Q${(mx - dy * curve).toFixed(2)} ${(my + dx * curve).toFixed(2)} ${q.x.toFixed(2)} ${q.y.toFixed(2)}`;
    } else {
      d = `M${p.x.toFixed(2)} ${p.y.toFixed(2)}L${q.x.toFixed(2)} ${q.y.toFixed(2)}`;
    }
    node.setAttribute('d', d);
    node.setAttribute('stroke-width', (link.w || 0.2).toFixed(2));
    node.setAttribute('opacity', opacity.toFixed(3));
    if (link.dash) node.setAttribute('stroke-dasharray', link.dash);
    else node.removeAttribute('stroke-dasharray');
  }

  /* Links cannot be interpolated when their endpoints differ, so a slot whose
     endpoints change cross-fades: out on the old pair, in on the new. */
  function paintLinks(A, B, t) {
    for (let i = 0; i < MAX_LINKS; i++) {
      const a = A.links[i], b = B.links[i];
      const same = a && b && a.a === b.a && a.b === b.b;
      if (same) {
        paintLink(linkNodes[i], { ...b, w: lerp(a.w || 0.2, b.w || 0.2, t), curve: lerp(a.curve || 0, b.curve || 0, t) }, lerp(a.o, b.o, t));
      } else if (t < 0.5) {
        paintLink(linkNodes[i], a, a ? a.o * (1 - t * 2) : 0);
      } else {
        paintLink(linkNodes[i], b, b ? b.o * (t * 2 - 1) : 0);
      }
    }
  }

  const PROP_NODES = { coast, protocol, protocolText, result, cores };

  function paintProps(A, B, t) {
    for (const key in PROP_NODES) {
      const o = lerp(A.props[key] || 0, B.props[key] || 0, t);
      PROP_NODES[key].setAttribute('opacity', o.toFixed(3));
    }
    const ps = lerp(A.props.protocolScale ?? 1, B.props.protocolScale ?? 1, t);
    protocol.setAttribute('transform', `translate(${(50 * (1 - ps)).toFixed(2)} ${(52 * (1 - ps)).toFixed(2)}) scale(${ps.toFixed(3)})`);

    const zoom = lerp(A.zoom, B.zoom, t);
    stage.setAttribute('transform', `translate(${(50 * (1 - zoom)).toFixed(2)} ${(50 * (1 - zoom)).toFixed(2)}) scale(${zoom.toFixed(3)})`);
  }

  function paintCaptions(from, to, t) {
    SCENES.forEach((scene, i) => {
      const o = i === from ? 1 - t : i === to ? t : 0;
      captionGroups[scene.id].setAttribute('opacity', (o * o).toFixed(3));
    });
  }

  function paintRing(global) {
    const g = clamp(global, 0, 1);
    ringArc.setAttribute('stroke-dasharray', `${(RING_C * g).toFixed(2)} ${RING_C.toFixed(2)}`);
    const a = g * Math.PI * 2;                 // 0 = twelve o'clock, clockwise
    ringHead.setAttribute('cx', (50 + RING_R * Math.sin(a)).toFixed(2));
    ringHead.setAttribute('cy', (50 - RING_R * Math.cos(a)).toFixed(2));
    ringHead.setAttribute('opacity', g > 0.002 ? 1 : 0);
  }

  /**
   * Render the story at a continuous position.
   * @param {number} progress 0 .. SCENES.length - 1
   */
  function render(progress) {
    const p = clamp(progress, 0, LAST);
    let from = Math.min(Math.floor(p), LAST - 1);
    let t = p - from;

    if (reducedMotion) {
      from = Math.round(p);
      from = Math.min(from, LAST);
      const state = states[from];
      const key = `r${from}`;
      if (key !== lastKey) {
        lastKey = key;
        blendAgents(state.agents, state.agents, 0);
        paintAgents();
        paintLinks(state, state, 0);
        paintProps(state, state, 0);
        paintCaptions(from, from, 0);
      }
      paintRing(LAST ? from / LAST : 0);
      return;
    }

    /* Hold each scene at both ends, transition through the middle. */
    t = smoothstep(clamp((t - HOLD / 2) / (1 - HOLD), 0, 1));

    const A = states[from], B = states[from + 1];
    blendAgents(A.agents, B.agents, t);
    paintAgents();
    paintLinks(A, B, t);
    paintProps(A, B, t);
    paintCaptions(from, from + 1, t);
    paintRing(LAST ? p / LAST : 0);
  }

  return {
    render,
    sceneCount: states.length,
    setReducedMotion(v) { reducedMotion = !!v; lastKey = null; },
    destroy() { svg.innerHTML = ''; }
  };
}
