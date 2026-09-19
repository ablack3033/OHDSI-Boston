## ---------------------------------------------------------------------------
## ohdsi_boston_logo.R
##
## The OHDSI Boston badge, generated entirely in R.
##
## A square badge on a black keyline. The OHDSI mark — navy field, sweeping
## white bow, bowstring and arrow — is reconstructed as analytic vector
## geometry; the lit orange half carries a white Boston skyline (the Zakim
## bridge, the downtown towers, the Prudential and Fenway Park), its reflection
## in the harbour, and the word BOSTON.
##
## Every number in the GEOMETRY sections was least-squares fitted or measured
## against the reference artwork in a normalised art square, x = 0..1, y = 0..1
## with y pointing up, so the whole thing can be re-tuned by editing constants.
##
## Usage:  Rscript ohdsi_boston_logo.R
## ---------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(ggplot2)
  library(grid)
  library(systemfonts)
})

HERE <- tryCatch({
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grep("^--file=", a)])
  if (length(f)) dirname(normalizePath(f)) else getwd()
}, error = function(e) getwd())


## ===========================================================================
## 1. Configuration
## ===========================================================================

## --- Palette, sampled from the reference ------------------------------------
## The orange field is a linear gradient; its direction and end colours were
## fitted by regressing the orange pixels' channels on position.
COL <- list(
  navy         = "#15405F",
  orange_dark  = "#EF7B16",   # up-gradient end (upper left of the orange)
  orange_mid   = "#F49213",
  orange_light = "#FDC605",   # down-gradient end (lower right)
  white        = "#FFFFFF",
  frame        = "#000000"
)

## Unit vector of the gradient, and the two ends of its axis in art coords.
GRADIENT <- list(
  from = c(0.117, 0.577),
  to   = c(1.028, 0.393)
)

## --- Canvas ----------------------------------------------------------------
## `frame` is the black keyline, as a fraction of the art square's side.
## Set it to 0 for a badge with no border.
CANVAS <- list(frame = 0.097)

## --- Output ----------------------------------------------------------------
OUT <- list(
  stem  = file.path(HERE, "ohdsi_boston_logo"),
  width = 6,      # inches
  dpi   = 400
)

## --- Typography -------------------------------------------------------------
FONT <- list(
  family   = "Source Sans 3",
  black    = file.path(HERE, "fonts", "SourceSans3-Black.ttf"),
  bold     = file.path(HERE, "fonts", "SourceSans3-Bold.ttf"),
  semibold = file.path(HERE, "fonts", "SourceSans3-Semibold.ttf")
)

WORDMARK <- "BOSTON"


## ===========================================================================
## 2. Emblem geometry
## ===========================================================================
##
## The two edges of the bow are circular arcs. Their centres and radii are
## least-squares fits to the reference (mean residual 0.002-0.004 of the
## square's width). The bowstring and the arrow shaft are straight bands, the
## shaft tapering slightly towards its tail.

EMB <- list(
  bow_in  = list(cx = 1.145769, cy = -0.230424, r = 1.241243),
  bow_out = list(cx = 1.196134, cy = -0.299743, r = 1.299270),

  ## Bowstring: two parallel lines, x as a function of y.
  string_lo = c(a = -0.164940, b = 1.190260),   # upper-left edge
  string_hi = c(a = -0.148160, b = 1.184190),   # lower-right edge

  ## Arrow shaft edges, x as a function of y.
  arrow_ll = c(a = 0.934930, b = -0.935970),    # lower-left edge
  arrow_ur = c(a = 0.954410, b = -0.895400),    # upper-right edge

  ## Arrowhead: the long tip, its single barb, and the notch behind it.
  arrow_head = c(a = 2.347960, b = -2.430000),  # tip -> barb edge
  arrow_barb  = c(0.18000, 0.88850),
  arrow_notch = c(0.16560, 0.88100)
)

## Waterline: the emblem's arrow and bowstring stop here, the skyline stands on
## it, and the reflections begin below it.
WATER_Y <- 0.258

line_x <- function(k, y) k[["a"]] + k[["b"]] * y

#' x on a circular arc at a given y. The branch used is always the one to the
#' left of the centre, which is the side the bow is drawn on.
arc_x <- function(circ, y) {
  d2 <- circ$r^2 - (y - circ$cy)^2
  circ$cx - sqrt(pmax(d2, 0))
}

#' y where an arc crosses a given x (upper branch).
arc_y <- function(circ, x) circ$cy + sqrt(pmax(circ$r^2 - (x - circ$cx)^2, 0))

#' Sample an arc between two y values.
arc_pts <- function(circ, y0, y1, n = 360) {
  y <- seq(y0, y1, length.out = n)
  data.frame(x = arc_x(circ, y), y = y)
}

