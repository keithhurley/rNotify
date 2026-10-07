#' Base Channel Interface and Safe Dispatch Wrapper
#'
#' All notification channels (Pushover, ntfy, CYD, Email, Desktop, Webhook)
#' inherit from this base abstraction to guarantee fault isolation,
#' granularity filtering, and individual channel throttling.
#'
#' @name rnotify_channel_base
#' @keywords internal
NULL

#' Construct an rNotify Channel
#'
#' @param name Identifier for the channel (e.g., "pushover", "cyd").
#' @param handler A function accepting \code{payload} of class \code{rnotify_payload}.
#' @param min_level Granularity level: "outer" (receives outer loop/job milestones only)
#'   or "inner" (also receives high-frequency inner loop iterations).
#' @param events Character vector of event types this channel responds to. Default is all events:
#'   \code{c("start", "progress", "step", "complete", "error", "catastrophic")}.
#' @param throttle_sec Optional channel-specific time throttle in seconds.
#' @param ... Additional metadata stored on the channel object.
#' @return An S3 object of class \code{rnotify_channel}.
#' @export
new_channel <- function(name,
                        handler,
                        min_level = c("outer", "inner"),
                        events = c("start", "progress", "step", "complete", "error", "catastrophic"),
                        throttle_sec = NULL,
                        ...) {
  min_level <- match.arg(min_level)

  throttler <- create_throttler(throttle_sec = throttle_sec)

  channel <- list(
    name         = name,
    handler      = handler,
    min_level    = min_level,
    events       = events,
    throttle_sec = throttle_sec,
    throttler    = throttler,
    meta         = list(...)
  )

  class(channel) <- c(sprintf("rnotify_channel_%s", name), "rnotify_channel", "list")
  channel
}

#' Safely Dispatch Payload to a Channel with Full Fault Isolation
#'
#' Guarantees that a failed network call, expired token, or timeout never
#' interrupts or crashes the calling R script.
#'
#' @param channel An \code{rnotify_channel} object.
#' @param payload An \code{rnotify_payload} object.
#' @param is_inner Logical indicating if this event originated from an inner loop subtask.
#' @return Logical TRUE if dispatched successfully, FALSE if skipped or caught error.
#' @export
safe_dispatch <- function(channel, payload, is_inner = FALSE) {
  if (!inherits(channel, "rnotify_channel")) {
    return(FALSE)
  }

  # 1. Granularity filter: if inner loop and channel is outer-only, skip silently
  if (isTRUE(is_inner) && identical(channel$min_level, "outer")) {
    return(FALSE)
  }

  # 2. Event filter: check if channel listens to this event
  if (!is.null(channel$events) && !(payload$event %in% channel$events)) {
    return(FALSE)
  }

  # 3. Channel-level throttling check (bypass throttle on critical events)
  force_dispatch <- payload$event %in% c("start", "complete", "error", "catastrophic")
  step_val <- if (!is.null(payload$progress$inner_step)) payload$progress$inner_step else payload$progress$step
  total_val <- if (!is.null(payload$progress$inner_total)) payload$progress$inner_total else payload$progress$total

  if (!channel$throttler$should_dispatch(step = step_val, total = total_val, force = force_dispatch)) {
    return(FALSE)
  }

  # 4. Safe execution with fault isolation
  sent <- tryCatch({
    channel$handler(payload)
    channel$throttler$record_dispatch(step = step_val, total = total_val)
    TRUE
  }, error = function(e) {
    err_msg <- sprintf("[rNotify] Delivery failed on channel '%s': %s", channel$name, e$message)
    rnotify_log(err_msg, level = "WARN")
    warning(err_msg, call. = FALSE, immediate. = FALSE)
    FALSE
  })

  sent
}

#' Print Method for rNotify Channel
#'
#' @param x An \code{rnotify_channel} object.
#' @param ... Additional arguments.
#' @export
print.rnotify_channel <- function(x, ...) {
  cat(sprintf("<rNotify Channel: %s>\n", x$name))
  cat(sprintf("  Level:  %s\n", x$min_level))
  cat(sprintf("  Events: %s\n", paste(x$events, collapse = ", ")))
  if (!is.null(x$throttle_sec)) {
    cat(sprintf("  Throttle: every %d seconds\n", x$throttle_sec))
  }
  invisible(x)
}
