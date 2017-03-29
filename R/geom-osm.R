
# bbox funcs

.tolatlon <- function(x, y, epsg=NULL, projection=NULL) {
  rgdal::CRSargs(sp::CRS("+init=epsg:3857")) #hack to load rgdal namespace
  if(is.null(epsg) && is.null(projection)) {
    stop("epsg and projection both null...nothing to project")
  } else if(!is.null(epsg) && !is.null(projection)) {
    stop("epsg and projection both specified...ambiguous call")
  }

  if(is.null(projection)) {
    projection <- sp::CRS(paste0("+init=epsg:", epsg))
  }

  coords <- sp::coordinates(matrix(c(x,y), byrow=TRUE, ncol=2))
  spoints <- sp::SpatialPoints(coords, projection)
  spnew <- sp::spTransform(spoints, sp::CRS("+init=epsg:4326"))
  c(sp::coordinates(spnew)[1], sp::coordinates(spnew)[2])
}

.fromlatlon <- function(lon, lat, epsg=NULL, projection=NULL) {
  rgdal::CRSargs(sp::CRS("+init=epsg:3857")) #hack to load rgdal namespace
  if(is.null(epsg) && is.null(projection)) {
    stop("epsg and projection both null...nothing to project")
  } else if(!is.null(epsg) && !is.null(projection)) {
    stop("epsg and projection both specified...ambiguous call")
  }

  if(is.null(projection)) {
    projection <- sp::CRS(paste0("+init=epsg:", epsg))
  }

  coords <- sp::coordinates(matrix(c(lon,lat), byrow=TRUE, ncol=2))
  spoints <- sp::SpatialPoints(coords, sp::CRS("+init=epsg:4326"))
  spnew <- sp::spTransform(spoints, projection)
  c(sp::coordinates(spnew)[1], sp::coordinates(spnew)[2])
}

.projectbbox <- function(bbox, toepsg=NULL, projection=NULL) {
  rgdal::CRSargs(sp::CRS("+init=epsg:3857")) #hack to load rgdal namespace
  if(is.null(toepsg) && is.null(projection)) {
    stop("toepsg and projection both null...nothing to project")
  } else if(!is.null(toepsg) && !is.null(projection)) {
    stop("toepsg and projection both specified...ambiguous call")
  }

  if(is.null(projection)) {
    projection <- sp::CRS(paste0("+init=epsg:", toepsg))
  }
  coords <- sp::coordinates(t(bbox))
  spoints = sp::SpatialPoints(coords, proj4string = sp::CRS("+init=epsg:4326"))
  newpoints <- sp::spTransform(spoints, projection)
  newbbox <- t(sp::coordinates(newpoints))

  if(newbbox[1,1] > newbbox[1,2]) { #if min>max
    maxx <- .fromlatlon(180, bbox[2, 1], projection=projection)[1]
    newbbox[1,1] <- newbbox[1,1]-maxx*2
  }
  newbbox
}

.revprojectbbox <- function(bbox, fromepsg=NULL, projection=NULL) {
  rgdal::CRSargs(sp::CRS("+init=epsg:3857")) #hack to load rgdal namespace
  if(is.null(fromepsg) && is.null(projection)) {
    stop("fromepsg and projection both null...nothing to project")
  } else if(!is.null(fromepsg) && !is.null(projection)) {
    stop("fromepsg and projection both specified...ambiguous call")
  }
  if(is.null(projection)) {
    projection <- sp::CRS(paste0("+init=epsg:", fromepsg))
  }
  coords <- sp::coordinates(t(bbox))
  spoints = sp::SpatialPoints(coords, proj4string = projection)
  newpoints <- sp::spTransform(spoints, sp::CRS("+init=epsg:4326"))
  t(sp::coordinates(newpoints))
}

# this stat takes the params passed to it and makes it into a dataframe with x, y, and colour vals
StatOSM <- ggplot2::ggproto("StatOSM", ggplot2::Stat,

   retransform = FALSE,

   compute_panel = function(self, data, scales, obj=NULL, zoomin=0, zoom=NULL,
                            type="osm", forcedownload=FALSE, cachedir=NULL,
                            projection=NULL) {
     # create bbox from xrange, yrange
     if(is.null(obj)) {
       obj <- rbind(scales$x$range$range, scales$y$range$range)
       box <- obj
     } else if(methods::is(obj, "Spatial")) {
       box <- sp::bbox(obj)
     } else {
       box <- obj
     }
     fused <- rosm::osm.raster(x=obj, zoomin=zoomin, zoom=zoom, type=type, forcedownload=forcedownload,
                         cachedir=cachedir, projection=projection)
     fused <- raster2dataframe(fused, crop=.projectbbox(box, projection=projection))
     return(fused[c("x", "y", "fill")])
   },

   required_aes = c()
)