#' Clip a band defined by two x(y) edges to y >= floor, as a closed polygon.
band_poly <- function(lo, hi, y0, y1) {
  data.frame(
    x = c(line_x(lo, y0), line_x(lo, y1), line_x(hi, y1), line_x(hi, y0)),
    y = c(y0, y1, y1, y0)
  )
}

#' Every piece of the OHDSI mark, as a named list of polygons.
make_ohdsi_geometry <- function() {
  ## Where the arcs meet the square.
  y_in_left  <- arc_y(EMB$bow_in,  0)     # inner edge leaves the left border
  y_out_left <- arc_y(EMB$bow_out, 0)
  x_in_top   <- arc_x(EMB$bow_in,  1)     # inner edge leaves the top border
  y_out_right <- EMB$bow_out$cy + sqrt(EMB$bow_out$r^2 - (1 - EMB$bow_out$cx)^2)

  inner <- arc_pts(EMB$bow_in, y_in_left, 1)
  inner <- inner[inner$x <= 1, ]
  outer <- arc_pts(EMB$bow_out, y_out_right, y_out_left)

  ## Navy field: everything up and left of the bow's inner edge.
  navy <- rbind(inner, data.frame(x = c(0, 0), y = c(1, y_in_left)))

  ## The white bow, clipped by the left, top and right borders. The band wraps
  ## the top-right corner: its inner edge leaves through the top, its outer
  ## edge through the right, which is what leaves the small orange wedge there.
  bow <- rbind(
    inner,
    data.frame(x = c(1, 1), y = c(1, y_out_right)),
    outer,
    data.frame(x = 0, y = y_in_left)
  )

  ## Bowstring and arrow both stop at the waterline.
  string <- band_poly(EMB$string_lo, EMB$string_hi, WATER_Y,
                      (1 - EMB$string_lo[["a"]]) / EMB$string_lo[["b"]])
  string$x <- pmin(string$x, 1)

  tip_y <- (EMB$arrow_head[["a"]] - EMB$arrow_ll[["a"]]) /
           (EMB$arrow_ll[["b"]] - EMB$arrow_head[["b"]])
  tip_x <- line_x(EMB$arrow_ll, tip_y)

  arrow <- data.frame(
    x = c(line_x(EMB$arrow_ll, WATER_Y), tip_x, EMB$arrow_barb[1],
          EMB$arrow_notch[1], line_x(EMB$arrow_ur, WATER_Y)),
    y = c(WATER_Y, tip_y, EMB$arrow_barb[2], EMB$arrow_notch[2], WATER_Y)
  )

  list(navy = navy, bow = bow, string = string, arrow = arrow,
       square = data.frame(x = c(0, 1, 1, 0), y = c(0, 0, 1, 1)))
}


## ===========================================================================
## 3. Skyline geometry
## ===========================================================================
##
## Three groups, west to east: the Zakim bridge, the downtown towers, and
## Fenway Park. Positions were measured off the reference. Buildings are
## rectangles; everything else is an explicit polygon or a set of segments.

#' A rectangle standing on the waterline (or on a given base).
blk <- function(x0, x1, top, base = WATER_Y) {
  data.frame(x = c(x0, x1, x1, x0), y = c(base, base, top, top))
}

#' The Leonard P. Zakim Bunker Hill Bridge: one slender pylon and two fans of
#' stays. The pylon is a straight taper — a concave profile reads as a wine
#' glass rather than a tower — and the two fans are symmetric about it.
zakim <- function(cx = 0.2360, tip = 0.4900, deck = WATER_Y + 0.0020) {
  polys <- list()
  w_base <- 0.0125; w_neck <- 0.0052
  y_neck <- 0.4480
  polys$pylon <- data.frame(
    x = c(cx - w_base, cx + w_base, cx + w_neck, cx, cx - w_neck),
    y = c(deck, deck, y_neck, tip, y_neck)
  )
  ## Stays: nine a side, anchored down the upper pylon and landing on the
  ## deck at equal spacing either side of it.
  n <- 9
  ay     <- seq(0.4390, 0.3560, length.out = n)   # anchor heights
  land_l <- seq(0.0340, 0.1960, length.out = n)
  land_r <- seq(0.2760, 0.4380, length.out = n)
  hw <- 0.0017
  for (i in seq_len(n)) {
    polys[[paste0("stay_l", i)]] <- data.frame(
      x = c(cx - hw, cx + hw, land_l[i] + hw, land_l[i] - hw),
      y = c(ay[i], ay[i], deck, deck))
    polys[[paste0("stay_r", i)]] <- data.frame(
      x = c(cx - hw, cx + hw, land_r[i] + hw, land_r[i] - hw),
      y = c(ay[i], ay[i], deck, deck))
  }
  polys$deck <- blk(0.0300, 0.4480, deck + 0.0022, deck - 0.0030)
  polys
}

