# OHDSI Boston

This repository holds two things:

| | |
| --- | --- |
| [`docs/`](docs/) | The **website**, a static site published with GitHub Pages. See [`docs/README.md`](docs/README.md). |
| the root | The **logo**, generated reproducibly in R. Documented below. |
| [`google-apps-script/`](google-apps-script/) | The signup endpoint for the site's email form. Deployed to Google, not to Pages. |

---

# The logo

A reproducible, vector-quality **OHDSI-Boston** logo generated entirely from R.

![OHDSI-Boston logo](ohdsi_boston_logo.png)

The OHDSI emblem — navy square, sweeping white bow, bowstring and arrow — is
reconstructed as analytic vector geometry. The orange half of the emblem
doubles as the lit surface of a globe: an **orthographic projection centred on
Massachusetts Bay** places Boston, Boston Harbor, Massachusetts Bay, Cape Cod
Bay and the hook of Cape Cod inside the orange field as a low-contrast tonal
texture.

The navy half is the night side of that same sphere: a sparse, seeded star
field, mostly at the threshold of visibility, kept clear of the white mark and
the square's border.

The design order is deliberate: **OHDSI first, Boston second, map third.** At
thumbnail size the geography disappears and the mark reads as the ordinary
OHDSI logo; at larger sizes the orange field resolves into eastern
Massachusetts.

## Running it

```sh
Rscript ohdsi_boston_logo.R
```

Outputs, all written next to the script:

| File | Notes |
| --- | --- |
| `ohdsi_boston_logo.png` | 2400 px wide, 400 dpi (`ragg`) |
| `ohdsi_boston_logo.svg` | vector (`svglite`); the orange field is a real SVG `linearGradient`/`radialGradient`, not a raster |
| `ohdsi_boston_logo.pdf` | vector (`cairo_pdf`) |

### Requirements

R ≥ 4.1 (gradient fills in `grid`) plus `ggplot2`, `sf`, `grid`, `systemfonts`,
`svglite` and `ragg`.

Geographic data is Natural Earth 1:10m admin-1 states, pre-extracted to
`data-cache/ne10_northeast_land.geojson` so iteration is fast and the script
runs offline. Delete that file to force a fresh download from Natural Earth.

Typography is Source Sans 3 (SIL OFL, bundled in `fonts/`), the closest open
counterpart to the humanist sans of the OHDSI wordmark. `ensure_fonts()`
registers the faces with `systemfonts` and also links them into the user font
directory so that the cairo PDF device resolves the same outlines. On a machine
that has never seen these fonts the *first* run may fall back to a system sans
in the PDF only, because fontconfig caches are read at process start — a second
run produces an identical PDF.

## How it is put together

Everything is expressed in a normalised emblem square, `x = 0..1`, `y = 0..1`,
which makes the geometry easy to re-tune.

| Function | Responsibility |
| --- | --- |
| `make_ohdsi_geometry()` | navy field, bow, bowstring and arrow as polygons |
| `orange_field_sf()` | the orange region, used to clip the geography |
| `get_boston_geography()` | cached Natural Earth coastline (data acquisition only) |
| `project_geography()` / `to_emblem()` | orthographic projection, then an affine map into emblem coordinates |
| `make_graticule()` | projected graticule, drawn at ~4 % opacity |
| `draw_globe_layer()` | land fill, coastline and graticule, clipped to the orange field |
| `draw_night_sky()` / `glow_polygons()` | the star field over the navy |
| `orange_gradient_grob()` | the orange gradient |
| `draw_ohdsi_symbol()` | the white mark, painted over the geography |
| `fit_line()` / `layout_smallcaps()` / `draw_wordmark()` | type |
| `build_logo()` / `save_logo()` | assembly and output |

A few choices worth calling out:

- **The bow edges are circular arcs.** Both edges were least-squares fitted to
  the reference artwork and match it to within ~0.5 % of the square's width;
  the fitted centres and radii live in `EMB`.
- **The orange gradient is radial about the centre of those arcs**, so its
  tonal bands run parallel to the sweeping white curve. The orange field then
  reads as a sphere lit from the lower right, with the bow as its limb.
- **Land is a veil of white over the gradient**, never a separate hue — no
  blue ocean, no green land, no map labels. Boston is a single barely-there
  dot rather than a pin.
- **Fill and coastline are clipped separately.** The fill is intersected with
  the orange field, but the stroke comes from the land's own boundary, so the
  clip edges along the bow and the arrow are never drawn as if they were
  coastline.
- **Stars sit on a jittered lattice, not a uniform draw.** A uniform draw
  clumps, and clumps read as dirt rather than as sky. Their radius and opacity
  follow a steep power law, so most are specks; the few bright ones get a glow
  built from concentric rings with decaying opacity, because a single flat disc
  reads as a grey bubble against the navy.
- **Type is sized by width, never scaled horizontally.** `fit_line()` picks the
  point size that makes a line its target width in the font's natural
  proportions; the subtitle is set in true small caps, with each glyph placed
  from the font's own advance widths.

The wordmark is set bold and fitted to sit within the width of the emblem
above it (`LAYOUT$word_width`), with the subtitle narrower again.

Tuning knobs (colours, star field, map framing, layout rhythm, output size) are
the `COL`, `GEO`, `SKY`, `MAP`, `LAYOUT` and `OUT` lists at the top of the
script.

## Boston geography

`docs/js/coastline.js` is generated from the same cached Natural Earth extract
as the logo, in the same orthographic projection. To regenerate it — after
changing the framing, say — run this against the repository root:

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
- `fonts/SourceSans3-*.ttf`: Source Sans 3, SIL Open Font Licence 1.1 (`fonts/OFL.txt`).
- `data-cache/ne10_northeast_land.geojson`: derived from Natural Earth, public domain.
