## ---------------------------------------------------------------------------
## ohdsi_boston_logo.R
##
## A reproducible, vector-quality OHDSI-Boston logo built entirely in R.
##
## The emblem (navy square + bow / bowstring / arrow) is reconstructed as
## analytic vector geometry in a normalised 0..1 "emblem" coordinate system.
## The orange half of the emblem doubles as the lit surface of a globe: an
## orthographic projection centred on Massachusetts Bay places Boston, Cape Cod
## Bay and the hook of Cape Cod inside the orange field as a low-contrast
## tonal texture.
##
##   Reading order by design:  OHDSI first, Boston second, map third.
##
## Usage:  Rscript ohdsi_boston_logo.R
## ---------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(ggplot2)
  library(grid)
  library(sf)
  library(systemfonts)
})

sf::sf_use_s2(FALSE)

HERE <- tryCatch({
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grep("^--file=", a)])
  if (length(f)) dirname(normalizePath(f)) else getwd()
}, error = function(e) getwd())


## ===========================================================================
## 1. Configuration
## ===========================================================================

## --- Palette (sampled from the reference artwork) --------------------------
COL <- list(
  navy          = "#1A3C5B",  # OHDSI dark navy
  orange_dark   = "#EF7F1B",  # upper-left end of the orange field
  orange_mid    = "#F79C1B",
  orange_light  = "#FDC50D",  # lower-right end (yellow-orange)
  white         = "#FFFFFF",
  background    = "#FFFFFF",
  text          = "#1A3C5B"
)

## Geography is drawn only as tonal variation of the orange field: land is a
## veil of white over the gradient, never a separate hue.
GEO <- list(
  land_fill     = "#FFFFFF",
  land_alpha    = 0.14,
  coast_col     = "#FFFFFF",
  coast_alpha   = 0.70,
  coast_lwd     = 0.26,
  graticule_col = "#FFFFFF",
  graticule_alpha = 0.045,
  graticule_lwd = 0.30,
  boston_alpha  = 0.55,
  boston_r      = 0.0085   # emblem units
)

## --- Globe / map framing ---------------------------------------------------
## Orthographic projection centred on Massachusetts Bay. MAP_SPAN_KM is the
## ground distance covered by one full emblem side, and MAP_ANCHOR is where the
## projection centre lands inside the emblem square.
MAP <- list(
  lon0      = -71.000,
  lat0      =  42.073,
  span_km   = 245,
  anchor_x  = 0.500,
  anchor_y  = 0.500,
  grat_lon  = 1.0,   # degrees between meridians
  grat_lat  = 1.0    # degrees between parallels
)

## --- Typography ------------------------------------------------------------
## Source Sans 3 is the closest open counterpart to the humanist sans of the
## OHDSI wordmark.  The faces are registered under their real family name so
## that every device - ragg and svglite (systemfonts registry) as well as the
## cairo PDF device (fontconfig) - resolves the same outlines.
FONT <- list(
  family   = "Source Sans 3",
  bold     = file.path(HERE, "fonts", "SourceSans3-Bold.ttf"),
  semibold = file.path(HERE, "fonts", "SourceSans3-Semibold.ttf")
)

## The wordmark is set bold, the subtitle semibold (registered as the "plain"
## face of the same family).
FACE_WORD <- list(family = FONT$family, bold = TRUE)
FACE_SUB  <- list(family = FONT$family, bold = FALSE)

## --- Layout, in "logo units" where the emblem square has side 1 -------------
## Ratios were measured off the reference artwork (emblem width = 921 px).
LAYOUT <- list(
  margin          = 0.050,
  gap_emblem_word = 0.055,   # emblem bottom -> wordmark cap top
  word_width      = 1.080,   # wordmark advance width (never squashed: this
                             # only picks the font SIZE, not an x-scale)
  gap_word_sub    = 0.038,   # wordmark baseline -> subtitle cap top
  sub_smallcap    = 0.780,   # small-cap size as a fraction of the large cap
  sub_width       = 1.000,
  sub_tracking    = 0.072    # extra tracking, as a fraction of the cap height
)

WORDMARK <- "OHDSI-Boston"
SUBTITLE <- "Observational Health Data Sciences and Informatics"

## --- Output ----------------------------------------------------------------
OUT <- list(
  stem   = file.path(HERE, "ohdsi_boston_logo"),
  width  = 6.0,     # inches
  dpi    = 400
)