#' A dome on a stepped drum, with a lantern and a finial.
dome <- function(cx = 0.5195, rx = 0.0300, ry = 0.0615,
                 spring = 0.3330, spire = 0.4110) {
  th <- seq(0, pi, length.out = 90)
  list(
    base   = blk(cx - 0.0430, cx + 0.0430, spring - 0.018),
    drum   = blk(cx - 0.0330, cx + 0.0330, spring + 0.004),
    dome   = data.frame(x = cx + rx * cos(th), y = spring + ry * sin(th)),
    lantern = blk(cx - 0.0068, cx + 0.0068, spring + ry + 0.0075,
                  spring + ry - 0.002),
    finial = data.frame(
      x = c(cx - 0.0016, cx + 0.0016, cx + 0.0016, cx, cx - 0.0016),
      y = c(spring + ry + 0.0070, spring + ry + 0.0070,
            spire - 0.006, spire, spire - 0.006))
  )
}

#' Downtown: towers between the bridge and Fenway, plus the low-rise skirt.
#' The skirt matters — without small blocks and the orange gaps between them
#' the towers read as slabs rather than as a city.
downtown <- function() {
  list(
    ## --- mid-rise, west to east -------------------------------------------
    b1  = blk(0.2900, 0.3120, 0.3480),
    b2  = blk(0.3190, 0.3420, 0.3360),
    b3  = blk(0.3530, 0.3830, 0.3720),
    b4  = blk(0.3930, 0.4060, 0.2960),
    b5  = blk(0.4110, 0.4240, 0.4290),   # stepped tower, lower step
    b6  = blk(0.4280, 0.4650, 0.4380),   # stepped tower, main shaft
    b7  = blk(0.4760, 0.4890, 0.3200),
    b8  = blk(0.5520, 0.5640, 0.3250),

    ## --- Custom House: shaft, pointed crown, spire ------------------------
    ch  = blk(0.5820, 0.6240, 0.4460),
    ch_step  = blk(0.5880, 0.6180, 0.4620, 0.4460),
    ch_crown = data.frame(
      x = c(0.5880, 0.6180, 0.6030),
      y = c(0.4620, 0.4620, 0.4880)),
    ch_spire = blk(0.6015, 0.6045, 0.5000, 0.4840),

    ## --- Prudential: shaft, banded crown, roof box, mast ------------------
    pr        = blk(0.6500, 0.7180, 0.5240),
    pr_crown  = blk(0.6440, 0.7240, 0.5510, 0.5240),
    pr_roof   = blk(0.6760, 0.6990, 0.5620, 0.5520),
    pr_mast   = blk(0.6860, 0.6890, 0.5956, 0.5620),

    ## --- low-rise skirt ---------------------------------------------------
    s01 = blk(0.2680, 0.2830, 0.2890),
    s02 = blk(0.3140, 0.3170, 0.3150),
    s03 = blk(0.3900, 0.3930, 0.3210),
    s04 = blk(0.4070, 0.4100, 0.3060),
    s05 = blk(0.4700, 0.4750, 0.2980),
    s06 = blk(0.4930, 0.5050, 0.3000),
    s07 = blk(0.5060, 0.5140, 0.2950),
    s08 = blk(0.5660, 0.5800, 0.3060),
    s09 = blk(0.6250, 0.6420, 0.3080),
    s10 = blk(0.6280, 0.6450, 0.2950),
    s11 = blk(0.7210, 0.7330, 0.3220),
    s12 = blk(0.7340, 0.7450, 0.2980),
    s13 = blk(0.7550, 0.7680, 0.3830),
    s14 = blk(0.7680, 0.7760, 0.3120),
    s15 = blk(0.8060, 0.8180, 0.3340),
    s16 = blk(0.8820, 0.8960, 0.3320),
    s17 = blk(0.9120, 0.9280, 0.3300),
    s18 = blk(0.9800, 0.9940, 0.3360)
  )
}

#' Fenway Park: two light towers, the trussed sign gantry and the grandstand.
fenway <- function() {
  ## Measured bulb-bank spans: 0.768-0.817 and 0.910-0.973.
  ## `r` is the bulb radius; bulbs are spaced 2.1r so they read as separate
  ## lamps rather than a cloud. The masts stop where they meet the gantry —
  ## carrying them further down puts lattice behind the FENWAY PARK sign and
  ## swallows the first letter.
  towers <- list(
    list(cx = 0.7925, top = 0.4790, cols = 6, rows = 3, r = 0.0039,
         mast_top = 0.4470, mast_bot = 0.3830, w0 = 0.0060, w1 = 0.0125),
    list(cx = 0.9415, top = 0.5180, cols = 7, rows = 4, r = 0.0043,
         mast_top = 0.4780, mast_bot = 0.4000, w0 = 0.0068, w1 = 0.0150)
  )
  gantry <- list(x0 = 0.7480, x1 = 1.0000,
                 y0 = 0.4010, y1 = 0.4210, depth = 0.0205)
  list(towers = towers, gantry = gantry,
       sign  = list(x = 0.8780, width = 0.1400, y = 0.3600),
       stand = list(top = 0.3180, x0 = 0.7800, x1 = 1.0000))
}

