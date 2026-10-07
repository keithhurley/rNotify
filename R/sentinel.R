#' Detached Background Crash Sentinel (Dead Man's Switch)
#'
#' Spawns and manages an independent watcher process that detects if the
#' parent R session aborts, segfaults, or terminates without a clean exit.
#'
#' @name rnotify_sentinel
#' @keywords internal
NULL

#' Start the Background Sentinel Watcher Process
#'
#' @param job_id Unique job ID.
#' @param title Job title.
#' @param channels List of \code{rnotify_channel} objects.
#' @param parent_pid Integer PID of the main R session (default: \code{Sys.getpid()}).
#' @param poll_interval Integer check interval in seconds (default: 10).
#' @return An environment containing sentinel handles and methods.
#' @export
start_sentinel <- function(job_id,
                           title,
                           channels,
                           parent_pid = Sys.getpid(),
                           poll_interval = 10) {
  state_dir <- file.path(path.expand("~"), ".rnotify", "jobs")
  if (!dir.exists(state_dir)) {
    tryCatch(dir.create(state_dir, recursive = TRUE, showWarnings = FALSE), error = function(e) NULL)
  }

  state_file <- file.path(state_dir, sprintf("%s.rds", job_id))

  initial_state <- list(
    job_id         = job_id,
    title          = title,
    parent_pid     = parent_pid,
    channels       = channels,
    status         = "RUNNING",
    last_touch     = Sys.time()
  )

  saveRDS(initial_state, state_file)

  # Locate sentinel_daemon.R
  daemon_path <- system.file("sentinel", "sentinel_daemon.R", package = "rNotify")
  if (!nzchar(daemon_path) || !file.exists(daemon_path)) {
    # Check current package development location
    dev_path <- file.path("inst", "sentinel", "sentinel_daemon.R")
    if (file.exists(dev_path)) {
      daemon_path <- normalizePath(dev_path)
    }
  }

  sentinel_env <- new.env(parent = emptyenv())
  sentinel_env$state_file <- state_file
  sentinel_env$process <- NULL
  sentinel_env$active <- FALSE

  if (file.exists(daemon_path)) {
    rscript_bin <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")

    cmd_args <- c(
      shQuote(daemon_path),
      sprintf("--state-file=%s", state_file),
      sprintf("--poll-interval=%d", poll_interval)
    )

    tryCatch({
      # Spawn detached background process
      if (requireNamespace("callr", quietly = TRUE)) {
        proc <- callr::r_bg(
          function(daemon, sf, pi) {
            system2(
              file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript"),
              c(shQuote(daemon), sprintf("--state-file=%s", sf), sprintf("--poll-interval=%d", pi)),
              wait = FALSE, stdout = FALSE, stderr = FALSE
            )
          },
          args = list(daemon = daemon_path, sf = state_file, pi = poll_interval)
        )
        sentinel_env$process <- proc
      } else {
        system2(rscript_bin, cmd_args, wait = FALSE, stdout = FALSE, stderr = FALSE)
      }
      sentinel_env$active <- TRUE
    }, error = function(e) {
      rnotify_log(sprintf("Failed to spawn sentinel daemon: %s", e$message), level = "WARN")
    })
  }

  # Touch heartbeat
  sentinel_env$touch <- function() {
    if (file.exists(state_file)) {
      tryCatch({
        st <- readRDS(state_file)
        st$last_touch <- Sys.time()
        saveRDS(st, state_file)
      }, error = function(e) NULL)
    }
  }

  # Stop sentinel cleanly
  sentinel_env$stop <- function(status = "COMPLETED") {
    if (file.exists(state_file)) {
      tryCatch({
        st <- readRDS(state_file)
        st$status <- status
        saveRDS(st, state_file)
      }, error = function(e) NULL)
    }
    sentinel_env$active <- FALSE
  }

  sentinel_env
}