## ===========================================================================
## 2. Fonts
## ===========================================================================

#' Make the bundled Source Sans 3 faces available to every graphics device.
#'
#' svglite/ragg read the systemfonts registry directly; the cairo devices go
#' through fontconfig, so the faces are also linked into the user font
#' directory (a no-op once present).
ensure_fonts <- function(install_for_fontconfig = TRUE) {
  if (!all(file.exists(FONT$bold, FONT$semibold))) {
    warning("Bundled fonts not found; falling back to a system sans face.")
    FONT$family  <<- "sans"
    FACE_WORD    <<- list(family = "sans", bold = TRUE)
    FACE_SUB     <<- list(family = "sans", bold = FALSE)
    return(invisible(FALSE))
  }
  ## Registering under the real family name makes systemfonts-backed devices
  ## use the bundled files.  If the faces are already installed system-wide
  ## (see below) systemfonts refuses the registration - which is fine, because
  ## the system copies are the same files.
  try(systemfonts::register_font(
    FONT$family,
    plain  = FONT$semibold, bold       = FONT$bold,
    italic = FONT$semibold, bolditalic = FONT$bold
  ), silent = TRUE)
  if (install_for_fontconfig && .Platform$OS.type == "unix") {
    dest <- path.expand("~/.local/share/fonts/ohdsi-boston")
    if (!dir.exists(dest)) dir.create(dest, recursive = TRUE)
    for (f in c(FONT$bold, FONT$semibold)) {
      tgt <- file.path(dest, basename(f))
      if (!file.exists(tgt)) file.copy(f, tgt)
    }
    suppressWarnings(try(system2("fc-cache", c("-f", shQuote(dest)),
                                 stdout = FALSE, stderr = FALSE), silent = TRUE))
  }
  invisible(TRUE)
}

#' Cap height of a face, expressed as a fraction of the font size.
cap_ratio <- function(face = FACE_WORD) {
  systemfonts::glyph_info("H", family = face$family, bold = face$bold,
                          size = 1000)$height / 1000
}


## ===========================================================================
## 3. OHDSI emblem geometry
## ===========================================================================
##
## Everything below lives in the normalised emblem square x = 0..1, y = 0..1
## (y pointing up).  The two edges of the sweeping "bow" are, to within a
## quarter of a percent of the square's width, concentric-free circular arcs;
## their centres/radii were least-squares fitted to the reference artwork.
## The bowstring and the arrow shaft are straight bands, the arrow shaft
## tapering slightly towards its tail.

EMB <- list(
  ## bow: inner (navy-side) and outer edges
  bow_in  = list(cx = 1.126372, cy = -0.125025, r = 1.142482),
  bow_out = list(cx = 1.331758, cy = -0.318922, r = 1.360288),
  ## bowstring: x = y + string_c, half-width measured horizontally
  string_c  = 0.01290,
  string_hw = 0.00785,
  ## arrow shaft edges, x as a function of y (lower-left and upper-right)
  arrow_ll = c(a = 0.947970, b = -0.928200),
  arrow_ur = c(a = 0.969780, b = -0.878800),
  ## arrowhead
  arrow_tip   = c(0.06610, 0.95010),
  arrow_barb  = c(0.22300, 0.88900),
  arrow_notch = c(0.19640, 0.88000)
)

#' Sample a circular arc between two y values, returning the x on the arc.
#' The relevant branch is always the one to the LEFT of the circle centre.
arc_x <- function(circ, y) {
  d2 <- circ$r^2 - (y - circ$cy)^2
  d2[d2 < 0] <- 0
  circ$cx - sqrt(d2)
}

#' y at which an arc crosses a given x (upper branch).
arc_y_at_x <- function(circ, x) {
  circ$cy + sqrt(pmax(circ$r^2 - (x - circ$cx)^2, 0))
}

#' x at which an arc crosses a given y, and vice versa, for the square's edges.
arc_polyline <- function(circ, y_from, y_to, n = 400) {
  y <- seq(y_from, y_to, length.out = n)
  data.frame(x = arc_x(circ, y), y = y)
}

line_x <- function(coef, y) coef[["a"]] + coef[["b"]] * y

