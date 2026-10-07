#!/usr/bin/env Rscript
# rNotify Standalone Sentinel Daemon (Dead Man's Switch)
#
# This script runs as a detached independent background process.
# It monitors the parent R session PID and the job state file.
# If the parent PID vanishes without flagging clean completion,
# this daemon broadcasts an emergency catastrophic alert to all configured channels.

args <- commandArgs(trailingOnly = TRUE)
state_file <- NULL
poll_interval <- 10

for (a in args) {
  if (startsWith(a, "--state-file=")) {
    state_file <- sub("^--state-file=", "", a)
  } else if (startsWith(a, "--poll-interval=")) {
    poll_interval <- as.numeric(sub("^--poll-interval=", "", a))
  }
}

if (is.null(state_file) || !file.exists(state_file)) {
  quit(status = 1, save = "no")
}

# Cross-platform PID alive check
check_pid_alive <- function(pid) {
  if (is.null(pid) || is.na(pid)) return(FALSE)
  pid <- as.integer(pid)
  if (.Platform$OS.type == "windows") {
    out <- tryCatch({
      cmd <- sprintf("Get-Process -Id %d -ErrorAction SilentlyContinue", pid)
      res <- system2("powershell", c("-NoProfile", "-Command", cmd), stdout = TRUE, stderr = FALSE)
      length(res) > 0 && any(grepl(as.character(pid), res))
    }, error = function(e) FALSE)
    return(isTRUE(out))
  } else {
    res <- tryCatch(system2("kill", c("-0", as.character(pid)), stdout = FALSE, stderr = FALSE), error = function(e) 1)
    return(identical(res, 0L))
  }
}

# Read initial state
state <- tryCatch(readRDS(state_file), error = function(e) NULL)
if (is.null(state)) {
  quit(status = 1, save = "no")
}

parent_pid <- state$parent_pid
job_id     <- state$job_id
title      <- state$title
channels   <- state$channels

# Main monitoring loop
repeat {
  Sys.sleep(poll_interval)

  # Re-read state
  curr_state <- tryCatch(readRDS(state_file), error = function(e) NULL)
  if (!is.null(curr_state)) {
    if (curr_state$status %in% c("COMPLETED", "CLEAN_EXIT", "FAILED", "STOPPED")) {
      # Parent finished cleanly or handled its own error
      tryCatch(unlink(state_file), error = function(e) NULL)
      quit(status = 0, save = "no")
    }
  }

  # Check if parent process is still alive
  if (!check_pid_alive(parent_pid)) {
    # Parent PID has vanished unexpectedly!
    # Double-check state one final time
    final_state <- tryCatch(readRDS(state_file), error = function(e) NULL)
    if (!is.null(final_state) && final_state$status %in% c("COMPLETED", "CLEAN_EXIT", "FAILED")) {
      tryCatch(unlink(state_file), error = function(e) NULL)
      quit(status = 0, save = "no")
    }

    # CRITICAL: Catastrophic crash detected!
    # Load rNotify library or evaluate dispatch
    suppressPackageStartupMessages({
      requireNamespace("rNotify", quietly = TRUE)
    })

    # Construct catastrophic payload
    emergency_payload <- list(
      job_id          = job_id,
      title           = title,
      event           = "catastrophic",
      status          = "crashed",
      timestamp       = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
      message         = sprintf("R session (PID %d) terminated abruptly without clean exit! Job status is UNKNOWN.", parent_pid),
      progress        = list(
        step = NA, total = NA, pct = NA_real_,
        elapsed_sec = NA_real_, elapsed_fmt = "--:--:--",
        eta_sec = NA_real_, eta_fmt = "--:--:--", eta_timestamp = NA_character_,
        inner_step = NULL, inner_total = NULL, inner_pct = NA_real_, inner_message = NULL
      ),
      system          = list(
        host = as.character(Sys.info()["nodename"]),
        user = as.character(Sys.info()["user"]),
        os = as.character(Sys.info()["sysname"]),
        pid = parent_pid,
        r_version = R.version.string
      ),
      channels_active = vapply(channels, function(c) c$name, character(1)),
      details         = list(
        error_message = "Process vanished unexpectedly (segfault, crash, kill, or system shutdown).",
        call_stack = NULL,
        custom_stats = list()
      )
    )
    class(emergency_payload) <- c("rnotify_payload", "list")

    # Broadcast emergency alert across all channels
    for (ch in channels) {
      tryCatch({
        ch$handler(emergency_payload)
      }, error = function(e) NULL)
    }

    # Remove state file and exit
    tryCatch(unlink(state_file), error = function(e) NULL)
    quit(status = 0, save = "no")
  }
}
