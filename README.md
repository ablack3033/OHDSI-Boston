# OHDSI Boston

This repository holds two things:

| | |
| --- | --- |
| [`docs/`](docs/) | The **website**, a static site published with GitHub Pages. See [`docs/README.md`](docs/README.md). |
| the root | The **logo**, generated reproducibly in R. Documented below. |
| [`google-apps-script/`](google-apps-script/) | The signup endpoint for the site's email form. Deployed to Google, not to Pages. |

---

# The logo

The OHDSI Boston badge, generated entirely from R.

![OHDSI Boston badge](ohdsi_boston_logo.png)

A square badge on a black keyline. The OHDSI mark — navy field, sweeping white
bow, bowstring and arrow — is reconstructed as analytic vector geometry; the
lit orange half carries a white Boston skyline (the Zakim bridge, the downtown
towers, the Custom House, the Prudential and the light towers of Fenway Park),
its reflection broken across the harbour, and the word BOSTON.

## Running it

```sh
Rscript ohdsi_boston_logo.R
```

| File | What it is |
| --- | --- |
| `ohdsi_boston_logo.{png,svg,pdf}` | the badge, with its keyline |
| `docs/assets/logo.{svg,png}` | the badge without the keyline, for the website |
| `docs/assets/badge.svg` | emblem, skyline and harbour, no wordmark |
| `docs/assets/mark.svg` | the OHDSI emblem alone — the only variant that survives favicon size |
| `docs/assets/skyline.svg` | the white skyline on its own, for the site's horizon band |

### Requirements

R ≥ 4.1 (gradient fills in `grid`) plus `ggplot2`, `grid`, `systemfonts`,
`svglite` and `ragg`. Typography is Source Sans 3 (SIL OFL, bundled in
`fonts/`): Black for BOSTON, Bold for the FENWAY PARK sign.

`ensure_fonts()` registers the faces with `systemfonts` and links them into the
user font directory so the cairo PDF device resolves the same outlines. On a
machine that has never seen these fonts the *first* run may fall back to a
system sans in the PDF only, because fontconfig caches are read at process
start; a second run produces an identical PDF.

## How it is put together

Everything lives in a normalised art square, `x = 0..1`, `y = 0..1` with y
pointing up, so any part can be re-tuned by editing a constant.

| Function | Responsibility |
| --- | --- |
| `make_ohdsi_geometry()` | navy field, bow, bowstring and arrow |
| `zakim()` / `downtown()` / `dome()` / `fenway()` | the skyline, as data |
| `draw_skyline()` | those parts, plus the bulb banks, lattice masts and sign gantry |
| `make_water()` | the harbour and its reflections |
| `draw_lettering()` | BOSTON and the FENWAY PARK sign |
| `build_logo()` / `save_logo()` / `save_skyline()` / `save_all()` | assembly and output |

A few choices worth calling out:

- **The bow edges are circular arcs.** Both were least-squares fitted to the
  reference artwork, weighting the top of the arc where it is flattest and
  therefore least forgiving. Mean residual is 0.004 of the square's width; the
  fitted centres and radii are in `EMB`.
- **The band wraps the top-right corner.** The inner edge leaves through the
  top border and the outer edge through the right, which is what leaves the
  small orange wedge in the corner.
- **The pylon is a straight taper.** A concave profile reads as a wine glass
  rather than a tower, which is how the first attempt looked.
- **Lamp banks are circles with gaps, not a plate.** Spaced at 2.1× their
  radius: any tighter and the bulbs merge into a cloud.
- **A reflection is the skyline again, not noise.** The strokes are organised
  into vertical columns under the things that cast them, alternating left and
  right so each column reads as a zigzag, with clean orange between. Each
  stroke is a lens — a bar with tapered ends — because a rectangle reads as a
  dash and a tapered one reads as a glint.
- **BOSTON is tracked, not stretched.** The reference's face is wider per unit
  of cap height than Source Sans 3 Black, so matching its width alone would
  leave the letters a fifth too tall. The cap height is matched and the line
  tracked out instead: every glyph keeps its own proportions.

Tuning knobs are the `COL`, `GRADIENT`, `CANVAS`, `EMB` and `WATER_Y`
constants, plus the skyline functions in section 3.

## Boston geography

`docs/js/coastline.js` — the geography inside the website's scrollytelling
diagram, not the logo — is generated from the cached Natural Earth extract in
`data-cache/`. To regenerate it after changing the framing, run this against
the repository root:

```r
library(sf); sf_use_s2(FALSE)
land <- st_read("data-cache/ne10_northeast_land.geojson")

lon0 <- -70.95; lat0 <- 42.15; span_km <- 190      # the diagram's framing
crs  <- sprintf("+proj=ortho +lat_0=%f +lon_0=%f +R=6371000 +units=m +no_defs",
                lat0, lon0)

half <- span_km * 1000 / 2
box  <- st_polygon(list(cbind(c(-half, half, half, -half, -half) * 1.05,
                              c(-half, -half, half, half, -half) * 1.05)))
pj   <- st_intersection(st_make_valid(st_transform(st_set_crs(land, 4326), crs)),
                        st_sfc(box, crs = crs))
pj   <- st_simplify(pj, dTolerance = 260)          # keeps the file a few KB

# Project to the diagram's 0..100 box (y flipped for SVG) and emit one
# "M x y L x y ..." subpath per ring; see docs/js/coastline.js for the shape
# of the output. SITE_POINTS are eight real institutions placed on a ring
# ordered by their true bearing from downtown Boston.
```

## Licences

- Code: see repository licence.
- `fonts/SourceSans3-{Black,Bold,Semibold}.ttf`: Source Sans 3, SIL Open Font Licence 1.1 (`fonts/OFL.txt`).
- `data-cache/ne10_northeast_land.geojson`: derived from Natural Earth, public domain.