#' All emblem polygons, as a named list of data.frame(x, y).
make_ohdsi_geometry <- function() {
  ## Where the bow edges meet the square.
  y_in_left  <- arc_y_at_x(EMB$bow_in, 0)          # inner edge x left border
  x_in_top   <- arc_x(EMB$bow_in, 1)               # inner edge x top border
  x_out_top  <- arc_x(EMB$bow_out, 1)
  x_out_bot  <- arc_x(EMB$bow_out, 0)

  inner <- arc_polyline(EMB$bow_in, y_in_left, 1)
  outer <- arc_polyline(EMB$bow_out, 1, 0)
  outer <- outer[outer$x >= 0, ]

  ## Navy field: everything up-and-left of the bow's inner edge.
  navy <- rbind(
    inner,
    data.frame(x = c(0, 0), y = c(1, y_in_left))
  )

  ## The white bow band, clipped by the left and bottom edges of the square.
  bow <- rbind(
    inner,
    data.frame(x = c(x_out_top), y = c(1)),
    outer,
    data.frame(x = c(0, 0), y = c(0, y_in_left))
  )

  ## Bowstring: a thin straight band running corner to corner, clipped at the
  ## right edge of the square.
  s_up <- function(y) y + EMB$string_c - EMB$string_hw
  s_lo <- function(y) y + EMB$string_c + EMB$string_hw
  y_up1 <- 1 - EMB$string_c + EMB$string_hw   # upper edge reaches x = 1
  y_lo1 <- 1 - EMB$string_c - EMB$string_hw
  string <- data.frame(
    x = c(s_up(0), 1, 1, s_lo(0)),
    y = c(0,      y_up1, y_lo1, 0)
  )

  ## Arrow: tapered shaft plus a single-barbed head, clipped at the bottom.
  arrow <- data.frame(
    x = c(line_x(EMB$arrow_ll, 0), EMB$arrow_tip[1], EMB$arrow_barb[1],
          EMB$arrow_notch[1], line_x(EMB$arrow_ur, 0)),
    y = c(0, EMB$arrow_tip[2], EMB$arrow_barb[2], EMB$arrow_notch[2], 0)
  )

  list(navy = navy, bow = bow, string = string, arrow = arrow,
       square = data.frame(x = c(0, 1, 1, 0), y = c(0, 0, 1, 1)))
}

#' The orange field as an sf polygon: the square minus the navy region.
#' Used only to clip the geography, never drawn directly (the gradient is a
#' full-square rectangle that the navy and white shapes are painted over).
orange_field_sf <- function(geom) {
  sq <- sf::st_polygon(list(as.matrix(rbind(geom$square, geom$square[1, ]))))
  nv <- sf::st_polygon(list(as.matrix(rbind(geom$navy, geom$navy[1, ]))))
  sf::st_make_valid(sf::st_difference(sf::st_make_valid(sq), sf::st_make_valid(nv)))
}


## ===========================================================================
## 4. Geography
## ===========================================================================

#' Coastline of the wider Boston region as an sf polygon in EPSG:4326.
#'
#' Uses the cached Natural Earth 1:10m extract shipped with this repository and
#' falls back to downloading it if the cache is missing, so the script runs
#' offline once it has run online.
get_boston_geography <- function(
    cache = file.path(HERE, "data-cache", "ne10_northeast_land.geojson"),
    bbox = c(xmin = -73.8, ymin = 40.3, xmax = -68.3, ymax = 44.6)) {

  if (!file.exists(cache)) {
    message("Cache miss - downloading Natural Earth 1:10m admin-1 states ...")
    dir.create(dirname(cache), showWarnings = FALSE, recursive = TRUE)
    url <- paste0("https://naturalearth.s3.amazonaws.com/10m_cultural/",
                  "ne_10m_admin_1_states_provinces.zip")
    zipf <- tempfile(fileext = ".zip")
    utils::download.file(url, zipf, mode = "wb", quiet = TRUE)
    dir <- tempfile(); dir.create(dir); utils::unzip(zipf, exdir = dir)
    shp <- list.files(dir, pattern = "\\.shp$", full.names = TRUE)[1]
    x <- sf::st_read(shp, quiet = TRUE)
    x <- x[x$iso_a2 %in% c("US", "CA"), ]
    x <- sf::st_crop(sf::st_make_valid(x), sf::st_bbox(bbox, crs = 4326))
    sf::st_write(sf::st_sf(geometry = sf::st_union(x)), cache,
                 delete_dsn = TRUE, quiet = TRUE)
  }
  sf::st_read(cache, quiet = TRUE)
}

