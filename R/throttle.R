#' Throttling and Debouncing Engine for rNotify
#'
#' Provides rich throttling controls across single-stage workflows, nested loops,
#' and outer milestones to avoid flooding communication channels.
#'
#' @name rnotify_throttle
#' @keywords internal
NULL

#' Create a Throttle Controller
#'
#' @param throttle_sec Minimum interval in seconds between successive notifications.
#'   Default is NULL (no time throttle).
#' @param milestones Numeric vector of progress percentage milestones to trigger on,
#'   e.g. \code{c(25, 50, 75, 100)}. Default is NULL.
#' @param pct_step Percentage interval to trigger on, e.g. \code{10} for every 10%. Default is NULL.
#' @param min_step_change Minimum integer steps advanced before allowing another progress notification.
#' @return An environment acting as a stateful throttle controller.
#' @export
create_throttler <- function(throttle_sec = NULL,
                             milestones = NULL,
                             pct_step = NULL,
                             min_step_change = NULL) {
  env <- new.env(parent = emptyenv())
  env$throttle_sec     <- throttle_sec
  env$milestones       <- if (!is.null(milestones)) sort(unique(milestones)) else NULL
  env$pct_step         <- pct_step
  env$min_step_change  <- min_step_change

  env$last_dispatch_time <- as.numeric(Sys.time()) - 999999
  env$last_step          <- -999999
  env$last_pct           <- -1
  env$fired_milestones   <- numeric()

  # Check if a notification should be emitted
  env$should_dispatch <- function(step = NULL, total = NULL, force = FALSE) {
    if (isTRUE(force)) return(TRUE)

    now <- as.numeric(Sys.time())

    # Calculate current percentage if step and total are given
    current_pct <- NA_real_
    if (!is.null(step) && !is.null(total) && total > 0) {
      current_pct <- (step / total) * 100
    }

    # 1. Milestone check
    milestone_hit <- FALSE
    if (!is.null(env$milestones) && !is.na(current_pct)) {
      unfired <- setdiff(env$milestones, env$fired_milestones)
      eligible <- unfired[current_pct >= unfired]
      if (length(eligible) > 0) {
        milestone_hit <- TRUE
      }
    }

    # 2. Percentage step check (e.g. every 10%)
    pct_step_hit <- FALSE
    if (!is.null(env$pct_step) && !is.na(current_pct)) {
      curr_bucket <- floor(current_pct / env$pct_step)
      last_bucket <- floor(env$last_pct / env$pct_step)
      if (curr_bucket > last_bucket && curr_bucket > 0) {
        pct_step_hit <- TRUE
      }
    }

    # If milestone mode was requested
    if (!is.null(env$milestones)) {
      if (milestone_hit) return(TRUE)
      # If no time throttle or pct_step is configured, don't fire outside milestones
      if (is.null(env$throttle_sec) && is.null(env$pct_step)) {
        return(FALSE)
      }
    }

    # If pct_step mode was requested
    if (!is.null(env$pct_step)) {
      if (pct_step_hit) return(TRUE)
      if (is.null(env$throttle_sec)) {
        return(FALSE)
      }
    }

    # 3. Minimum step change check
    if (!is.null(env$min_step_change) && !is.null(step)) {
      if ((step - env$last_step) < env$min_step_change) {
        return(FALSE)
      }
    }

    # 4. Time interval throttle check
    if (!is.null(env$throttle_sec)) {
      time_elapsed <- now - env$last_dispatch_time
      if (time_elapsed < env$throttle_sec) {
        return(FALSE)
      }
      return(TRUE)
    }

    TRUE
  }

  # Record that a dispatch has occurred
  env$record_dispatch <- function(step = NULL, total = NULL) {
    now <- as.numeric(Sys.time())
    env$last_dispatch_time <- now

    if (!is.null(step)) {
      env$last_step <- step
    }

    if (!is.null(step) && !is.null(total) && total > 0) {
      current_pct <- (step / total) * 100
      env$last_pct <- current_pct

      if (!is.null(env$milestones)) {
        reached <- env$milestones[current_pct >= env$milestones]
        env$fired_milestones <- union(env$fired_milestones, reached)
      }
    }
  }

  # Reset throttler state
  env$reset <- function() {
    env$last_dispatch_time <- as.numeric(Sys.time()) - 999999
    env$last_step          <- -999999
    env$last_pct           <- -1
    env$fired_milestones   <- numeric()
  }

  env
}
