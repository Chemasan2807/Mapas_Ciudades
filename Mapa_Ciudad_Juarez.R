# ============================================================
#  Mapa minimalista de Ciudad Juárez, Chihuahua (México)
#  Genera un PNG con tamaño de impresión EXACTO de 13 x 8.6 cm,
#  donde el mapa llena por completo el lienzo (sin márgenes blancos).
#
#  Fuente de datos: OpenStreetMap (vía el paquete `osmdata`, gratis,
#  sin necesidad de API key).
# ============================================================

# ---- 0. Paquetes --------------------------------------------
pkgs <- c("osmdata", "sf", "ggplot2", "ragg", "dplyr", "readxl", "png")
faltantes <- pkgs[!pkgs %in% rownames(installed.packages())]
if (length(faltantes) > 0) install.packages(faltantes)

library(osmdata)
library(sf)
library(ggplot2)
library(dplyr)
library(readxl)

# El espejo por defecto de osmdata (overpass.kumi.systems) a veces falla o
# está caído; overpass-api.de es el servidor principal y más estable.
set_overpass_url("https://overpass-api.de/api/interpreter")

# ============================================================
# ---- 1. CONFIGURACIÓN (lo único que normalmente necesitas tocar) ----
# ============================================================

# --- Tamaño físico final del PNG ---
paper_w_cm <- 13     # ancho  (cm)
paper_h_cm <- 8.6    # alto   (cm)

# --- Resolución de salida ---
# 300 = buena calidad para pantalla / documentos. 600 = alta calidad de impresión.
dpi <- 600

# --- Punto central del mapa ---
# Por defecto: Plaza de Armas, centro histórico de Ciudad Juárez.
# Puedes cambiarlo por cualquier otro punto (p.ej. una propiedad específica).
centro_lat <- 31.683511283160563
centro_lon <- -106.41757955956528

# --- CONTROL DE ZOOM (el único número que necesitas mover) -----------
# Es la distancia, en km, del centro al borde SUPERIOR/INFERIOR del mapa.
# El ancho se calcula automáticamente para llenar los 13 x 8.6 cm sin deformar.
#
#   Número MÁS PEQUEÑO -> más zoom (te acercas, ves menos ciudad)
#   Número MÁS GRANDE  -> menos zoom (te alejas, ves más ciudad)
#
radio_vertical_km <- 10

# --- Caché local de datos OSM ------------------------------------------
# La PRIMERA vez, el script descarga de OpenStreetMap un área más grande
# que tu zoom actual y la guarda en disco (archivo_cache). Mientras
# radio_vertical_km quepa dentro de radio_cache_km, las siguientes corridas
# leen el archivo local: son casi instantáneas y no requieren internet.
# Si algún día pones un radio_vertical_km mayor a radio_cache_km, el script
# se da cuenta solo y vuelve a descargar (un área más grande).
radio_cache_km <- max(15, radio_vertical_km)
archivo_cache  <- "/Users/chema/Library/CloudStorage/OneDrive-ACTINVER/Python/Mapas_JLL/Ciudad_Juarez/ciudad_juarez_osm_cache.rds"

# --- Colores ---
color_fondo               <- "#f4f1ea"  # fondo del mapa
color_calles_secundarias  <- "#dbd7cf"  # calles normales
color_calles_principales  <- "#5f5d5d"  # avenidas / carreteras principales
color_agua                <- "#bbd3e1"  # ríos / cuerpos de agua
color_verde                <- "#c9d6b6"  # parques / áreas verdes

archivo_salida <- "/Users/chema/Library/CloudStorage/OneDrive-ACTINVER/Python/Mapas_JLL/Mapas_png/Mapa_Ciudad_Juarez.png"