## ===========================================================================
## 4. Water
## ===========================================================================

#' The harbour.
#'
#' A reflection is not noise: it is the skyline again, upside down and broken
#' into ripples. So the strokes are organised into vertical columns sitting
#' directly under the things that cast them — the pylon, the tower blocks, the
#' light masts — with a thin scatter of longer streaks between them. Each
#' stroke is a lens (a bar with tapered ends), because a plain rectangle reads
#' as a dash and a tapered one reads as a glint. Seeded, so the badge is
#' identical on every run.
make_water <- function(seed = 20260919) {
  set.seed(seed)
  out <- list(); k <- 0
  top <- WATER_Y - 0.008
  bot <- 0.020

  ## Strokes are clamped to the art square: anything wider paints over the
  ## keyline, because the panel clips to the canvas, not to the artwork.
  lens <- function(x0, x1, y, t) {
    x0 <- max(x0, 0); x1 <- min(x1, 1)
    if (x1 - x0 < 1e-4) return(NULL)
    taper <- min((x1 - x0) * 0.42, t * 4.2)
    data.frame(
      x = c(x0, x0 + taper, x1 - taper, x1, x1 - taper, x0 + taper),
      y = c(y, y + t, y + t, y, y - t, y - t))
  }
  add <- function(df) { if (is.null(df)) return(invisible()); k <<- k + 1; out[[k]] <<- cbind(df, id = k) }

  ## The shoreline: a thin, mostly unbroken bar the skyline stands on.
  for (seg in list(c(0.000, 0.352), c(0.362, 0.639), c(0.648, 1.000))) {
    add(lens(seg[1], seg[2], top, 0.0022))
  }

  ## What casts a reflection: centre, half-width and how far down it carries.
  sources <- list(
    c(0.2360, 0.0160, 1.00),   # bridge pylon
    c(0.1100, 0.0700, 0.55),   # west stay fan
    c(0.3600, 0.0700, 0.55),   # east stay fan
    c(0.3060, 0.0260, 0.70),
    c(0.3690, 0.0210, 0.80),
    c(0.4450, 0.0230, 0.90),
    c(0.5195, 0.0330, 0.85),
    c(0.6030, 0.0220, 0.80),
    c(0.6840, 0.0400, 1.00),   # Prudential
    c(0.7925, 0.0180, 0.75),   # light tower west
    c(0.8700, 0.0600, 0.85),   # grandstand
    c(0.9415, 0.0200, 0.75),   # light tower east
    c(0.0700, 0.0400, 0.40),
    c(0.1700, 0.0320, 0.50),
    c(0.4100, 0.0240, 0.70),
    c(0.4800, 0.0200, 0.60),
    c(0.5700, 0.0200, 0.60),
    c(0.7400, 0.0260, 0.70),
    c(0.8300, 0.0220, 0.60),
    c(0.9800, 0.0220, 0.55)
  )

  ## The ripple field. Marks are stacked into tight vertical columns under
  ## each source, alternating left and right so the column reads as a zigzag,
  ## with clean orange between columns. A solid white field reads as ice.
  rows <- 15
  dy   <- 0.0060
  for (i in seq_len(rows)) {
    t <- (i - 1) / (rows - 1)
    y <- (top - 0.021) - (i - 1) * dy
    thick <- 0.0027 * (1 - 0.25 * t)
    for (si in seq_along(sources)) {
      src <- sources[[si]]
      if (t > src[3]) next
      if (stats::runif(1) > 0.88 - 0.30 * t) next
      half <- src[2] * (0.40 + 0.60 * stats::runif(1)) * (1 - 0.20 * t)
      swing <- if ((i + si) %% 2 == 0) 1 else -1
      cxj <- src[1] + swing * src[2] * (0.20 + 0.30 * stats::runif(1))
      add(lens(cxj - half, cxj + half, y, thick))
    }
    ## Long streaks, mostly near the shore, tying the columns together.
    for (j in seq_len(if (i <= 5) 3 else 1)) {
      if (stats::runif(1) > 0.70) next
      len <- 0.030 + 0.150 * stats::runif(1)^1.8
      x0  <- stats::runif(1, -0.02, 1.00)
      add(lens(x0, x0 + len, y, thick * 0.8))
    }
  }

  ## A quiet tail of far ripples behind and below the wordmark.
  for (i in seq_len(9)) {
    y <- (top - 0.021) - (rows - 1) * dy - i * 0.0115
    if (y < bot) break
    for (j in seq_len(3)) {
      if (stats::runif(1) > 0.62) next
      len <- 0.025 + 0.130 * stats::runif(1)^1.8
      x0  <- stats::runif(1, -0.02, 1.00)
      add(lens(x0, x0 + len, y, 0.0021))
    }
  }
  do.call(rbind, out)
}


