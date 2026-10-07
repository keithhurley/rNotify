#' Cheap Yellow Display (CYD) ESP32 Hardware Channel
#'
#' Transmits real-time job status and progress telemetry to an ESP32 CYD module
#' (2.8" or 2.4" 320x240 TFT LCD) over Wi-Fi via a lightweight REST HTTP endpoint.
#'
#' @param host IP address or hostname of the CYD module (e.g. "192.168.1.150").
#'   Defaults to \code{Sys.getenv("CYD_HOST", "127.0.0.1")}.
#' @param port HTTP port on the CYD module (default: 80).
#' @param path Endpoint path on the CYD (default: "/api/notify").
#' @param min_level Granularity level: "inner" (default, enables desk screen live updates)
#'   or "outer" (milestones only).
#' @param events Vector of event types to dispatch.
#' @param throttle_sec Minimum interval in seconds between CYD screen updates (default: 2.0).
#' @param timeout_sec HTTP request timeout in seconds (default: 2.0).
#' @return An \code{rnotify_channel} object.
#' @export
channel_cyd <- function(host = Sys.getenv("CYD_HOST", "127.0.0.1"),
                        port = 80,
                        path = "/api/notify",
                        min_level = "inner",
                        events = c("start", "progress", "step", "complete", "error", "catastrophic"),
                        throttle_sec = 2.0,
                        timeout_sec = 2.0) {
  handler <- function(payload) {
    if (!nzchar(host)) {
      warning("[rNotify: CYD] CYD host is not configured.", call. = FALSE)
      return(invisible(FALSE))
    }

    # Color and label mapping
    status_map <- switch(payload$event,
      start        = list(text = "STARTED",  color = "#00CCFF"),
      progress     = list(text = "RUNNING",  color = "#33DD66"),
      step         = list(text = "RUNNING",  color = "#33DD66"),
      complete     = list(text = "COMPLETE", color = "#00FF00"),
      error        = list(text = "FAILED",   color = "#FF3333"),
      catastrophic = list(text = "CRASHED",  color = "#FF0000")
    )

    # Format step information
    step_info <- ""
    if (!is.null(payload$progress$step) && !is.null(payload$progress$total)) {
      step_info <- sprintf("%s / %s", payload$progress$step, payload$progress$total)
    }

    inner_info <- ""
    if (!is.null(payload$progress$inner_step) && !is.null(payload$progress$inner_total)) {
      inner_info <- sprintf("%s / %s", payload$progress$inner_step, payload$progress$inner_total)
    }

    cyd_body <- list(
      title        = payload$title,
      event        = payload$event,
      status_text  = status_map$text,
      status_color = status_map$color,
      progress_pct = if (!is.na(payload$progress$pct)) as.integer(round(payload$progress$pct)) else 0L,
      step_info    = step_info,
      inner_pct    = if (!is.na(payload$progress$inner_pct)) as.integer(round(payload$progress$inner_pct)) else 0L,
      inner_info   = inner_info,
      message      = payload$message,
      elapsed      = payload$progress$elapsed_fmt,
      eta          = payload$progress$eta_fmt,
      channels     = payload$channels_active
    )

    json_str <- jsonlite::toJSON(cyd_body, auto_unbox = TRUE)
    url <- sprintf("http://%s:%d%s", host, as.integer(port), path)

    h <- curl::new_handle()
    curl::handle_setopt(
      h,
      customrequest = "POST",
      postfields = json_str,
      timeout = timeout_sec,
      connecttimeout = timeout_sec
    )
    curl::handle_setheaders(h, "Content-Type" = "application/json")

    res <- curl::curl_fetch_memory(url, handle = h)
    if (res$status_code >= 400) {
      stop(sprintf("CYD HTTP %d: %s", res$status_code, rawToChar(res$content)))
    }

    invisible(TRUE)
  }

  new_channel(
    name = "cyd",
    handler = handler,
    min_level = min_level,
    events = events,
    throttle_sec = throttle_sec,
    host = host,
    port = port
  )
}