# ============================================================
# ---- 1b. PROPIEDADES (puntos sobre el mapa) -------------------
# ============================================================
# Excel con las propiedades. Columnas usadas: Company (color del punto),
# Type (forma del punto), Latitude y Longitude (posición).
# Solo se dibujan los puntos que caen DENTRO del recuadro visible del mapa.
archivo_propiedades <- "/Users/chema/Library/CloudStorage/OneDrive-ACTINVER/Python/Mapas_JLL/Property_Coordinates.xlsx"
hoja_propiedades    <- "Property_Coordinates"

# --- Aeropuertos (áreas sombreadas) ---
# La hoja "Airport" trae un vértice por fila: airport, vertex_order, Latitude,
# Longitude. Las filas con el mismo `airport` forman su polígono, en el orden
# que marca `vertex_order`.
# Se dibujan los aeropuertos que TOCAN el recuadro visible; si uno queda a
# medias, se ve la parte que entra y el resto se corta en el borde del mapa.
hoja_aeropuertos  <- "Airport"
color_aeropuerto  <- "#a8a8a8"  # gris del sombreado
alpha_aeropuerto  <- 1      # 0 = invisible, 1 = gris sólido

# --- Icono de avión sobre cada aeropuerto ---
# Se coloca en el centroide de la PARTE VISIBLE del polígono: si el aeropuerto
# sale completo, es su centroide real; si sale a medias, es el centroide del
# pedazo que sí entra en el mapa.
archivo_avion    <- "/Users/chema/Library/CloudStorage/OneDrive-ACTINVER/Python/Mapas_JLL/Airplane.png"
mostrar_avion    <- TRUE
avion_ancho_frac <- 0.035  # ancho del avión como fracción del ancho del mapa
                           # (al ser relativo, se ve del mismo tamaño en el PNG
                           #  sin importar el zoom)

# --- Apariencia de los puntos ---
punto_tamano <- 2.5      # tamaño del marcador
punto_borde  <- "white"  # contorno del marcador: NA = sin contorno
punto_grosor <- 0.25     # grosor del contorno (solo aplica si punto_borde no es NA)

mostrar_leyenda <- TRUE  # FALSE = mapa limpio, sin leyenda encima

# --- Tipografía ---
# Nombre de la familia tal como la tiene instalada el sistema. ragg la resuelve
# sola; si no está instalada, avisa y usa la de por defecto.
fuente <- "Century Gothic"

# --- COLOR por Company ---
# Paleta institucional definida por el usuario.
colores_empresa <- c(
  "DANHOS"  = "#041E42",  # azul marino
  "VESTA"   = "#B6A269",  # arena
  "FIHO"    = "#78909C",  # gris azulado
  "FIBRAMQ" = "#5B9BD5",  # azul claro
  "SOMA"    = "#008080",  # verde azulado
  "HOTEL"   = "#0563C1",  # azul
  "FINN"    = "#66B3B3",  # turquesa claro
  "FSHOP"   = "#555B60",  # gris oscuro
  "FUNO"    = "#6B577F",  # morado
  "NEXT"    = "#92899A",  # morado grisáceo
  "HCITY"   = "#44546A"   # azul pizarra
)

# --- FORMA por Type ---
# Se usan formas 21-25 (rellenables): el relleno lleva el color de la empresa.
# Al ser rellenables, se les puede activar un contorno con `punto_borde`.
formas_tipo <- c(
  "Hotel"      = 21,  # círculo
  "Industrial" = 22,  # cuadrado
  "Office"     = 23,  # rombo
  "Retail"     = 24,  # triángulo
  "Mix"        = 25   # triángulo invertido
)

# ============================================================
# ---- 2. Cálculo del área a descargar, según el tamaño del papel ----
# ============================================================

aspecto <- paper_w_cm / paper_h_cm   # ancho / alto del papel

punto_centro <- st_sfc(st_point(c(centro_lon, centro_lat)), crs = 4326)

# CRS métrico (UTM zona 13N) adecuado para el estado de Chihuahua.
crs_metrico <- 32613

centro_m <- st_transform(punto_centro, crs_metrico)
xy_centro <- st_coordinates(centro_m)

