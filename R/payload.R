#' Standardized Notification Payload Constructor
#'
#' Builds the strongly-typed internal payload data structure for rNotify events.
#'
#' @param event Event type: "start", "progress", "step", "complete", "error", or "catastrophic".
#' @param title Job title or description.
#' @param message Human-readable status or milestone message.
#' @param job_id Unique identifier for the job.
#' @param step Current completed outer step count.
#' @param total Total expected outer steps.
#' @param elapsed_sec Total elapsed seconds since job start.
#' @param inner_step Current completed inner step count for nested loops.
#' @param inner_total Total inner steps for current subtask.
#' @param inner_message Status message for the inner loop.
#' @param channels_active Vector of channel names active for this dispatch.
#' @param error_message Error message string if an error occurred.
#' @param call_stack Character string or vector of call stack if available.
#' @param custom_stats Named list of user-provided metrics.
#' @return An S3 object of class \code{rnotify_payload}.
#' @export
new_payload <- function(event = c("start", "progress", "step", "complete", "error", "catastrophic"),
                        title = "R Job",
                        message = "",
                        job_id = NULL,
                        step = NULL,
                        total = NULL,
                        elapsed_sec = 0,
                        inner_step = NULL,
                        inner_total = NULL,
                        inner_message = NULL,
                        channels_active = character(),
                        error_message = NULL,
                        call_stack = NULL,
                        custom_stats = list()) {
  event <- match.arg(event)

  if (is.null(job_id)) {
    job_id <- sprintf("job_%s_%04d", format(Sys.time(), "%Y%m%d_%H%M%S"), sample(1000:9999, 1))
  }

  status <- switch(event,
    start        = "running",
    progress     = "running",
    step         = "running",
    complete     = "success",
    error        = "failed",
    catastrophic = "crashed"
  )

  # Progress and ETA calculations
  pct <- NA_real_
  eta <- list(eta_sec = NA_real_, eta_fmt = "--:--:--", eta_timestamp = NA_character_)

  if (!is.null(step) && !is.null(total) && total > 0) {
    if (!is.null(inner_step) && !is.null(inner_total) && inner_total > 0) {
      composite_step <- (max(0, step - 1)) + (inner_step / inner_total)
      pct <- round((composite_step / total) * 100, 1)
      eta <- calc_eta(elapsed_sec, composite_step, total)
    } else {
      pct <- round((step / total) * 100, 1)
      eta <- calc_eta(elapsed_sec, step, total)
    }
  }

  inner_pct <- NA_real_
  if (!is.null(inner_step) && !is.null(inner_total) && inner_total > 0) {
    inner_pct <- round((inner_step / inner_total) * 100, 1)
  }

  progress_info <- list(
    step          = step,
    total         = total,
    pct           = pct,
    elapsed_sec   = round(elapsed_sec, 1),
    elapsed_fmt   = format_duration(elapsed_sec),
    eta_sec       = eta$eta_sec,
    eta_fmt       = eta$eta_fmt,
    eta_timestamp = eta$eta_timestamp,
    inner_step    = inner_step,
    inner_total   = inner_total,
    inner_pct     = inner_pct,
    inner_message = inner_message
  )

  sys_info <- Sys.info()
  system_meta <- list(
    host      = as.character(sys_info["nodename"]),
    user      = as.character(sys_info["user"]),
    os        = as.character(sys_info["sysname"]),
    pid       = Sys.getpid(),
    r_version = R.version.string
  )

  payload <- list(
    job_id          = job_id,
    title           = title,
    event           = event,
    status          = status,
    timestamp       = current_iso8601(),
    message         = message,
    progress        = progress_info,
    system          = system_meta,
    channels_active = channels_active,
    details         = list(
      error_message = error_message,
      call_stack    = call_stack,
      custom_stats  = custom_stats
    )
  )

  class(payload) <- c("rnotify_payload", "list")
  payload
}

#' Convert rNotify Payload to Formatted Summary Text
#'
#' Generates clean, human-readable plain text or markdown for push notifications and emails.
#'
#' @param x An \code{rnotify_payload} object.
#' @param ... Additional arguments.
#' @return Character string.
#' @export
as_summary_text <- function(x, ...) {
  icon <- switch(x$event,
    start        = "\U0001F680",
    progress     = "\u23F3",
    step         = "\U0001F4CC",
    complete     = "\u2705",
    error        = "\u274C",
    catastrophic = "\U0001F6A8"
  )

  status_label <- switch(x$event,
    start        = "STARTED",
    progress     = sprintf("PROGRESS (%.1f%%)", if (!is.na(x$progress$pct)) x$progress$pct else 0),
    step         = "MILESTONE",
    complete     = "COMPLETED",
    error        = "JOB FAILED",
    catastrophic = "CRITICAL: R SESSION CRASHED"
  )

  lines <- c(
    sprintf("%s [%s] %s", icon, status_label, x$title),
    ""
  )

  if (nzchar(x$message)) {
    lines <- c(lines, x$message)
  }

  if (!is.na(x$progress$pct) && !is.null(x$progress$step)) {
    step_str <- sprintf("Step: %s/%s (%.1f%%)", x$progress$step, x$progress$total, x$progress$pct)
    if (!is.null(x$progress$inner_step)) {
      step_str <- sprintf("%s | Subtask: %s/%s (%.1f%%)",
                          step_str, x$progress$inner_step, x$progress$inner_total,
                          if (!is.na(x$progress$inner_pct)) x$progress$inner_pct else 0)
    }
    lines <- c(lines, step_str)
  }

  if (x$event %in% c("progress", "step", "complete", "error")) {
    timing_str <- sprintf("Elapsed: %s", x$progress$elapsed_fmt)
    if (!is.na(x$progress$eta_sec) && !(x$event %in% c("complete", "error"))) {
      timing_str <- sprintf("%s | ETA: %s", timing_str, x$progress$eta_fmt)
    }
    lines <- c(lines, timing_str)
  }

  if (!is.null(x$details$error_message)) {
    lines <- c(lines, "", sprintf("Error: %s", x$details$error_message))
    if (!is.null(x$details$call_stack)) {
      lines <- c(lines, "Stack trace:", x$details$call_stack)
    }
  }

  if (x$event == "catastrophic") {
    lines <- c(
      lines,
      "",
      sprintf("Session PID %d terminated abruptly without clean exit.", x$system$pid),
      "No further notifications are forthcoming. Job status is UNKNOWN."
    )
  }

  lines <- c(lines, "", sprintf("Host: %s (PID %d) | %s", x$system$host, x$system$pid, x$timestamp))
  paste(lines, collapse = "\n")
}

#' Format Method for rNotify Payload
#'
#' @param x An \code{rnotify_payload} object.
#' @param ... Additional arguments.
#' @return Formatted character string.
#' @export
format.rnotify_payload <- function(x, ...) {
  as_summary_text(x, ...)
}

#' Print Method for rNotify Payload
#'
#' @param x An \code{rnotify_payload} object.
#' @param ... Additional arguments.
#' @export
print.rnotify_payload <- function(x, ...) {
  cat(as_summary_text(x), "\n")
  invisible(x)
}
