#' ntfy.sh Open-Source Push Channel
#'
#' Publishes notifications to any ntfy topic on ntfy.sh or a self-hosted instance.
#'
#' @param topic Topic name on ntfy. Defaults to \code{Sys.getenv("NTFY_TOPIC", "rnotify")}.
#' @param server Base server URL. Defaults to \code{Sys.getenv("NTFY_SERVER", "https://ntfy.sh")}.
#' @param token Optional Bearer access token for private/authenticated topics. Defaults to \code{Sys.getenv("NTFY_TOKEN")}.
#' @param priority Priority integer (1 min, 3 default, 5 urgent).
#' @param tags Character vector of tags/emojis (e.g. \code{c("warning", "computer")}).
#' @param min_level Minimum granularity level: "outer" (default) or "inner".
#' @param events Vector of event types to dispatch.
#' @param throttle_sec Optional channel throttle in seconds.
#' @param timeout_sec HTTP request timeout in seconds (default: 5).
#' @return An \code{rnotify_channel} object.
#' @export
channel_ntfy <- function(topic = Sys.getenv("NTFY_TOPIC", "rnotify"),
                         server = Sys.getenv("NTFY_SERVER", "https://ntfy.sh"),
                         token = Sys.getenv("NTFY_TOKEN", ""),
                         priority = 3,
                         tags = NULL,
                         min_level = "outer",
                         events = c("start", "progress", "step", "complete", "error", "catastrophic"),
                         throttle_sec = NULL,
                         timeout_sec = 5) {
  handler <- function(payload) {
    if (!nzchar(topic)) {
      warning("[rNotify: ntfy] No topic specified.", call. = FALSE)
      return(invisible(FALSE))
    }

    # Dynamically select priority and tags based on event
    msg_priority <- priority
    auto_tags <- tags
    if (is.null(auto_tags)) auto_tags <- character()

    if (payload$event == "start") {
      auto_tags <- unique(c(auto_tags, "rocket", "clock"))
    } else if (payload$event == "complete") {
      auto_tags <- unique(c(auto_tags, "white_check_mark", "tada"))
    } else if (payload$event == "error") {
      msg_priority <- 5
      auto_tags <- unique(c(auto_tags, "x", "warning"))
    } else if (payload$event == "catastrophic") {
      msg_priority <- 5
      auto_tags <- unique(c(auto_tags, "skull", "rotating_light"))
    }

    url <- sprintf("%s/%s", sub("/+$", "", server), topic)
    body_text <- as_summary_text(payload)

    headers <- c(
      "Title"    = sprintf("[%s] %s", toupper(payload$status), payload$title),
      "Priority" = as.character(msg_priority)
    )

    if (length(auto_tags) > 0) {
      headers["Tags"] <- paste(auto_tags, collapse = ",")
    }

    if (nzchar(token)) {
      headers["Authorization"] <- sprintf("Bearer %s", token)
    }

    h <- curl::new_handle()
    curl::handle_setopt(
      h,
      customrequest = "POST",
      postfields = body_text,
      timeout = timeout_sec,
      connecttimeout = timeout_sec
    )
    curl::handle_setheaders(h, .list = as.list(headers))

    res <- curl::curl_fetch_memory(url, handle = h)
    if (res$status_code >= 400) {
      stop(sprintf("ntfy HTTP %d: %s", res$status_code, rawToChar(res$content)))
    }

    invisible(TRUE)
  }

  new_channel(
    name = "ntfy",
    handler = handler,
    min_level = min_level,
    events = events,
    throttle_sec = throttle_sec,
    topic = topic
  )
}