## ===========================================================================
## 5. Fonts
## ===========================================================================

ensure_fonts <- function(install_for_fontconfig = TRUE) {
  files <- c(FONT$black, FONT$bold, FONT$semibold)
  if (!all(file.exists(files))) {
    warning("Bundled fonts not found; falling back to a system sans face.")
    FONT$family <<- "sans"
    return(invisible(FALSE))
  }
  try(systemfonts::register_font(
    FONT$family,
    plain = FONT$semibold, bold = FONT$bold,
    italic = FONT$semibold, bolditalic = FONT$bold), silent = TRUE)
  try(systemfonts::register_font(
    "Source Sans 3 Black", plain = FONT$black, bold = FONT$black,
    italic = FONT$black, bolditalic = FONT$black), silent = TRUE)
  if (install_for_fontconfig && .Platform$OS.type == "unix") {
    dest <- path.expand("~/.local/share/fonts/ohdsi-boston")
    if (!dir.exists(dest)) dir.create(dest, recursive = TRUE)
    for (f in files) {
      tgt <- file.path(dest, basename(f))
      if (!file.exists(tgt)) file.copy(f, tgt)
    }
    suppressWarnings(try(system2("fc-cache", c("-f", shQuote(dest)),
                                 stdout = FALSE, stderr = FALSE), silent = TRUE))
  }
  invisible(TRUE)
}

cap_ratio <- function(family, bold = FALSE) {
  systemfonts::glyph_info("H", family = family, bold = bold, size = 1000)$height / 1000
}

advance_width <- function(s, size, family, bold = FALSE) {
  systemfonts::shape_string(s, family = family, bold = bold, size = size)$metrics$width
}


## ===========================================================================
## 6. Drawing
## ===========================================================================

poly_layer <- function(df, fill, alpha = 1) {
  ggplot2::geom_polygon(data = df, ggplot2::aes(x, y), fill = fill,
                        colour = NA, alpha = alpha, inherit.aes = FALSE)
}

poly_layers <- function(lst, fill) lapply(lst, poly_layer, fill = fill)

#' The orange field, as a real vector gradient (kept as a gradient in SVG/PDF).
orange_gradient_grob <- function() {
  grid::rectGrob(gp = grid::gpar(col = NA, fill = grid::linearGradient(
    colours = c(COL$orange_dark, COL$orange_mid, COL$orange_light),
    stops   = c(0, 0.52, 1),
    x1 = grid::unit(GRADIENT$from[1], "npc"), y1 = grid::unit(GRADIENT$from[2], "npc"),
    x2 = grid::unit(GRADIENT$to[1],   "npc"), y2 = grid::unit(GRADIENT$to[2],   "npc"))))
}

draw_ohdsi_symbol <- function(geom) {
  c(list(poly_layer(geom$navy, COL$navy)),
    poly_layers(list(geom$bow, geom$string, geom$arrow), COL$white))
}

#' A filled circle.
disc <- function(cx, cy, r, n = 26) {
  th <- seq(0, 2 * pi, length.out = n + 1)[-(n + 1)]
  data.frame(x = cx + r * cos(th), y = cy + r * sin(th))
}

#' A four-pointed sparkle, used between the bulbs of a light bank.
sparkle <- function(cx, cy, r) {
  k <- r * 0.30
  data.frame(
    x = c(cx, cx + k, cx + r, cx + k, cx, cx - k, cx - r, cx - k),
    y = c(cy + r, cy + k, cy, cy - k, cy - r, cy - k, cy, cy + k))
}

