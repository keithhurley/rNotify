#' Utility Functions for rNotify
#'
#' Internal helpers for formatting, timing, process monitoring, and safe I/O.
#'
#' @name rnotify_utils
#' @keywords internal
NULL

#' Format Duration in Seconds to HH:MM:SS
#'
#' @param seconds Numeric elapsed or ETA time in seconds.
#' @return Formatted character string, e.g. "01:23:45".
#' @export
format_duration <- function(seconds) {
  if (is.null(seconds) || is.na(seconds) || seconds < 0 || !is.finite(seconds)) {
    return("--:--:--")
  }
  sec <- as.integer(round(seconds))
  hrs <- sec %/% 3600
  rem <- sec %% 3600
  mins <- rem %/% 60
  secs <- rem %% 60
  sprintf("%02d:%02d:%02d", hrs, mins, secs)
}

#' Get Current Timestamp in ISO-8601 Format
#'
#' @return Formatted ISO-8601 string with local timezone.
#' @export
current_iso8601 <- function() {
  format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
}

#' Calculate Estimated Time Remaining (ETA)
#'
#' @param elapsed_sec Elapsed time in seconds.
#' @param current_step Current completed step count.
#' @param total_steps Total expected steps.
#' @return List with \code{eta_sec}, \code{eta_fmt}, and \code{eta_timestamp}.
#' @export
calc_eta <- function(elapsed_sec, current_step, total_steps) {
  if (is.null(total_steps) || is.na(total_steps) || total_steps <= 0 ||
      is.null(current_step) || is.na(current_step) || current_step <= 0) {
    return(list(
      eta_sec = NA_real_,
      eta_fmt = "--:--:--",
      eta_timestamp = NA_character_
    ))
  }

  if (current_step >= total_steps) {
    return(list(
      eta_sec = 0,
      eta_fmt = "00:00:00",
      eta_timestamp = current_iso8601()
    ))
  }

  rate <- elapsed_sec / current_step
  remaining_steps <- total_steps - current_step
  eta_sec <- rate * remaining_steps
  eta_time <- Sys.time() + eta_sec

  list(
    eta_sec = round(eta_sec, 1),
    eta_fmt = format_duration(eta_sec),
    eta_timestamp = format(eta_time, "%Y-%m-%dT%H:%M:%S%z")
  )
}

#' Check if an OS Process ID (PID) is Active
#'
#' Cross-platform process check.
#'
#' @param pid Integer process identifier.
#' @return Logical TRUE if process is currently running, FALSE otherwise.
#' @export
is_pid_alive <- function(pid) {
  if (is.null(pid) || is.na(pid)) return(FALSE)
  pid <- as.integer(pid)

  if (.Platform$OS.type == "windows") {
    # Use powershell quietly without triggering process exit warnings
    out <- tryCatch({
      cmd <- sprintf('if (Get-Process -Id %d -ErrorAction SilentlyContinue) { exit 0 } else { exit 1 }', pid)
      suppressWarnings(
        system2("powershell", c("-NoProfile", "-Command", cmd), stdout = FALSE, stderr = FALSE) == 0
      )
    }, error = function(e) FALSE)
    return(isTRUE(out))
  } else {
    # POSIX: kill -0 checks process existence without signaling
    res <- tryCatch(
      suppressWarnings(system2("kill", c("-0", as.character(pid)), stdout = FALSE, stderr = FALSE)),
      error = function(e) 1
    )
    return(identical(res, 0L))
  }
}

#' Internal Logging for rNotify
#'
#' Appends diagnostic messages to a local log file and optionally displays a warning.
#'
#' @param msg Character log message.
#' @param level Character log level: "INFO", "WARN", "ERROR".
#' @keywords internal
rnotify_log <- function(msg, level = "INFO") {
  log_dir <- file.path(path.expand("~"), ".rnotify")
  if (!dir.exists(log_dir)) {
    tryCatch(dir.create(log_dir, recursive = TRUE, showWarnings = FALSE), error = function(e) NULL)
  }
  log_file <- file.path(log_dir, "rnotify.log")
  timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  entry <- sprintf("[%s] [%s] %s\n", timestamp, level, msg)
  tryCatch(cat(entry, file = log_file, append = TRUE), error = function(e) NULL)
}
