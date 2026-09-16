# OHDSI Boston — website

The static site published at `docs/`. See [`../README.md`](../README.md) for the
repository as a whole, including the R program that generates the logo.

Everything here is hand-written HTML, CSS and ES modules. There is no build
step, no bundler, no framework and no server: what is in this directory is
exactly what the browser receives.

---

## Local development

Any static file server works, but it must be a *server* — the site uses ES
modules, which browsers refuse to load over `file://`.

```sh
cd docs
python3 -m http.server 8000
# then open http://localhost:8000
```

Edit a file, reload the page. That is the whole loop.

---

## Deploying to GitHub Pages

The site is already laid out for the simplest option:

1. **Settings → Pages**
2. **Source:** *Deploy from a branch*
3. **Branch:** `main`, **folder:** `/docs`

`docs/.nojekyll` is present so Jekyll does not touch the files.

`google-apps-script/` sits outside `docs/` deliberately: it is deployment
reference code for Google, and Pages never serves it.

**To publish from the repository root instead,** move the contents of `docs/`
up one level and change `<link>`/`<script>` paths if you also move the
subdirectories. **To publish from a `gh-pages` branch,** push the contents of
`docs/` to the root of that branch.

**Custom domain:** add a `CNAME` file containing the bare domain to `docs/`.

---

## Configuration

Everything you are likely to change lives in **`js/config.js`**.

```js
links: {
  ohdsi: 'https://ohdsi.org',
  ohdsiForums: 'https://forums.ohdsi.org',
  github: '',            // ← fill these in
  runAStudy: '',
  proposeQuestion: '',
  calendar: '',
  contactEmail: ''
}
```

A link left empty renders as a dimmed, inert placeholder with a screen-reader
note — not a broken link — so the site is safe to deploy before every
destination has been decided. Anything with a `data-link="key"` attribute in
`index.html` picks up `CONFIG.links[key]` automatically.

The other blocks are `signup` (endpoint and anti-abuse settings) and `story`
(scene pacing and how many marks the diagram draws).

Colours, type scale and spacing are CSS custom properties in
**`css/tokens.css`**, sampled from the logo.

---

## Email signup

```
browser ──POST──▶ Google Apps Script /exec ──▶ Google Sheet
(no secrets)      (runs as you)                (private)
```

Full setup instructions: [`../google-apps-script/README.md`](../google-apps-script/README.md).

Short version: create a Sheet, paste `Code.gs` into its bound Apps Script
project, deploy as a web app (*execute as: me*, *access: anyone*), and put the
`/exec` URL into `CONFIG.signup.endpoint`.

The request is sent as `text/plain` on purpose. That keeps it a CORS "simple
request", so the browser skips the preflight that Apps Script does not answer.
The body is still JSON.

### Form states

`idle → submitting → success | already | error`, plus `invalid` for input the
browser can reject without a round trip. The current state is on the form as
`data-state`, which is what the CSS keys off. Errors leave the button enabled
so the visitor can retry; success and "already subscribed" disable it.

### Anti-abuse, honestly

Three guards ship with the form: a honeypot field, a minimum fill time, and a
duplicate check in `localStorage`. All three run on the visitor's machine, so
**none of them is a security control** — anyone can read the endpoint out of
`config.js` and post to it with `curl`. They stop naive bots and double-clicks.
That is all they are for.

One rule shapes the order of the checks: **never fake a success.** The honeypot
is the only signal trusted enough to silently drop a submission, because a real
person cannot fill a field they cannot see. A submission that arrives faster
than a human could type is *delayed* rather than discarded — silently swallowing
a legitimate address is worse than letting a hurried bot through, since the
person walks away believing they signed up.

Real protection belongs in the Apps Script, which is where the rate limit, the
server-side validation and the server-side honeypot check live. If the endpoint
is abused, add a CAPTCHA and verify the token *inside* the script, with the
secret in Script Properties. Never put a "secret" in `config.js`.

---

## Architecture

```
docs/
├── index.html          all prose; works with JavaScript off
├── css/
│   ├── tokens.css      palette, type scale, spacing — the design system
│   ├── base.css        reset, typography, layout primitives, utilities
│   └── site.css        components
├── js/
│   ├── config.js       every URL and tunable value
│   ├── story.js        scene order + the words drawn inside the diagram
│   ├── scene-graph.js  the persistent SVG visual system
│   ├── scroll-director.js  scroll position → story progress
│   ├── signup.js       the form's state machine
│   ├── coastline.js    generated Boston geography
│   └── main.js         wiring, and nothing else
└── assets/             logo mark, star field, web font, social image
```

Five concerns, five modules, and the seams between them are narrow on purpose:

| Concern | Lives in | Talks to the rest via |
| --- | --- | --- |
| Story content | `index.html`, `story.js` | scene `id`s |
| Scroll state | `scroll-director.js` | one number, `progress` |
| Rendering | `scene-graph.js` | `viz.render(progress)` |
| Signup | `signup.js` | `attachSignup(form)` |
| Configuration | `config.js` | `CONFIG` |

### The animation model

**One cast, many layouts.** The diagram holds a fixed cast of marks that is
created once and never added to or removed from. A scene is not an animation;
it is a *layout* — a pure function that gives every mark in the cast a target
position, size, corner radius, colour and opacity. Moving between two scenes is
interpolation between two layouts.