calcular_bbox <- function(radio_km) {
  medio_alto_m  <- radio_km * 1000
  medio_ancho_m <- medio_alto_m * aspecto
  st_bbox(c(
    xmin = xy_centro[1] - medio_ancho_m,
    xmax = xy_centro[1] + medio_ancho_m,
    ymin = xy_centro[2] - medio_alto_m,
    ymax = xy_centro[2] + medio_alto_m
  ), crs = st_crs(crs_metrico))
}

# bbox de DISPLAY: lo que realmente se ve en el PNG final (según el zoom pedido)
bbox_m <- calcular_bbox(radio_vertical_km)

# bbox de CACHÉ: el área que se descarga y se guarda en disco (más grande o igual)
bbox_cache_m  <- calcular_bbox(radio_cache_km)
bbox_cache_ll <- st_bbox(st_transform(st_as_sfc(bbox_cache_m), 4326))

# ---- Las 4 coordenadas (lat, lon) que definen el contorno del mapa mostrado ----
bbox_display_ll <- st_bbox(st_transform(st_as_sfc(bbox_m), 4326))
message("Contorno del mapa (WGS84 - lat, lon):")
message("  Noroeste: ", round(bbox_display_ll["ymax"], 6), ", ", round(bbox_display_ll["xmin"], 6))
message("  Noreste : ", round(bbox_display_ll["ymax"], 6), ", ", round(bbox_display_ll["xmax"], 6))
message("  Sureste : ", round(bbox_display_ll["ymin"], 6), ", ", round(bbox_display_ll["xmax"], 6))
message("  Suroeste: ", round(bbox_display_ll["ymin"], 6), ", ", round(bbox_display_ll["xmin"], 6))

# ============================================================
# ---- 3. Datos de OpenStreetMap (con caché en disco) -----------
# ============================================================

# ¿Ya hay un caché en disco que cubra el centro y el radio que pedimos?
cache_valido <- FALSE
if (file.exists(archivo_cache)) {
  cache <- readRDS(archivo_cache)
  mismo_centro <- isTRUE(all.equal(c(cache$centro_lat, cache$centro_lon),
                                    c(centro_lat, centro_lon), tolerance = 1e-6))
  cache_cubre_zoom <- cache$radio_cache_km >= radio_vertical_km
  cache_valido <- mismo_centro && cache_cubre_zoom
}