#' A tapering lattice mast: two legs plus X bracing.
lattice_mast <- function(cx, y_top, y_bot, w_top, w_bot, bays = 5,
                         leg = 0.0028, brace = 0.0024) {
  wat <- function(y) w_bot + (w_top - w_bot) * (y - y_bot) / (y_top - y_bot)
  out <- list(
    data.frame(x = c(cx - wat(y_top), cx - wat(y_top) + leg,
                     cx - wat(y_bot) + leg, cx - wat(y_bot)),
               y = c(y_top, y_top, y_bot, y_bot)),
    data.frame(x = c(cx + wat(y_top) - leg, cx + wat(y_top),
                     cx + wat(y_bot), cx + wat(y_bot) - leg),
               y = c(y_top, y_top, y_bot, y_bot)))
  ys <- seq(y_top, y_bot, length.out = bays + 1)
  for (i in seq_len(bays)) {
    y0 <- ys[i]; y1 <- ys[i + 1]
    out <- c(out, list(
      data.frame(x = c(cx - wat(y0), cx - wat(y0) + brace,
                       cx + wat(y1), cx + wat(y1) - brace),
                 y = c(y0, y0, y1, y1)),
      data.frame(x = c(cx + wat(y0), cx + wat(y0) - brace,
                       cx - wat(y1), cx - wat(y1) + brace),
                 y = c(y0, y0, y1, y1))))
  }
  out
}

#' Everything white that stands on the waterline.
draw_skyline <- function(gradient_fill = COL$orange_mid) {
  fw <- fenway()
  layers <- list()

  layers <- c(layers, poly_layers(zakim(), COL$white))
  layers <- c(layers, poly_layers(downtown(), COL$white))
  layers <- c(layers, poly_layers(dome(), COL$white))

  ## Two orange rules through the Prudential crown, so the band reads as the
  ## tower's louvred top rather than a plain box.
  for (yy in c(0.5330, 0.5430)) {
    layers <- c(layers, list(poly_layer(
      blk(0.6440, 0.7240, yy + 0.0028, yy), gradient_fill)))
  }

  ## --- Fenway light towers: banks of bulbs, no backing plate --------------
  for (t in fw$towers) {
    r  <- t$r
    sp <- r * 2.10
    xs <- seq(t$cx - (t$cols - 1) / 2 * sp,
              t$cx + (t$cols - 1) / 2 * sp, length.out = t$cols)
    ys <- seq(t$top - r, t$top - r - (t$rows - 1) * sp, length.out = t$rows)
    for (xx in xs) for (yy in ys) {
      layers <- c(layers, list(poly_layer(disc(xx, yy, r), COL$white)))
    }
    for (i in seq_len(t$cols - 1)) for (j in seq_len(t$rows - 1)) {
      layers <- c(layers, list(poly_layer(
        sparkle((xs[i] + xs[i + 1]) / 2, (ys[j] + ys[j + 1]) / 2, r * 0.62),
        COL$white)))
    }
    ## a short neck joining the bank to the mast
    layers <- c(layers, list(poly_layer(
      blk(t$cx - t$w0 - 0.0028, t$cx + t$w0 + 0.0028,
          ys[t$rows] - r, t$mast_top), COL$white)))
    layers <- c(layers, poly_layers(
      lattice_mast(t$cx, t$mast_top, t$mast_bot, t$w0, t$w1, bays = 6),
      COL$white))
  }

  ## --- the sign gantry ----------------------------------------------------
  g  <- fw$gantry
  gy <- function(x) g$y0 + (g$y1 - g$y0) * (x - g$x0) / (g$x1 - g$x0)
  chord <- 0.0036
  layers <- c(layers, list(
    poly_layer(data.frame(
      x = c(g$x0, g$x1, g$x1, g$x0),
      y = c(gy(g$x0), gy(g$x1), gy(g$x1) - chord, gy(g$x0) - chord)), COL$white),
    poly_layer(data.frame(
      x = c(g$x0, g$x1, g$x1, g$x0),
      y = c(gy(g$x0) - g$depth + chord, gy(g$x1) - g$depth + chord,
            gy(g$x1) - g$depth, gy(g$x0) - g$depth)), COL$white)))
  nx <- 26
  xs <- seq(g$x0, g$x1, length.out = nx + 1)
  bw <- 0.0021
  for (i in seq_len(nx)) {
    x0 <- xs[i]; x1 <- xs[i + 1]
    layers <- c(layers, list(
      poly_layer(data.frame(
        x = c(x0, x0 + bw, x1 + bw, x1),
        y = c(gy(x0) - chord, gy(x0) - chord,
              gy(x1) - g$depth + chord, gy(x1) - g$depth + chord)), COL$white),
      poly_layer(data.frame(
        x = c(x0, x0 + bw, x1 + bw, x1),
        y = c(gy(x0) - g$depth + chord, gy(x0) - g$depth + chord,
              gy(x1) - chord, gy(x1) - chord)), COL$white)))
  }
  ## Hanger boxes and their drops.
  for (x in c(0.7760, 0.9040)) {
    layers <- c(layers, list(
      poly_layer(blk(x - 0.0018, x + 0.0018, gy(x) - g$depth, 0.3320), COL$white),
      poly_layer(blk(x - 0.0058, x + 0.0058, gy(x) - g$depth - 0.0060,
                     gy(x) - g$depth - 0.0190), COL$white)))
  }

  ## --- grandstand ---------------------------------------------------------
  st <- fw$stand
  layers <- c(layers, poly_layers(list(
    blk(st$x0,  0.8180, st$top - 0.014),
    blk(0.8180, 0.9460, st$top),
    blk(0.9460, 0.9760, st$top - 0.020),
    blk(0.9760, st$x1,  st$top - 0.006),
    blk(0.7560, 0.7800, 0.2980),
    blk(0.7380, 0.7560, 0.2860)
  ), COL$white))
  ## The panel's triangular cut-out and the notches between sections.
  layers <- c(layers, list(poly_layer(data.frame(
    x = c(0.8600, 0.9060, 0.8830),
    y = c(0.2790, 0.2790, 0.3040)), gradient_fill)))
  for (nx2 in c(0.8180, 0.9460)) {
    layers <- c(layers, list(poly_layer(
      blk(nx2 - 0.0022, nx2 + 0.0022, st$top - 0.026, WATER_Y + 0.004),
      gradient_fill)))
  }
  layers
}

