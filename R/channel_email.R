#' Email Notification Channel
#'
#' Sends job completion, error, and status alerts via SMTP or blastula.
#'
#' @param to Character vector of recipient email addresses.
#' @param from Sender email address. Defaults to \code{Sys.getenv("RNOTIFY_EMAIL_FROM")}.
#' @param smtp_server SMTP server host. Defaults to \code{Sys.getenv("SMTP_SERVER")}.
#' @param smtp_port SMTP port (default: 587).
#' @param smtp_user SMTP username. Defaults to \code{Sys.getenv("SMTP_USER")}.
#' @param smtp_password SMTP password. Defaults to \code{Sys.getenv("SMTP_PASSWORD")}.
#' @param use_ssl Logical indicating whether to use TLS/SSL (default: TRUE).
#' @param min_level Minimum granularity level: "outer" (default).
#' @param events Vector of event types to dispatch. Default is major milestones only:
#'   \code{c("start", "complete", "error", "catastrophic")}.
#' @param throttle_sec Optional channel throttle in seconds.
#' @return An \code{rnotify_channel} object.
#' @export
channel_email <- function(to,
                          from = Sys.getenv("RNOTIFY_EMAIL_FROM", "rnotify@localhost"),
                          smtp_server = Sys.getenv("SMTP_SERVER"),
                          smtp_port = as.integer(Sys.getenv("SMTP_PORT", "587")),
                          smtp_user = Sys.getenv("SMTP_USER"),
                          smtp_password = Sys.getenv("SMTP_PASSWORD"),
                          use_ssl = TRUE,
                          min_level = "outer",
                          events = c("start", "complete", "error", "catastrophic"),
                          throttle_sec = NULL) {
  handler <- function(payload) {
    if (missing(to) || length(to) == 0 || !nzchar(to[1])) {
      warning("[rNotify: Email] No recipient specified.", call. = FALSE)
      return(invisible(FALSE))
    }

    if (!nzchar(smtp_server)) {
      warning("[rNotify: Email] SMTP_SERVER is not configured.", call. = FALSE)
      return(invisible(FALSE))
    }

    subject <- sprintf("[%s] %s - %s", toupper(payload$status), payload$title, payload$timestamp)
    body <- as_summary_text(payload)

    # Format standard RFC 2822 email message
    rfc_message <- paste(
      sprintf("From: %s", from),
      sprintf("To: %s", paste(to, collapse = ", ")),
      sprintf("Subject: %s", subject),
      "MIME-Version: 1.0",
      "Content-Type: text/plain; charset=utf-8",
      "",
      body,
      sep = "\r\n"
    )

    mail_url <- sprintf("smtp%s://%s:%d", if (isTRUE(use_ssl)) "s" else "", smtp_server, smtp_port)

    # Use curl::send_mail
    curl::send_mail(
      mail_from = from,
      mail_rcpt = to,
      message   = charToRaw(rfc_message),
      smtp_server = mail_url,
      use_ssl = if (isTRUE(use_ssl)) "try" else "none",
      username = if (nzchar(smtp_user)) smtp_user else NULL,
      password = if (nzchar(smtp_password)) smtp_password else NULL
    )

    invisible(TRUE)
  }

  new_channel(
    name = "email",
    handler = handler,
    min_level = min_level,
    events = events,
    throttle_sec = throttle_sec,
    to = to
  )
}