if (cache_valido) {

  message("Usando caché local (", archivo_cache, ") -- sin descargar de internet.")
  calles_todas_l       <- cache$calles_todas_l
  calles_principales_l <- cache$calles_principales_l
  agua_poly             <- cache$agua_poly
  rios_l                 <- cache$rios_l
  verde_poly             <- cache$verde_poly

} else {

  descargar_osm <- function(key, value = NULL) {
    q <- opq(bbox = bbox_cache_ll, timeout = 120)
    q <- if (is.null(value)) add_osm_feature(q, key = key) else add_osm_feature(q, key = key, value = value)
    tryCatch(osmdata_sf(q), error = function(e) NULL)
  }

  message("Descargando de OpenStreetMap (radio de caché: ", radio_cache_km, " km)...")

  message("  - calles...")
  calles_todas <- descargar_osm("highway")

  message("  - vialidades principales...")
  calles_principales <- descargar_osm("highway", c("motorway", "trunk", "primary", "secondary", "motorway_link", "trunk_link", "primary_link"))

  message("  - agua...")
  agua_poligonos <- descargar_osm("natural", "water")
  rios <- descargar_osm("waterway")

  message("  - áreas verdes...")
  verde <- descargar_osm("leisure", c("park", "garden"))

  # ---- Helper: extrae una capa (líneas o polígonos), o NULL si no hay nada ----
  capa_lineas <- function(x) if (!is.null(x) && !is.null(x$osm_lines) && nrow(x$osm_lines) > 0) st_transform(x$osm_lines, crs_metrico) else NULL
  capa_poligonos <- function(x) if (!is.null(x) && !is.null(x$osm_polygons) && nrow(x$osm_polygons) > 0) st_transform(x$osm_polygons, crs_metrico) else NULL

  calles_todas_l       <- capa_lineas(calles_todas)
  calles_principales_l <- capa_lineas(calles_principales)
  agua_poly             <- capa_poligonos(agua_poligonos)
  rios_l                 <- capa_lineas(rios)
  verde_poly             <- capa_poligonos(verde)

  # Solo guardamos caché si la descarga realmente trajo datos. Si Overpass
  # falló o no devolvió nada (p.ej. por límite de uso temporal), NO se guarda
  # un caché vacío -- así la siguiente corrida vuelve a intentar en vez de
  # quedarse pegada con un mapa en blanco para siempre.
  if (!is.null(calles_todas_l) && nrow(calles_todas_l) > 0) {
    saveRDS(list(
      centro_lat = centro_lat, centro_lon = centro_lon, radio_cache_km = radio_cache_km,
      calles_todas_l = calles_todas_l, calles_principales_l = calles_principales_l,
      agua_poly = agua_poly, rios_l = rios_l, verde_poly = verde_poly
    ), archivo_cache)
    message("Caché guardado en ", archivo_cache, " (radio ", radio_cache_km, " km).")
  } else {
    warning("La descarga de OpenStreetMap no trajo datos de calles (¿sin internet? ¿Overpass ocupado?). ",
            "No se guardó caché; el PNG resultante puede salir vacío. Vuelve a correr el script.")
  }
}

# ============================================================
# ---- 3b. Propiedades del Excel (puntos) -----------------------
# ============================================================

# Algunas celdas de Latitude traen "lat, lon" juntos en el mismo campo, así que
# se toma el PRIMER número de la celda en vez de convertir a ciegas.
primer_numero <- function(x) {
  x <- as.character(x)
  pos <- regexpr("-?[0-9]+(\\.[0-9]+)?", x)
  out <- rep(NA_real_, length(x))
  encontrado <- pos > 0
  out[encontrado] <- as.numeric(regmatches(x, pos))
  out
}

propiedades <- read_excel(archivo_propiedades, sheet = hoja_propiedades)

propiedades <- propiedades %>%
  mutate(
    lat = primer_numero(Latitude),
    lon = primer_numero(Longitude)
  ) %>%
  filter(!is.na(lat), !is.na(lon))

# A sf en WGS84 y luego al CRS métrico del mapa.
propiedades_sf <- st_as_sf(propiedades, coords = c("lon", "lat"), crs = 4326) %>%
  st_transform(crs_metrico)

# ---- Nos quedamos SOLO con lo que cae dentro del recuadro visible ----
xy_props <- st_coordinates(propiedades_sf)
dentro <- xy_props[, 1] >= bbox_m["xmin"] & xy_props[, 1] <= bbox_m["xmax"] &
          xy_props[, 2] >= bbox_m["ymin"] & xy_props[, 2] <= bbox_m["ymax"]
puntos <- propiedades_sf[dentro, ]

message("Propiedades dentro del mapa: ", nrow(puntos), " de ", nrow(propiedades_sf), " del Excel.")

if (nrow(puntos) > 0) {
  # Aviso si aparece una empresa o un tipo sin color/forma asignado, para que
  # no desaparezca del mapa en silencio.
  sin_color <- setdiff(unique(puntos$Company), names(colores_empresa))
  sin_forma <- setdiff(unique(puntos$Type), names(formas_tipo))
  if (length(sin_color) > 0) warning("Company sin color asignado: ", paste(sin_color, collapse = ", "))
  if (length(sin_forma) > 0) warning("Type sin forma asignada: ", paste(sin_forma, collapse = ", "))

  message("  Empresas: ", paste(sort(unique(puntos$Company)), collapse = ", "))
  message("  Tipos   : ", paste(sort(unique(puntos$Type)), collapse = ", "))
}