#' The BOSTON wordmark, its flanking rules, and the FENWAY PARK sign.
#'
#' Both lines are sized by their INKED width, not their advance width: side
#' bearings are a property of the font, not of the drawing, and sizing by
#' advance leaves the letters visibly narrower than the measured target. The
#' type is only ever scaled uniformly - never condensed to fit.
draw_lettering <- function(pt_per_unit) {
  black <- "Source Sans 3 Black"

  #' Point size at which a string's inked width is exactly `target` units.
  size_for_ink <- function(txt, target, family, bold = FALSE) {
    m <- systemfonts::shape_string(txt, family = family, bold = bold, size = 1000)$metrics
    ink <- m$width - m$left_bearing - m$right_bearing
    1000 * target * pt_per_unit / ink
  }

  ## --- BOSTON --------------------------------------------------------------
  ## The reference's face is wider per unit height than Source Sans 3 Black,
  ## so matching its width alone would leave the letters 20% too tall. Instead
  ## the cap height is matched and the line is TRACKED out to the measured
  ## width: every glyph keeps its own proportions, and only the spaces between
  ## them change.
  ## Matching the reference's width exactly would open the tracking to twice
  ## what a logotype wants, because this face is the narrower of the two. The
  ## cap height is matched and the width pulled in a little, which keeps the
  ## letter rhythm tight.
  cap_h    <- 0.0920
  ink_w    <- 0.6000
  baseline <- 0.0600

  size_w <- cap_h * pt_per_unit / cap_ratio(black)
  chars  <- strsplit(WORDMARK, "")[[1]]
  adv    <- vapply(chars, function(ch)
    systemfonts::shape_string(ch, family = black, size = size_w)$metrics$width,
    numeric(1)) / pt_per_unit
  m    <- systemfonts::shape_string(WORDMARK, family = black, size = size_w)$metrics
  natural_ink <- (m$width - m$left_bearing - m$right_bearing) / pt_per_unit
  track <- (ink_w - natural_ink) / (length(chars) - 1)
  lsb   <- m$left_bearing / pt_per_unit

  x0     <- 0.5 - ink_w / 2 - lsb
  starts <- x0 + cumsum(c(0, utils::head(adv, -1))) + track * (seq_along(chars) - 1)
  word   <- data.frame(label = chars, x = starts + adv / 2, stringsAsFactors = FALSE)

  ## The rules sit on the letters' optical centre and stop short of B and N.
  rule_y <- baseline + cap_h * 0.44
  rule_h <- 0.0060
  gap    <- 0.0320

  ## --- FENWAY PARK ---------------------------------------------------------
  sign_size <- size_for_ink("FENWAY PARK", 0.1400, FONT$family, bold = TRUE)

  list(
    ggplot2::geom_text(data = word, ggplot2::aes(x = x, y = baseline, label = label),
                       family = black, colour = COL$white,
                       size = size_w / .pt, hjust = 0.5, vjust = 0,
                       inherit.aes = FALSE),
    poly_layer(blk(0.0180, 0.5 - ink_w / 2 - gap, rule_y + rule_h, rule_y), COL$white),
    poly_layer(blk(0.5 + ink_w / 2 + gap, 0.9820, rule_y + rule_h, rule_y), COL$white),
    ggplot2::annotate("text", x = 0.8780, y = 0.3600, label = "FENWAY PARK",
                      family = FONT$family, fontface = "bold",
                      colour = COL$white, size = sign_size / .pt,
                      hjust = 0.5, vjust = 0.5)
  )
}


## ===========================================================================
## 7. Assembly
## ===========================================================================

