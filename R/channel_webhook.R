#' Generic HTTP Webhook Channel
#'
#' Dispatches full notification payloads to any arbitrary HTTP/HTTPS webhook URL.
#'
#' @param url Target endpoint URL.
#' @param headers Named list or character vector of custom HTTP headers.
#' @param method HTTP method ("POST" or "PUT", default: "POST").
#' @param min_level Minimum granularity level: "outer" (default) or "inner".
#' @param events Vector of event types to dispatch.
#' @param throttle_sec Optional channel throttle in seconds.
#' @param timeout_sec HTTP request timeout in seconds (default: 5).
#' @return An \code{rnotify_channel} object.
#' @export
channel_webhook <- function(url,
                            headers = list("Content-Type" = "application/json"),
                            method = "POST",
                            min_level = "outer",
                            events = c("start", "progress", "step", "complete", "error", "catastrophic"),
                            throttle_sec = NULL,
                            timeout_sec = 5) {
  handler <- function(payload) {
    if (missing(url) || !nzchar(url)) {
      warning("[rNotify: Webhook] No URL specified.", call. = FALSE)
      return(invisible(FALSE))
    }

    json_str <- jsonlite::toJSON(unclass(payload), auto_unbox = TRUE, pretty = FALSE)

    h <- curl::new_handle()
    curl::handle_setopt(
      h,
      customrequest = method,
      postfields = json_str,
      timeout = timeout_sec,
      connecttimeout = timeout_sec
    )
    curl::handle_setheaders(h, .list = as.list(headers))

    res <- curl::curl_fetch_memory(url, handle = h)
    if (res$status_code >= 400) {
      stop(sprintf("Webhook HTTP %d: %s", res$status_code, rawToChar(res$content)))
    }

    invisible(TRUE)
  }

  new_channel(
    name = "webhook",
    handler = handler,
    min_level = min_level,
    events = events,
    throttle_sec = throttle_sec,
    url = url
  )
}