# ============================================================
# ---- 3c. Aeropuertos (polígonos sombreados) -------------------
# ============================================================

vertices_aeropuerto <- read_excel(archivo_propiedades, sheet = hoja_aeropuertos) %>%
  filter(!is.na(Latitude), !is.na(Longitude)) %>%
  arrange(airport, vertex_order)

# Cada aeropuerto es un grupo de vértices -> un polígono.
anillos <- lapply(split(vertices_aeropuerto, vertices_aeropuerto$airport), function(d) {
  m <- as.matrix(d[, c("Longitude", "Latitude")])
  # Un polígono necesita el anillo cerrado (último vértice = primero). En el
  # Excel ya vienen cerrados, pero se fuerza por si algún aeropuerto no lo está.
  if (!isTRUE(all.equal(m[1, ], m[nrow(m), ]))) m <- rbind(m, m[1, ])
  st_polygon(list(m))
})

aeropuertos_sf <- st_sf(
  airport  = names(anillos),
  geometry = st_sfc(anillos, crs = 4326)
) %>%
  st_transform(crs_metrico) %>%
  # Los vértices vienen trazados a mano, así que un anillo puede auto-cruzarse.
  st_make_valid()

# ---- Nos quedamos con los que TOCAN el recuadro visible ----
# Basta con que lo toquen: el recorte fino lo hace coord_sf al dibujar, así que
# un aeropuerto que entra a medias se ve cortado en el borde del mapa.
recuadro_visible <- st_as_sfc(bbox_m)
aeropuertos <- aeropuertos_sf[lengths(st_intersects(aeropuertos_sf, recuadro_visible)) > 0, ]

message("Aeropuertos visibles en el mapa: ", nrow(aeropuertos), " de ", nrow(aeropuertos_sf), " del Excel.")
if (nrow(aeropuertos) > 0) message("  ", paste(aeropuertos$airport, collapse = ", "))

# ---- Posición del avión: centroide de la PARTE VISIBLE ----
# Se recorta cada aeropuerto contra el recuadro y se saca el centroide de lo
# que queda. Para uno que sale completo da su centroide normal; para uno
# cortado, el del pedazo que sí se ve.
centros_avion <- NULL
if (nrow(aeropuertos) > 0) {
  st_agr(aeropuertos) <- "constant"   # evita el aviso de atributos en la intersección
  aeropuertos_recortados <- st_intersection(aeropuertos, recuadro_visible)

  centroides <- st_centroid(st_geometry(aeropuertos_recortados))
  # Un aeropuerto en forma de L puede tener el centroide FUERA de su propia
  # área; en ese caso se usa un punto garantizado dentro del polígono.
  cae_dentro <- as.logical(diag(st_intersects(centroides, aeropuertos_recortados, sparse = FALSE)))
  if (any(!cae_dentro)) {
    seguros <- st_point_on_surface(st_geometry(aeropuertos_recortados))
    centroides[!cae_dentro] <- seguros[!cae_dentro]
    message("  (centroide reubicado dentro del área en: ",
            paste(aeropuertos_recortados$airport[!cae_dentro], collapse = ", "), ")")
  }
  centros_avion <- st_coordinates(centroides)
}

