#' R6 Class Representing a Stateful Notification Job
#'
#' @importFrom R6 R6Class
#' @export
NotifyJob <- R6::R6Class("NotifyJob",
  public = list(
    #' @field title Job title or label.
    title = NULL,

    #' @field job_id Unique identifier for the job.
    job_id = NULL,

    #' @field channels List of active \code{rnotify_channel} objects.
    channels = list(),

    #' @field total_steps Total expected outer steps.
    total_steps = NULL,

    #' @field start_time POSIXct timestamp when the job started.
    start_time = NULL,

    #' @field current_step Current outer step number.
    current_step = 0,

    #' @field throttler Throttle controller instance.
    throttler = NULL,

    #' @field sentinel Sentinel controller instance.
    sentinel = NULL,

    #' @field is_running Logical indicating if the job is active.
    is_running = FALSE,

    #' Initialize a new NotifyJob
    #'
    #' @param title Job title.
    #' @param channels Specification of channels ("all", list, or vector of names).
    #' @param total_steps Total expected steps for outer loop.
    #' @param throttle_sec Time throttle in seconds.
    #' @param milestones Percentage milestone thresholds, e.g. \code{c(25, 50, 75, 100)}.
    #' @param pct_step Percentage interval trigger, e.g. \code{10}.
    #' @param min_step_change Minimum step change between dispatches.
    #' @param use_sentinel Logical indicating whether to launch crash sentinel daemon.
    #' @param announce Logical indicating whether to announce active channels on init.
    initialize = function(title = "R Job",
                          channels = "all",
                          total_steps = NULL,
                          throttle_sec = 60,
                          milestones = NULL,
                          pct_step = NULL,
                          min_step_change = NULL,
                          use_sentinel = TRUE,
                          announce = TRUE) {
      self$title <- title
      self$job_id <- sprintf("job_%s_%04d", format(Sys.time(), "%Y%m%d_%H%M%S"), sample(1000:9999, 1))
      self$channels <- resolve_channels(channels)
      self$total_steps <- total_steps

      self$throttler <- create_throttler(
        throttle_sec = throttle_sec,
        milestones = milestones,
        pct_step = pct_step,
        min_step_change = min_step_change
      )

      if (isTRUE(announce)) {
        announce_channels(
          title = self$title,
          channels = self$channels,
          pid = Sys.getpid(),
          sentinel_active = isTRUE(use_sentinel)
        )
      }

      if (isTRUE(use_sentinel)) {
        self$sentinel <- start_sentinel(
          job_id = self$job_id,
          title = self$title,
          channels = self$channels,
          parent_pid = Sys.getpid()
        )
      }
    },

    #' Start the Job and Dispatch Initial Notification
    #'
    #' @param message Optional message string.
    start = function(message = "Job execution initiated.") {
      self$start_time <- Sys.time()
      self$is_running <- TRUE

      channel_names <- vapply(self$channels, function(c) c$name, character(1))

      payload <- new_payload(
        event = "start",
        title = self$title,
        message = message,
        job_id = self$job_id,
        total = self$total_steps,
        channels_active = channel_names
      )

      self$dispatch(payload, force = TRUE)
      invisible(self)
    },

    #' Report Progress
    #'
    #' @param step Current outer step number.
    #' @param message Status message.
    #' @param total Total outer steps (overrides initial total_steps if supplied).
    #' @param inner_step Current inner step number for nested loops.
    #' @param inner_total Total inner steps for nested loops.
    #' @param inner_message Status message for the inner loop.
    #' @param force Force dispatch bypassing throttlers.
    progress = function(step = NULL,
                        message = "",
                        total = NULL,
                        inner_step = NULL,
                        inner_total = NULL,
                        inner_message = NULL,
                        force = FALSE) {
      if (!self$is_running) {
        self$start()
      }

      if (!is.null(step)) self$current_step <- step
      tot <- if (!is.null(total)) total else self$total_steps

      elapsed <- as.numeric(difftime(Sys.time(), self$start_time, units = "secs"))

      # Check master job throttler
      if (!isTRUE(force)) {
        check_step <- if (!is.null(inner_step) && !is.null(inner_total) && !is.null(tot)) {
          (max(0, self$current_step - 1)) + (inner_step / inner_total)
        } else {
          self$current_step
        }

        if (!self$throttler$should_dispatch(step = check_step, total = tot, force = FALSE)) {
          # Still touch sentinel heartbeat
          if (!is.null(self$sentinel)) self$sentinel$touch()
          return(invisible(self))
        }
      }

      channel_names <- vapply(self$channels, function(c) c$name, character(1))

      payload <- new_payload(
        event = "progress",
        title = self$title,
        message = message,
        job_id = self$job_id,
        step = self$current_step,
        total = tot,
        elapsed_sec = elapsed,
        inner_step = inner_step,
        inner_total = inner_total,
        inner_message = inner_message,
        channels_active = channel_names
      )

      self$dispatch(payload, is_inner = !is.null(inner_step))
      self$throttler$record_dispatch(step = self$current_step, total = tot)

      if (!is.null(self$sentinel)) self$sentinel$touch()
      invisible(self)
    },

    #' Report an Unmetered Milestone Step
    #'
    #' @param message Milestone description.
    step = function(message = "") {
      self$progress(message = message, force = TRUE)
      invisible(self)
    },

    #' Create a Nested Subtask for Inner Loops
    #'
    #' @param title Subtask title.
    #' @param total_steps Total steps in this inner loop.
    #' @param step_num Current outer step index.
    #' @return An environment acting as a subtask controller.
    subtask = function(title, total_steps = NULL, step_num = NULL) {
      parent_job <- self
      if (!is.null(step_num)) parent_job$current_step <- step_num

      sub <- new.env(parent = emptyenv())
      sub$title <- title
      sub$total_steps <- total_steps

      sub$progress = function(step, message = "") {
        parent_job$progress(
          step = parent_job$current_step,
          total = parent_job$total_steps,
          inner_step = step,
          inner_total = sub$total_steps,
          inner_message = sprintf("[%s] %s", sub$title, message)
        )
      }

      sub$complete = function(message = sprintf("Subtask '%s' completed.", sub$title)) {
        parent_job$progress(
          step = parent_job$current_step,
          total = parent_job$total_steps,
          inner_step = sub$total_steps,
          inner_total = sub$total_steps,
          inner_message = message,
          force = TRUE
        )
      }

      sub
    },

    #' Complete the Job Successfully
    #'
    #' @param message Completion summary message.
    #' @param custom_stats Optional list of metrics to include.
    complete = function(message = "Job completed successfully.", custom_stats = list()) {
      if (!self$is_running) return(invisible(self))

      elapsed <- as.numeric(difftime(Sys.time(), self$start_time, units = "secs"))
      self$is_running <- FALSE

      if (!is.null(self$sentinel)) {
        self$sentinel$stop(status = "COMPLETED")
      }

      channel_names <- vapply(self$channels, function(c) c$name, character(1))

      payload <- new_payload(
        event = "complete",
        title = self$title,
        message = message,
        job_id = self$job_id,
        step = self$total_steps,
        total = self$total_steps,
        elapsed_sec = elapsed,
        channels_active = channel_names,
        custom_stats = custom_stats
      )

      self$dispatch(payload, force = TRUE)
      invisible(self)
    },

    #' Handle Job Failure
    #'
    #' @param e Error object or error message string.
    #' @param message Optional context message.
    error = function(e, message = "Job encountered an unhandled error.") {
      elapsed <- if (!is.null(self$start_time)) {
        as.numeric(difftime(Sys.time(), self$start_time, units = "secs"))
      } else {
        0
      }
      self$is_running <- FALSE

      if (!is.null(self$sentinel)) {
        self$sentinel$stop(status = "FAILED")
      }

      err_str <- if (inherits(e, "error") || inherits(e, "condition")) conditionMessage(e) else as.character(e)
      call_str <- if (inherits(e, "error") && !is.null(conditionCall(e))) deparse(conditionCall(e)) else NULL

      channel_names <- vapply(self$channels, function(c) c$name, character(1))

      payload <- new_payload(
        event = "error",
        title = self$title,
        message = message,
        job_id = self$job_id,
        step = self$current_step,
        total = self$total_steps,
        elapsed_sec = elapsed,
        channels_active = channel_names,
        error_message = err_str,
        call_stack = call_str
      )

      self$dispatch(payload, force = TRUE)
      invisible(self)
    },

    #' Internal Dispatch to Active Channels
    #'
    #' @param payload \code{rnotify_payload} object.
    #' @param is_inner Logical indicating inner loop origin.
    #' @param force Logical to bypass throttles.
    dispatch = function(payload, is_inner = FALSE, force = FALSE) {
      for (ch in self$channels) {
        safe_dispatch(ch, payload, is_inner = is_inner)
      }
    }
  )
)