#' Orthographic projection centred on Massachusetts Bay, then an affine map
#' into emblem coordinates.  Working in a true azimuthal projection (rather
#' than plate carree) is what makes the orange field behave like a piece of a
#' sphere rather than a flat sheet.
project_geography <- function(x, map = MAP) {
  crs <- sprintf("+proj=ortho +lat_0=%f +lon_0=%f +R=6371000 +units=m +no_defs",
                 map$lat0, map$lon0)
  sf::st_transform(sf::st_set_crs(x, 4326), crs)
}

#' Rescale projected metres into the normalised emblem square.
to_emblem <- function(x, map = MAP) {
  s <- 1 / (map$span_km * 1000)
  aff <- matrix(c(s, 0, 0, s), 2, 2)
  g <- sf::st_geometry(x) * aff
  g <- g + c(map$anchor_x, map$anchor_y)
  sf::st_sf(geometry = sf::st_sfc(g))
}

#' A projected graticule, as an sf line layer already in emblem coordinates.
make_graticule <- function(map = MAP) {
  half_deg_lon <- (map$span_km / 111 / cos(map$lat0 * pi / 180))
  half_deg_lat <- (map$span_km / 111)
  lons <- seq(floor(map$lon0 - half_deg_lon), ceiling(map$lon0 + half_deg_lon),
              by = map$grat_lon)
  lats <- seq(floor(map$lat0 - half_deg_lat), ceiling(map$lat0 + half_deg_lat),
              by = map$grat_lat)
  segs <- list()
  for (lo in lons) {
    segs[[length(segs) + 1]] <- sf::st_linestring(
      cbind(lo, seq(min(lats), max(lats), length.out = 120)))
  }
  for (la in lats) {
    segs[[length(segs) + 1]] <- sf::st_linestring(
      cbind(seq(min(lons), max(lons), length.out = 120), la))
  }
  sf::st_sf(geometry = sf::st_sfc(segs, crs = 4326))
}

#' Everything the orange field needs: land, coastline and graticule, already
#' projected, scaled and clipped to the orange region of the emblem.
draw_globe_layer <- function(geom, map = MAP, offset = c(0, 0)) {
  field <- orange_field_sf(geom)
  shift <- function(x) sf::st_sf(geometry = sf::st_geometry(x) + offset)

  land <- to_emblem(project_geography(get_boston_geography(), map), map)
  land <- sf::st_make_valid(land)

  ## Fill and coastline are clipped separately: the fill is intersected with
  ## the orange field, but the stroke comes from the land's own boundary, so
  ## the clip edges along the bow and the arrow are never drawn as if they
  ## were coastline.
  coast <- suppressWarnings(sf::st_intersection(sf::st_boundary(land), field))
  land  <- suppressWarnings(sf::st_intersection(land, field))

  grat <- to_emblem(project_geography(make_graticule(map), map), map)
  grat <- suppressWarnings(sf::st_intersection(grat, field))

  ## Boston, as a barely-there tonal dot rather than a map pin.
  bos <- sf::st_sfc(sf::st_point(c(-71.0589, 42.3601)), crs = 4326)
  bos <- to_emblem(project_geography(sf::st_sf(geometry = bos), map), map)

  list(
    ggplot2::geom_sf(data = shift(grat), colour = GEO$graticule_col,
                     alpha = GEO$graticule_alpha, linewidth = GEO$graticule_lwd,
                     inherit.aes = FALSE),
    ggplot2::geom_sf(data = shift(land), fill = GEO$land_fill,
                     alpha = GEO$land_alpha, colour = NA, inherit.aes = FALSE),
    ggplot2::geom_sf(data = shift(coast),
                     colour = GEO$coast_col, alpha = GEO$coast_alpha,
                     linewidth = GEO$coast_lwd, inherit.aes = FALSE),
    ggplot2::geom_sf(data = shift(bos), colour = COL$white, alpha = GEO$boston_alpha,
                     size = GEO$boston_r * 220, shape = 16,
                     inherit.aes = FALSE)
  )
}


## ===========================================================================
## 5. Emblem drawing
## ===========================================================================

