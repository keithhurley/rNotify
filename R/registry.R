#' Channel Registry, Configuration, and Resolution
#'
#' Manages global channel profiles, channel selection (1, few, or all),
#' and startup announcements.
#'
#' @name rnotify_registry
#' @keywords internal
NULL

# Internal storage environment for configured channels
.rnotify_env <- new.env(parent = emptyenv())
.rnotify_env$configured_channels <- list()

#' Configure Default Notification Channels
#'
#' Saves a profile of channels that can be referenced globally by name
#' or collectively via \code{channels = "all"}.
#'
#' @param ... Named \code{rnotify_channel} objects, e.g. \code{desktop = channel_desktop()}.
#' @return Invisible list of configured channels.
#' @export
#' @examples
#' \dontrun{
#' rnotify_configure(
#'   desktop  = channel_desktop(),
#'   pushover = channel_pushover(),
#'   cyd      = channel_cyd(host = "192.168.1.150")
#' )
#' }
rnotify_configure <- function(...) {
  args <- list(...)
  if (length(args) == 0) {
    return(invisible(.rnotify_env$configured_channels))
  }

  channels <- list()
  for (i in seq_along(args)) {
    obj <- args[[i]]
    arg_name <- names(args)[i]
    if (inherits(obj, "rnotify_channel")) {
      key <- if (!is.null(arg_name) && nzchar(arg_name)) arg_name else obj$name
      channels[[key]] <- obj
    }
  }

  .rnotify_env$configured_channels <- channels
  message(sprintf("[rNotify] Configured %d channels: %s",
                  length(channels),
                  paste(names(channels), collapse = ", ")))
  invisible(channels)
}

#' Retrieve Configured Notification Channels
#'
#' @return Named list of \code{rnotify_channel} objects.
#' @export
rnotify_get_configured <- function() {
  .rnotify_env$configured_channels
}

#' Resolve Channel Specifications
#'
#' Resolves user input into a validated list of \code{rnotify_channel} objects.
#' Supports:
#' \itemize{
#'   \item Explicit channel object (e.g. \code{channel_desktop()})
#'   \item List of channel objects
#'   \item The keyword \code{"all"} (all configured channels)
#'   \item Character vector of configured channel names (e.g. \code{c("pushover", "cyd")})
#' }
#'
#' @param channels Channel specification.
#' @return List of validated \code{rnotify_channel} objects.
#' @export
resolve_channels <- function(channels = "all") {
  if (is.null(channels)) {
    return(list())
  }

  # If single channel object
  if (inherits(channels, "rnotify_channel")) {
    return(list(channels))
  }

  # If character vector
  if (is.character(channels)) {
    configured <- rnotify_get_configured()

    if (identical(channels, "all")) {
      if (length(configured) == 0) {
        # Fallback default: Desktop channel
        return(list(channel_desktop()))
      }
      return(unname(configured))
    }

    # Match subset of names
    selected <- list()
    for (nm in channels) {
      if (nm %in% names(configured)) {
        selected[[nm]] <- configured[[nm]]
      } else {
        warning(sprintf("[rNotify] Channel '%s' was requested but is not configured.", nm), call. = FALSE)
      }
    }

    if (length(selected) == 0) {
      warning("[rNotify] No requested channels matched configuration. Defaulting to desktop channel.", call. = FALSE)
      return(list(channel_desktop()))
    }
    return(unname(selected))
  }

  # If list of channels
  if (is.list(channels)) {
    valid <- list()
    for (item in channels) {
      if (inherits(item, "rnotify_channel")) {
        valid <- c(valid, list(item))
      } else if (is.character(item) && length(item) == 1) {
        # Resolve by name
        res <- resolve_channels(item)
        valid <- c(valid, res)
      }
    }
    return(valid)
  }

  stop("[rNotify] Unrecognized 'channels' argument format.")
}

#' Announce Active Channels on Job Initialization
#'
#' Outputs informative startup status to the console.
#'
#' @param title Job title.
#' @param channels List of resolved \code{rnotify_channel} objects.
#' @param pid Integer process ID.
#' @param sentinel_active Logical indicating whether background crash sentinel is active.
#' @export
announce_channels <- function(title, channels, pid = Sys.getpid(), sentinel_active = FALSE) {
  ch_desc <- vapply(channels, function(ch) {
    if (ch$name == "cyd") {
      tr <- if (!is.null(ch$transport)) ch$transport else ch$meta$transport
      tgt <- if (!is.null(ch$target)) ch$target else ch$meta$target
      if (identical(tr, "bluetooth")) {
        sprintf("CYD Bluetooth (%s)", tgt)
      } else if (identical(tr, "serial")) {
        sprintf("CYD Serial (%s)", tgt)
      } else if (!is.null(tgt) && grepl("^(COM[0-9]+|/dev/)", tgt, ignore.case = TRUE)) {
        sprintf("CYD (%s)", tgt)
      } else if (!is.null(ch$meta$host)) {
        sprintf("CYD (%s:%s)", ch$meta$host, ch$meta$port)
      } else if (!is.null(tgt)) {
        sprintf("CYD (%s)", tgt)
      } else {
        "CYD"
      }
    } else if (ch$name == "ntfy" && !is.null(ch$meta$topic)) {
      sprintf("ntfy [%s]", ch$meta$topic)
    } else if (ch$name == "email" && !is.null(ch$meta$to)) {
      sprintf("Email (%s)", paste(ch$meta$to, collapse = ","))
    } else {
      capitalize(ch$name)
    }
  }, character(1))

  ch_str <- if (length(ch_desc) > 0) paste(ch_desc, collapse = ", ") else "None (Console Only)"

  message(sprintf("[rNotify] ========================================================"))
  message(sprintf("[rNotify] Job Initialized: '%s' (PID: %d)", title, pid))
  message(sprintf("[rNotify] Active Channels (%d): %s", length(channels), ch_str))
  if (isTRUE(sentinel_active)) {
    message(sprintf("[rNotify] Crash Sentinel: Active (Dead Man's Switch monitoring PID %d)", pid))
  }
  message(sprintf("[rNotify] ========================================================"))
}

capitalize <- function(s) {
  if (!nzchar(s)) return(s)
  paste0(toupper(substr(s, 1, 1)), substr(s, 2, nchar(s)))
}