# ---- Carga del icono de avión ----
avion_raster  <- NULL
avion_aspecto <- 1  # alto / ancho
if (mostrar_avion && !is.null(centros_avion)) {
  if (!file.exists(archivo_avion)) {
    warning("No se encontró la imagen del avión: ", archivo_avion, ". Se dibuja el mapa sin ella.")
  } else {
    img <- png::readPNG(archivo_avion)

    if (dim(img)[3] == 4) {
      # PNG con transparencia real: se usa su propio canal alfa.
      alfa    <- img[, , 4]
      rgb_img <- img[, , 1:3, drop = FALSE]
    } else {
      # PNG SIN canal alfa: el "fondo transparente" viene dibujado como un
      # damero gris de píxeles reales. Se reconstruye la transparencia con la
      # saturación: el damero es gris (saturación ~0) y el avión tiene color
      # (saturación alta), así que la saturación sirve de canal alfa y de paso
      # deja los bordes suavizados.
      mx  <- pmax(img[, , 1], img[, , 2], img[, , 3])
      mn  <- pmin(img[, , 1], img[, , 2], img[, , 3])
      sat <- mx - mn
      alfa <- pmin(sat / max(sat), 1)
      # Es una silueta de un solo color: se repinta con el color más saturado
      # de la imagen para que los bordes no salgan lavados con gris.
      i_color <- which.max(sat)
      color_avion <- c(img[, , 1][i_color], img[, , 2][i_color], img[, , 3][i_color])
      rgb_img <- array(rep(color_avion, each = length(alfa)), dim = c(dim(alfa), 3))
    }

    # La imagen trae mucho margen vacío; se recorta al contenido para que
    # avion_ancho_frac se refiera al avión y no al lienzo.
    filas <- which(apply(alfa, 1, max) > 0.05)
    cols  <- which(apply(alfa, 2, max) > 0.05)
    if (length(filas) > 0 && length(cols) > 0) {
      alfa    <- alfa[filas, cols, drop = FALSE]
      rgb_img <- rgb_img[filas, cols, , drop = FALSE]
    }

    avion_raster  <- as.raster(array(c(rgb_img, alfa), dim = c(dim(alfa), 4)))
    avion_aspecto <- nrow(alfa) / ncol(alfa)
  }
}

# ============================================================
# ---- 4. Construcción del mapa ---------------------------------
# ============================================================

# Si la fuente no está instalada, ragg cae en la de por defecto sin decir nada;
# este aviso evita que el cambio pase desapercibido.
if (!tolower(fuente) %in% tolower(systemfonts::system_fonts()$family)) {
  warning("La fuente '", fuente, "' no está instalada; se usará la de por defecto.")
}

p <- ggplot() +
  theme_void() +
  theme(
    # `text` es la raíz de la que heredan los demás elementos de texto
    # (incluida la leyenda), así que basta ponerla aquí.
    text             = element_text(family = fuente),
    plot.background  = element_rect(fill = color_fondo, color = NA),
    panel.background = element_rect(fill = color_fondo, color = NA),
    plot.margin      = margin(0, 0, 0, 0)
  )

if (!is.null(verde_poly))            p <- p + geom_sf(data = verde_poly, fill = color_verde, color = NA)
if (!is.null(agua_poly))             p <- p + geom_sf(data = agua_poly, fill = color_agua, color = NA)
if (!is.null(rios_l))                p <- p + geom_sf(data = rios_l, color = color_agua, linewidth = 0.3)
if (!is.null(calles_todas_l))        p <- p + geom_sf(data = calles_todas_l, color = color_calles_secundarias, linewidth = 0.15)
if (!is.null(calles_principales_l))  p <- p + geom_sf(data = calles_principales_l, color = color_calles_principales, linewidth = 0.35)

# El sombreado de aeropuertos va ENCIMA de las calles: con alpha_aeropuerto = 1
# el gris las tapa y el área queda como un bloque limpio. Aun así se dibuja
# antes que los puntos, para no esconder ninguna propiedad.
if (nrow(aeropuertos) > 0)           p <- p + geom_sf(data = aeropuertos, fill = color_aeropuerto, color = NA, alpha = alpha_aeropuerto)

