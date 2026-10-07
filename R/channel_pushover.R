#' Pushover Mobile Push Channel
#'
#' Sends real-time notifications to iOS and Android devices via the Pushover API.
#'
#' @param user User or group key. Defaults to \code{Sys.getenv("PUSHOVER_USER")}.
#' @param token Application API token. Defaults to \code{Sys.getenv("PUSHOVER_TOKEN")}.
#' @param device Optional device name to target.
#' @param sound Optional alert sound name (e.g. "cosmic", "falling", "siren").
#' @param priority Default priority (-2 lowest, -1 low, 0 normal, 1 high, 2 emergency).
#' @param min_level Minimum granularity level: "outer" (default) or "inner".
#' @param events Vector of event types to dispatch.
#' @param throttle_sec Optional channel throttle in seconds.
#' @param timeout_sec HTTP request timeout in seconds (default: 5).
#' @return An \code{rnotify_channel} object.
#' @export
channel_pushover <- function(user = Sys.getenv("PUSHOVER_USER"),
                             token = Sys.getenv("PUSHOVER_TOKEN"),
                             device = NULL,
                             sound = NULL,
                             priority = 0,
                             min_level = "outer",
                             events = c("start", "progress", "step", "complete", "error", "catastrophic"),
                             throttle_sec = NULL,
                             timeout_sec = 5) {
  handler <- function(payload) {
    if (!nzchar(user) || !nzchar(token)) {
      warning("[rNotify: Pushover] PUSHOVER_USER or PUSHOVER_TOKEN is not configured.", call. = FALSE)
      return(invisible(FALSE))
    }

    # Dynamically bump priority on failure/catastrophic
    msg_priority <- priority
    if (payload$event %in% c("error", "catastrophic")) {
      msg_priority <- max(1, priority)
    }

    # Message sound
    msg_sound <- sound
    if (is.null(msg_sound)) {
      if (payload$event == "complete") msg_sound <- "magic"
      if (payload$event %in% c("error", "catastrophic")) msg_sound <- "falling"
    }

    body_text <- as_summary_text(payload)

    form_data <- list(
      token    = token,
      user     = user,
      title    = sprintf("[%s] %s", toupper(payload$status), payload$title),
      message  = body_text,
      priority = as.character(msg_priority)
    )

    if (!is.null(device) && nzchar(device)) form_data$device <- device
    if (!is.null(msg_sound) && nzchar(msg_sound)) form_data$sound <- msg_sound

    # Send POST via curl
    h <- curl::new_handle()
    curl::handle_setopt(
      h,
      timeout = timeout_sec,
      connecttimeout = timeout_sec
    )
    curl::handle_setform(h, .list = form_data)

    res <- curl::curl_fetch_memory("https://api.pushover.net/1/messages.json", handle = h)
    if (res$status_code >= 400) {
      err_text <- rawToChar(res$content)
      stop(sprintf("Pushover HTTP %d: %s", res$status_code, err_text))
    }

    invisible(TRUE)
  }

  new_channel(
    name = "pushover",
    handler = handler,
    min_level = min_level,
    events = events,
    throttle_sec = throttle_sec,
    user = user
  )
}