#' The orange gradient, as a real vector gradient (kept as a gradient in both
#' SVG and PDF output).  It is drawn across the whole square; the navy field
#' and the white bow/arrow are painted on top of it.
orange_gradient_grob <- function() {
  ## The gradient is radial about the centre of the bow's arcs, so its tonal
  ## bands run parallel to the sweeping white curve: the orange field reads as
  ## a sphere lit from the lower right, with the bow as its limb.
  c0 <- EMB$bow_in
  grid::rectGrob(gp = grid::gpar(
    col = NA,
    fill = grid::radialGradient(
      colours = c(COL$orange_light, COL$orange_mid, COL$orange_dark),
      stops   = c(0, 0.62, 1),
      cx1 = grid::unit(c0$cx, "npc"), cy1 = grid::unit(c0$cy, "npc"), r1 = grid::unit(0, "npc"),
      cx2 = grid::unit(c0$cx, "npc"), cy2 = grid::unit(c0$cy, "npc"),
      r2  = grid::unit(c0$r * 1.02, "npc")
    )))
}

#' ggplot layers for the emblem, in painting order.
draw_ohdsi_symbol <- function(geom, origin = c(0, 0)) {
  ox <- origin[1]; oy <- origin[2]
  poly <- function(df, fill) {
    ggplot2::geom_polygon(
      data = data.frame(x = df$x + ox, y = df$y + oy),
      ggplot2::aes(x, y), fill = fill, colour = NA, inherit.aes = FALSE)
  }
  list(
    poly(geom$navy,   COL$navy),
    poly(geom$bow,    COL$white),
    poly(geom$string, COL$white),
    poly(geom$arrow,  COL$white)
  )
}


## ===========================================================================
## 6. Typography
## ===========================================================================

#' Advance width of a string at a given point size, in points.
advance_width <- function(s, size, face = FACE_WORD) {
  if (!nzchar(s)) return(0)
  systemfonts::shape_string(s, family = face$family, bold = face$bold,
                            size = size)$metrics$width
}

#' ggplot2's fontface string for a face.
face_style <- function(face) if (isTRUE(face$bold)) "bold" else "plain"

#' Size a line of text by WIDTH, never by a horizontal scale factor.
#'
#' Returns the point size that makes `text` exactly `target_width` logo units
#' wide in its natural proportions, together with the cap height that follows.
fit_line <- function(text, target_width, pt_per_unit, face = FACE_WORD) {
  w <- advance_width(text, 1000, face)
  size <- 1000 * target_width * pt_per_unit / w
  list(size = size, cap = size * cap_ratio(face) / pt_per_unit)
}

#' Lay out a string in true small caps: the first letter of each word keeps the
#' full cap height, every other letter is drawn as a capital at a reduced size.
#'
#' Each glyph gets its own x position from the font's own advance widths, so
#' the line is fitted to `target_width` purely by choosing a size - the text is
#' never horizontally compressed.
layout_smallcaps <- function(text, target_width, ratio, tracking,
                             pt_per_unit, face = FACE_SUB) {
  cr    <- cap_ratio(face)
  chars <- strsplit(text, "")[[1]]
  big   <- c(TRUE, utils::head(chars, -1) == " ")   # first letter of each word
  glyph <- toupper(chars)

  ref       <- 1000
  size_ref  <- ifelse(big, ref, ref * ratio)
  adv_ref   <- mapply(advance_width, glyph, size_ref, MoreArgs = list(face))
  track_ref <- tracking * cr * ref                  # tracking ~ cap height
  total_ref <- sum(adv_ref) + track_ref * (length(chars) - 1)
  k         <- (target_width * pt_per_unit) / total_ref

  size  <- size_ref * k
  adv   <- adv_ref * k
  x_pt  <- cumsum(c(0, utils::head(adv + track_ref * k, -1)))

  keep <- glyph != " "
  list(
    df = data.frame(
      label = glyph[keep],
      x     = (x_pt[keep] + adv[keep] / 2) / pt_per_unit,
      size  = size[keep] / .pt,
      stringsAsFactors = FALSE
    ),
    cap = ref * k * cr / pt_per_unit
  )
}

