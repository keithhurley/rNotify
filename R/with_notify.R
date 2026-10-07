#' Execute an Expression with Automatic Multi-Channel Notifications
#'
#' Wraps an entire code block, model run, or script within an isolated
#' notification harness. Automatically captures execution duration, announces
#' channels, manages the crash sentinel, dispatches completion summaries,
#' and catches unhandled errors without hiding tracebacks.
#'
#' @param expr Expression or code block to evaluate.
#' @param title Job title or description.
#' @param channels Specification of channels ("all", list, or vector of names).
#' @param total_steps Total expected steps if progress will be reported.
#' @param throttle_sec Time throttle in seconds.
#' @param milestones Percentage milestone thresholds, e.g. \code{c(25, 50, 75, 100)}.
#' @param pct_step Percentage interval trigger, e.g. \code{10}.
#' @param use_sentinel Logical indicating whether to launch crash sentinel daemon (default: TRUE).
#' @param announce Logical indicating whether to announce active channels on init (default: TRUE).
#' @return The evaluated result of \code{expr}.
#' @export
#' @examples
#' \dontrun{
#' res <- with_notify(
#'   title = "Monte Carlo Creel Model",
#'   channels = "all",
#'   expr = {
#'     notify_step("Loading data...")
#'     Sys.sleep(2)
#'     notify_step("Fitting distributions...")
#'     42
#'   }
#' )
#' }
with_notify <- function(expr,
                        title = "R Job",
                        channels = "all",
                        total_steps = NULL,
                        throttle_sec = 60,
                        milestones = NULL,
                        pct_step = NULL,
                        use_sentinel = TRUE,
                        announce = TRUE) {
  job <- notify_job(
    title = title,
    channels = channels,
    total_steps = total_steps,
    throttle_sec = throttle_sec,
    milestones = milestones,
    pct_step = pct_step,
    use_sentinel = use_sentinel,
    announce = announce
  )

  # Register active job in thread-local environment for notify_step/notify_progress
  old_job <- .rnotify_env$current_job
  .rnotify_env$current_job <- job
  on.exit({
    .rnotify_env$current_job <- old_job
  }, add = TRUE)

  job$start()

  completed_cleanly <- FALSE
  on.exit({
    if (!completed_cleanly && job$is_running) {
      # Emergency exit cleanup (e.g. user interrupted via Ctrl+C / Esc)
      job$error("Execution interrupted by user or R session exit.")
    }
  }, add = TRUE)

  result <- tryCatch({
    res <- withCallingHandlers(
      expr,
      error = function(e) {
        # Catch and notify immediately before bubbling up
        job$error(e, message = "Job failed with an unhandled runtime error.")
        completed_cleanly <<- TRUE
      }
    )
    completed_cleanly <- TRUE
    job$complete()
    res
  }, error = function(e) {
    # Re-throw original error so caller receives standard R error condition
    stop(e)
  })

  result
}

#' Access the Currently Active Enclosing Job
#'
#' @return The active \code{NotifyJob} object, or NULL if not within \code{with_notify}.
#' @export
notify_current_job <- function() {
  .rnotify_env$current_job
}

#' Report Progress from Inside with_notify Block or Directly on Job
#'
#' @param step Current step number or \code{NotifyJob} object.
#' @param total Total steps.
#' @param message Status message.
#' @param job Optional target \code{NotifyJob} instance.
#' @export
notify_progress <- function(step, total = NULL, message = "", job = NULL) {
  if (inherits(step, "NotifyJob")) {
    job <- step
    step <- if (!is.null(total)) total else 1L
    total <- NULL
  }
  if (is.null(job)) {
    job <- notify_current_job()
  }
  if (!is.null(job)) {
    job$progress(step = step, total = total, message = message)
  }
}

#' Report a Step Milestone from Inside with_notify Block or Directly on Job
#'
#' @param message Milestone description or a \code{NotifyJob} instance.
#' @param step Optional current step index.
#' @param job Optional target \code{NotifyJob} instance.
#' @export
notify_step <- function(message = "", step = NULL, job = NULL) {
  if (inherits(message, "NotifyJob")) {
    job <- message
    message <- ""
  }
  if (is.null(job)) {
    job <- notify_current_job()
  }
  if (!is.null(job)) {
    job$step(message = message, step = step)
  }
}