#' A ggplot geometry for OSM imagery
#'
#' An experimental function returning a geom_raster representing the tile data such that it
#' can be plotted as a \code{ggplot2} layer. Should probably be used with \code{coord_fixed}.
#' Note that this does not scale the aspect like the \code{sp} package and will only work with
#' other datasets if they are provided in lat/lon (they can be projected using \link{geom_spatial}
#' without problems). This requires that the \code{rosm} package is installed.
#'
#' @param obj An object like in \code{osm.raster}: a bounding box or Spatial* object. Note that
#'   bounding boxes are always specified in lat/lon coordinates.
#' @param epsg The epsg code of the projection of the coordinates being plotted by other geoms.
#'   This defaults to spherical mercator or EPSG:3857.
#' @param zoomin The amount by which to adjust the automatically calculated zoom (or
#' manually specified if the \code{zoom} parameter is passed). Use +1 to zoom in, or -1 to zoom out.
#' @param zoom Manually specify the zoom level (not recommended; adjust \code{zoomin} instead.
#' @param type A map type; one of that returned by \code{osm.types}. User defined types are possible
#' by defining \code{tile.url.TYPENAME <- function(xtile, ytile, zoom){}} and passing TYPENAME
#' as the \code{type} argument.
#' @param forcedownload \code{TRUE} if cached tiles should be re-downloaded. Useful if
#' some tiles are corrupted.
#' @param cachedir The directory in which tiles should be cached. Defaults to \code{getwd()/rosm.cache}.
#' @param projection A map projection in which to reproject the RasterStack as generated by \code{CRS()} or
#'                  \code{Spatial*@@proj4string}. If a \code{Spatial*} object is passed as the first argument,
#'                  this argument will be ignored. Use \code{epsg} as a short form.
#' @param ... Agruments passed on to \code{geom_raster()}
#'
#' @return A \code{geom_raster} with colour data from the tiles.
#' @export
#'
#' @examples
#' \dontrun{
#' library(prettymapr)
#' library(ggplot2)
#' ns <- searchbbox("Nova Scotia")
#' cities <- geocode(c("Wolfville, NS", "Windsor, NS", "Halifax, NS"))
#' ggplot(cities, aes(x=lon, y=lat, col=id)) +
#'     geom_osm(epsg=3857) + geom_spatial(toepsg=3857) +
#'     coord_fixed()
#' ggplot() + geom_osm(ns) + coord_fixed()
#'
#' ggplot(data.frame(t(ns)), aes(x=x, y=y)) +
#'   geom_osm(type="stamenbw", zoomin=-1) +
#'   geom_point() + coord_fixed()
#' }
#'
geom_osm <- function(obj=NULL, zoomin=0, zoom=NULL, type="osm", forcedownload=FALSE, cachedir=NULL,
                     epsg=NULL, projection=NULL,...) {
  if(!("rosm" %in% rownames(utils::installed.packages()))) {
    stop("package 'rosm' must be installed for call to geom_osm()")
  }
  rgdal::CRSargs(sp::CRS("+init=epsg:3857")) #hack to load rgdal namespace
  if(is.null(projection) && is.null(epsg)) {
    projection <- sp::CRS("+init=epsg:3857")
  } else if(!is.null(projection) && !is.null(epsg)) {
    stop("Ambiguous call: do not specify epsg and projection")
  } else if(is.null(projection) && !is.null(epsg)) {
    projection <- sp::CRS(paste0("+init=epsg:", epsg))
  }
  ggplot2::layer(
    stat = StatOSM, data = data.frame(x=1), mapping = NULL, geom = "raster",
    show.legend = FALSE, inherit.aes = FALSE, position = "identity",
    params=list(obj=obj, zoomin=zoomin, zoom=zoom, type=type,
                forcedownload=forcedownload, cachedir=cachedir,
                projection=projection, ...)
  )
}