That is the visual argument of the site. The same nine marks are the questions
in scene 1, the study code in scene 2, the packets travelling to institutions in
scene 3, the point estimates of a result in scene 4, one tile of the evidence
commons in scene 5, and new questions in scene 6. Because every mark is a
`<rect>` whose corner radius is interpolated as a fraction of its size — `0.5`
is a circle, `0` is a square — a question dot can literally *become* a cell.

**Scroll maps to one number.** `scroll-director.js` is the only module that
reads scroll position, and it reads it once per animation frame rather than on
every scroll event. It converts the step column's geometry into

```
progress ∈ [0, SCENES.length - 1]
```

where an integer means "this scene is centred" and the fraction between two
integers is the transition. `main.js` hands that number to `viz.render(p)`.

**Discrete states, not scroll hacks.** Inside `render`, the fractional part is
squeezed by `HOLD` (default 0.34, in `config.js`) so each scene *holds* at both
ends of its step and transitions through the middle, then eased with a
smoothstep. Scenes read as states with transitions between them, rather than as
a continuous smear.

**Nothing outside `scene-graph.js` touches the SVG.** The narrative text does
not know the diagram exists, and the diagram does not know the text exists.
They share scene ids and a number. That is the whole coupling.

### Adding or reordering a scene

Three edits, in this order:

1. **`js/story.js`** — add or move an entry in `SCENES` (`id`, `label`,
   `captions`).
2. **`index.html`** — add or move the matching
   `<article class="step" data-scene="<id>">` inside `[data-story-steps]`.
3. **`js/scene-graph.js`** — add a layout function with the same `id` inside
   `buildLayouts()`. Start from `base()`, which parks the whole cast where it
   belongs and invisible, then assign the marks the scene actually uses.

Nothing else changes: the step count, the scroll mapping, the counter and the
progress ring all derive their length from `SCENES`. `main.js` logs a console
warning if the DOM order and `story.js` disagree, and `scene-graph.js` throws at
startup if a scene has no layout — both failures are loud rather than silent.

### Boston geography

`js/coastline.js` is generated, not written. It holds the eastern Massachusetts
coastline in the same orthographic projection the logo uses, plus eight real
greater-Boston institutions placed on a ring ordered by their true bearing from
downtown — readable as a network, but not arbitrary. To regenerate it, adapt the
`sf` snippet in the repository root README against
`data-cache/ne10_northeast_land.geojson`.

---

## Accessibility

**Meaning without JavaScript.** All prose is in `index.html`. With scripts
disabled the `no-js` class keeps the story as an ordinary article and hides the
(empty, decorative) figure. Every claim the site makes survives.

**Reduced motion.** `prefers-reduced-motion: reduce` changes the experience
rather than degrading it: the figure stops being sticky, each scene is drawn
once beside its own text, the scroll director stops its animation loop and an
IntersectionObserver snaps the diagram to whichever step is in view, and the
reveal-on-scroll transitions become no-ops. The same six scenes, the same words,
no large movement. A change to the OS setting is picked up live.

**The diagram is decorative.** `aria-hidden="true"` on the figure, because
everything it shows is stated in the adjacent prose — including the phrases
drawn inside the SVG, which are repeated as tags under each step. A screen
reader gets the argument, not a list of shapes.

**Structure.** One `h1`, no skipped heading levels, landmarks (`header`, `main`,
`footer`, labelled `nav`), a skip link, and `<article>` per step.

**Forms.** Every input has a real `<label>`. Status messages live in a
`role="status"` region referenced by `aria-describedby`, so they are announced
politely without stealing focus. `aria-invalid` marks the field on a validation
failure. The honeypot is hidden from sight, from the tab order (`tabindex="-1"`)
and from assistive technology (`aria-hidden`).

**Contrast.** Body text is navy on paper or near-white on navy, comfortably past
AA. The logo orange only reaches ~2.6:1 on paper, so it is used there for rules,
marks and diagram fills — never for body text or small links. On the dark panels
the amber (~10:1) carries link colour instead.

**Keyboard.** Focus styles are a visible 2px orange ring on every interactive
element; nothing is reachable by mouse alone.

---

## Dependencies

**None at runtime.** No frameworks, no libraries, no CDN, no analytics, no
fonts fetched from a third party. The only network requests are for files in
this directory.

GSAP and ScrollTrigger were considered and not used. ScrollTrigger earns its
weight when you need many independently-timed triggers, pinning and scrubbed
timelines. This site needs exactly one thing from scroll — a single scalar — and
that is about forty lines of `requestAnimationFrame`, which is far less code
than configuring the library would have been, and leaves nothing to keep
updated. WASM was not needed: the diagram is roughly sixty rects and forty
paths, which SVG attribute updates handle inside a frame's budget.

The one asset worth noting is **Source Sans 3** (SIL OFL), self-hosted as a
~100 KB variable WOFF2 subset to Latin. It covers every weight the site uses in
one file, it is the closest open counterpart to the OHDSI wordmark, and
self-hosting keeps visitors' requests on one origin.

### Performance notes

- Scroll listeners never do layout work; a single `requestAnimationFrame` loop
  reads the position and renders.
- The loop only runs while the story is on screen, gated by an
  IntersectionObserver, and stops entirely under reduced motion.
- Layouts are pure and resolved once at startup, so a frame is interpolation
  and attribute writes — no allocation, no DOM creation.
- The cast shrinks on narrow viewports (`CONFIG.story.castNarrow`).
- Layout metrics are cached and only recomputed on resize, orientation change
  and `document.fonts.ready`.