#' Initialize and Return a NotifyJob
#'
#' Factory function to create a new \code{NotifyJob} instance.
#'
#' @param title Job title or label.
#' @param channels Specification of channels ("all", list, or vector of names).
#' @param total_steps Total expected steps for outer loop.
#' @param throttle_sec Time throttle in seconds (default: 60).
#' @param milestones Percentage milestone thresholds, e.g. \code{c(25, 50, 75, 100)}.
#' @param pct_step Percentage interval trigger, e.g. \code{10}.
#' @param min_step_change Minimum step change between dispatches.
#' @param use_sentinel Logical indicating whether to launch crash sentinel daemon (default: TRUE).
#' @param announce Logical indicating whether to announce active channels on init (default: TRUE).
#' @return A \code{NotifyJob} R6 object.
#' @export
notify_job <- function(title = "R Job",
                       channels = "all",
                       total_steps = NULL,
                       throttle_sec = 60,
                       milestones = NULL,
                       pct_step = NULL,
                       min_step_change = NULL,
                       use_sentinel = TRUE,
                       announce = TRUE) {
  NotifyJob$new(
    title = title,
    channels = channels,
    total_steps = total_steps,
    throttle_sec = throttle_sec,
    milestones = milestones,
    pct_step = pct_step,
    min_step_change = min_step_change,
    use_sentinel = use_sentinel,
    announce = announce
  )
}
