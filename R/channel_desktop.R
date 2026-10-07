#' Desktop Notification and Audio Chime Channel
#'
#' Triggers native OS desktop toast notifications and audible completion/error chimes.
#'
#' @param sound Logical indicating whether to play an audio chime. Default is TRUE.
#' @param toast Logical indicating whether to display a desktop toast popup. Default is TRUE.
#' @param min_level Minimum granularity level: "outer" (default) or "inner".
#' @param events Vector of event types to dispatch. Default is \code{c("start", "step", "complete", "error", "catastrophic")}.
#' @param throttle_sec Optional channel throttle in seconds.
#' @return An \code{rnotify_channel} object.
#' @export
channel_desktop <- function(sound = TRUE,
                            toast = TRUE,
                            min_level = "outer",
                            events = c("start", "step", "complete", "error", "catastrophic"),
                            throttle_sec = NULL) {
  handler <- function(payload) {
    # 1. Audible alert
    if (isTRUE(sound)) {
      tryCatch({
        if (.Platform$OS.type == "windows") {
          freq <- switch(payload$event,
            complete     = 1000,
            error        = 400,
            catastrophic = 300,
            800
          )
          duration <- switch(payload$event,
            complete     = 250,
            error        = 600,
            catastrophic = 1000,
            150
          )
          cmd <- sprintf("[System.Console]::Beep(%d, %d)", freq, duration)
          system2("powershell", c("-NoProfile", "-Command", cmd), wait = FALSE, stdout = FALSE, stderr = FALSE)
        } else {
          cat("\a")
        }
      }, error = function(e) NULL)
    }

    # 2. Desktop Toast Notification
    if (isTRUE(toast)) {
      tryCatch({
        title_esc <- gsub("\"", "`\"", payload$title)
        msg_esc <- gsub("\"", "`\"", if (nzchar(payload$message)) payload$message else toupper(payload$status))

        if (.Platform$OS.type == "windows") {
          # PowerShell notification script
          ps_code <- sprintf(
            '$title = "%s"; $msg = "%s"; ' %+%
            'Add-Type -AssemblyName System.Windows.Forms; ' %+%
            '$notify = New-Object System.Windows.Forms.NotifyIcon; ' %+%
            '$notify.Icon = [System.Drawing.SystemIcons]::Information; ' %+%
            '$notify.Visible = $True; ' %+%
            '$notify.ShowBalloonTip(4000, $title, $msg, [System.Windows.Forms.ToolTipIcon]::Info);',
            title_esc, msg_esc
          )
          system2("powershell", c("-NoProfile", "-Command", ps_code), wait = FALSE, stdout = FALSE, stderr = FALSE)
        } else {
          # macOS terminal-notifier / Linux notify-send
          if (nzchar(Sys.which("notify-send"))) {
            system2("notify-send", c(shQuote(payload$title), shQuote(payload$message)), wait = FALSE)
          }
        }
      }, error = function(e) NULL)
    }

    invisible(TRUE)
  }

  new_channel(
    name = "desktop",
    handler = handler,
    min_level = min_level,
    events = events,
    throttle_sec = throttle_sec,
    sound = sound,
    toast = toast
  )
}

# Helper for string concatenation
`%+%` <- function(a, b) paste0(a, b)