#' Wordmark and subtitle as ggplot2 layers, plus the metrics the page layout
#' needs (their measured cap heights).
draw_wordmark <- function(pt_per_unit, layout = LAYOUT) {
  word <- fit_line(WORDMARK, layout$word_width, pt_per_unit, FACE_WORD)
  sub  <- layout_smallcaps(SUBTITLE, layout$sub_width, layout$sub_smallcap,
                           layout$sub_tracking, pt_per_unit, FACE_SUB)

  ## Vertical rhythm, built upwards from the subtitle baseline at y = 0.
  sub_baseline  <- 0
  word_baseline <- sub_baseline + sub$cap + layout$gap_word_sub
  emblem_bottom <- word_baseline + word$cap + layout$gap_emblem_word

  sub_df <- sub$df
  sub_df$x <- sub_df$x + (1 - layout$sub_width) / 2
  sub_df$y <- sub_baseline

  list(
    layers = list(
      ggplot2::annotate(
        "text", x = 0.5, y = word_baseline, label = WORDMARK,
        family = FACE_WORD$family, fontface = face_style(FACE_WORD),
        colour = COL$text,
        size = word$size / .pt, hjust = 0.5, vjust = 0),
      ggplot2::geom_text(
        data = sub_df,
        ggplot2::aes(x = x, y = y, label = label, size = size),
        family = FACE_SUB$family, fontface = face_style(FACE_SUB),
        colour = COL$text,
        hjust = 0.5, vjust = 0, inherit.aes = FALSE, show.legend = FALSE),
      ggplot2::scale_size_identity()
    ),
    emblem_bottom = emblem_bottom
  )
}


## ===========================================================================
## 7. Assembly
## ===========================================================================

build_logo <- function(layout = LAYOUT, out = OUT) {
  ensure_fonts()

  ## The emblem square is one logo unit wide; the canvas is as wide as the
  ## widest element (the wordmark may over-hang the mark slightly, as in the
  ## reference), plus margins.  That fixes points-per-unit, which is what lets
  ## type be sized by cap height rather than by eye.
  content_w   <- max(1, layout$word_width, layout$sub_width)
  canvas_w    <- content_w + 2 * layout$margin
  pt_per_unit <- (out$width / canvas_w) * 72
  side        <- (content_w - 1) / 2 + layout$margin

  txt           <- draw_wordmark(pt_per_unit, layout)
  emblem_bottom <- txt$emblem_bottom
  emblem_top    <- emblem_bottom + 1

  xlim <- c(-side, 1 + side)
  ylim <- c(-layout$margin, emblem_top + layout$margin)

  geom  <- make_ohdsi_geometry()
  globe <- draw_globe_layer(geom, MAP, offset = c(0, emblem_bottom))

  p <- ggplot2::ggplot() +
    ggplot2::annotation_custom(orange_gradient_grob(),
                               xmin = 0, xmax = 1,
                               ymin = emblem_bottom, ymax = emblem_top) +
    globe +
    draw_ohdsi_symbol(geom, origin = c(0, emblem_bottom)) +
    txt$layers +
    ggplot2::coord_sf(xlim = xlim, ylim = ylim, expand = FALSE,
                      crs = NULL, datum = NA, default_crs = NULL) +
    ggplot2::theme_void() +
    ggplot2::theme(
      plot.background  = ggplot2::element_rect(fill = COL$background, colour = NA),
      panel.background = ggplot2::element_rect(fill = COL$background, colour = NA),
      plot.margin      = ggplot2::margin(0, 0, 0, 0),
      legend.position  = "none"
    )

  attr(p, "canvas") <- c(w = canvas_w, h = diff(ylim))
  p
}

save_logo <- function(p = build_logo(), out = OUT) {
  cv <- attr(p, "canvas")
  w  <- out$width
  h  <- out$width * cv[["h"]] / cv[["w"]]

  ragg::agg_png(paste0(out$stem, ".png"), width = w, height = h,
                units = "in", res = out$dpi, background = COL$background)
  print(p); grDevices::dev.off()

  svglite::svglite(paste0(out$stem, ".svg"), width = w, height = h,
                   bg = COL$background)
  print(p); grDevices::dev.off()

  grDevices::cairo_pdf(paste0(out$stem, ".pdf"), width = w, height = h,
                       bg = COL$background)
  print(p); grDevices::dev.off()

  invisible(paste0(out$stem, c(".png", ".svg", ".pdf")))
}

if (sys.nframe() == 0L || !interactive()) {
  files <- save_logo()
  message("Wrote:\n  ", paste(files, collapse = "\n  "))
}