# ---- Avión encima de cada aeropuerto ----
# El tamaño se define en metros a partir del ancho del mapa; como el CRS es
# métrico y coord_sf conserva la proporción, el avión no se deforma.
if (!is.null(avion_raster)) {
  avion_ancho_m <- avion_ancho_frac * (bbox_m["xmax"] - bbox_m["xmin"])
  avion_alto_m  <- avion_ancho_m * avion_aspecto
  for (i in seq_len(nrow(centros_avion))) {
    p <- p + annotation_raster(
      avion_raster,
      xmin = centros_avion[i, 1] - avion_ancho_m / 2,
      xmax = centros_avion[i, 1] + avion_ancho_m / 2,
      ymin = centros_avion[i, 2] - avion_alto_m / 2,
      ymax = centros_avion[i, 2] + avion_alto_m / 2,
      interpolate = TRUE
    )
  }
}

# ---- Puntos de las propiedades (hasta arriba, sobre las calles) ----
if (nrow(puntos) > 0) {
  # Sin contorno (punto_borde = NA) el color del borde se mapea también a
  # Company: así el marcador se ve macizo. Ojo: NO se puede pasar color = NA
  # directo, porque ggplot lo trata como valor faltante y borra los puntos.
  sin_contorno <- is.na(punto_borde)

  if (sin_contorno) {
    # El color del borde se mapea también a Company, así el marcador se ve
    # macizo. Se necesita la escala de color y su entrada en guides().
    p <- p +
      geom_sf(data = puntos, aes(fill = Company, color = Company, shape = Type),
              size = punto_tamano, stroke = punto_grosor) +
      scale_color_manual(values = colores_empresa, name = NULL, drop = TRUE) +
      # fill y color se fusionan en una sola leyenda de empresas; el
      # override.aes va solo en una para no duplicarlo.
      guides(color = guide_legend(order = 1))
  } else {
    # Contorno de color fijo: `color` deja de ser una estética mapeada, así que
    # aquí NO va scale_color_manual (si no, ggplot avisa que la escala no
    # corresponde a ningún dato).
    p <- p +
      geom_sf(data = puntos, aes(fill = Company, shape = Type),
              size = punto_tamano, stroke = punto_grosor, color = punto_borde)
  }

  p <- p +
    scale_fill_manual(values = colores_empresa, name = NULL, drop = TRUE) +
    scale_shape_manual(values = formas_tipo, name = NULL, drop = TRUE) +
    # Las llaves de la leyenda necesitan ayuda: la de empresas se dibuja como
    # círculo relleno, y la de tipos como forma gris (si no, salen vacías).
    guides(
      fill  = guide_legend(order = 1, override.aes = list(shape = 21, size = 2.4)),
      shape = guide_legend(order = 2, override.aes = list(
        fill = "#5a5a5a", color = if (sin_contorno) "#5a5a5a" else punto_borde, size = 2.4))
    )

  if (mostrar_leyenda) {
    p <- p + theme(
      legend.position        = "inside",
      legend.position.inside = c(0.012, 0.018),
      legend.justification   = c(0, 0),
      legend.box             = "horizontal",
      legend.box.just        = "bottom",
      # Fondo semitransparente del color del mapa (CC = ~80% opaco).
      legend.background      = element_rect(fill = paste0(color_fondo, "CC"), color = NA),
      legend.key             = element_blank(),
      legend.text            = element_text(size = 4, color = "#3a3a3a"),
      legend.key.size        = unit(2.8, "mm"),
      legend.margin          = margin(1, 2, 1, 2),
      legend.box.spacing     = unit(0, "mm"),
      legend.spacing.x       = unit(1, "mm")
    )
  } else {  
    p <- p + theme(legend.position = "none")
  }
}

p <- p + coord_sf(
  xlim = c(bbox_m["xmin"], bbox_m["xmax"]),
  ylim = c(bbox_m["ymin"], bbox_m["ymax"]),
  crs  = crs_metrico,
  expand = FALSE
)

# ============================================================
# ---- 5. Exportar PNG con tamaño físico exacto -----------------
# ============================================================

ggsave(
  filename = archivo_salida,
  plot     = p,
  device   = ragg::agg_png,
  width    = paper_w_cm,
  height   = paper_h_cm,
  units    = "cm",
  dpi      = dpi,
  bg       = color_fondo
)