#' Build the badge.
#' @param variant "badge" for the full artwork; "mark" for the emblem, skyline
#'   and harbour without the wordmark or keyline; "emblem" for the OHDSI mark
#'   alone, which is the only one that survives being shown at favicon size.
build_logo <- function(variant = c("badge", "mark", "emblem"), canvas = CANVAS,
                       out = OUT, frame = NULL) {
  variant <- match.arg(variant)
  ensure_fonts()

  ## The keyline belongs to the badge as a standalone object; on a coloured
  ## page it just boxes the artwork in, so it can be switched off.
  f <- if (!is.null(frame)) frame else if (variant == "badge") canvas$frame else 0
  lim <- c(-f, 1 + f)
  pt_per_unit <- (out$width / (1 + 2 * f)) * 72

  geom <- make_ohdsi_geometry()

  p <- ggplot2::ggplot() +
    ggplot2::annotation_custom(orange_gradient_grob(), 0, 1, 0, 1) +
    draw_ohdsi_symbol(geom)

  if (variant != "emblem") {
    p <- p + draw_skyline() +
      ggplot2::geom_polygon(
        data = make_water(), ggplot2::aes(x, y, group = id),
        fill = COL$white, colour = NA, inherit.aes = FALSE)
  }
  if (variant == "badge") p <- p + draw_lettering(pt_per_unit)

  p <- p +
    ggplot2::coord_fixed(xlim = lim, ylim = lim, expand = FALSE, clip = "on") +
    ggplot2::theme_void() +
    ggplot2::theme(
      plot.background  = ggplot2::element_rect(
        fill = if (f > 0) COL$frame else COL$white, colour = NA),
      panel.background = ggplot2::element_rect(
        fill = if (f > 0) COL$frame else COL$white, colour = NA),
      plot.margin = ggplot2::margin(0, 0, 0, 0),
      legend.position = "none")

  attr(p, "side") <- 1 + 2 * f
  p
}

save_logo <- function(variant = "badge", stem = OUT$stem, out = OUT, frame = NULL) {
  p <- build_logo(variant, frame = frame)
  framed <- attr(p, "side") > 1
  w <- out$width; h <- w
  bg <- if (framed) COL$frame else COL$white

  ragg::agg_png(paste0(stem, ".png"), width = w, height = h, units = "in",
                res = out$dpi, background = bg)
  print(p); grDevices::dev.off()

  svglite::svglite(paste0(stem, ".svg"), width = w, height = h, bg = bg)
  print(p); grDevices::dev.off()

  grDevices::cairo_pdf(paste0(stem, ".pdf"), width = w, height = h, bg = bg)
  print(p); grDevices::dev.off()

  invisible(paste0(stem, c(".png", ".svg", ".pdf")))
}

#' The white skyline on its own, for use as a band across a dark panel.
#' `cut_fill` is what the punched-out shapes (the ballpark triangle, the
#' notches, the tower louvres) are filled with, so it must match the panel the
#' band will sit on.
save_skyline <- function(file, cut_fill = "#12293E", width = 12, dpi = 300,
                         y0 = 0.2540, y1 = 0.6050) {
  ensure_fonts()
  p <- ggplot2::ggplot() +
    draw_skyline(gradient_fill = cut_fill) +
    ggplot2::coord_fixed(xlim = c(0, 1), ylim = c(y0, y1), expand = FALSE, clip = "on") +
    ggplot2::theme_void() +
    ggplot2::theme(plot.margin = ggplot2::margin(0, 0, 0, 0),
                   legend.position = "none")
  h <- width * (y1 - y0)
  svglite::svglite(file, width = width, height = h, bg = "transparent")
  print(p); grDevices::dev.off()
  invisible(file)
}

#' Everything the repository and the website need, in one pass.
save_all <- function() {
  assets <- file.path(HERE, "docs", "assets")
  if (!dir.exists(assets)) dir.create(assets, recursive = TRUE)

  files <- save_logo("badge")

  ## The badge again, for the site, plus the emblem-and-skyline mark that
  ## stays legible at favicon size.
  ## For the website: the badge without its keyline, the emblem-and-skyline
  ## mark, the emblem alone (the only one legible at favicon size), and the
  ## skyline on its own for the page's horizon band.
  save_logo("badge",  stem = file.path(assets, "logo"),  frame = 0)
  save_logo("mark",   stem = file.path(assets, "badge"))
  save_logo("emblem", stem = file.path(assets, "mark"))
  save_skyline(file.path(assets, "skyline.svg"))

  for (f in c("logo", "badge", "mark")) unlink(file.path(assets, paste0(f, ".pdf")))
  unlink(file.path(assets, "badge.png"))
  invisible(files)
}

if (sys.nframe() == 0L || !interactive()) {
  files <- save_all()
  message("Wrote:\n  ", paste(files, collapse = "\n  "),
          "\n  docs/assets/{logo,badge,mark}.svg, logo.png, mark.png, skyline.svg")
}
