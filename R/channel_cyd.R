#' Cheap Yellow Display (CYD) ESP32 Hardware Channel
#'
#' Transmits real-time job status and progress telemetry to an ESP32 CYD module
#' (2.8" or 2.4" 320x240 TFT LCD) over Bluetooth Serial (SPP), USB Serial, or Wi-Fi HTTP.
#'
#' @param target Target destination: either a COM/serial port for Bluetooth/USB
#'   (e.g. \code{"COM8"}, \code{"COM10"}, \code{"/dev/rfcomm0"}), or an IP/hostname for Wi-Fi
#'   (e.g. \code{"192.168.1.150"}). Defaults to \code{Sys.getenv("CYD_BT_PORT", Sys.getenv("CYD_HOST", "127.0.0.1"))}.
#' @param transport Transport protocol: \code{"auto"} (default), \code{"bluetooth"},
#'   \code{"serial"}, or \code{"http"}. When \code{"auto"}, Bluetooth/serial is selected
#'   if \code{target} matches a serial/COM port pattern (e.g. \code{"COM3"}, \code{"/dev/tty*"}, \code{"/dev/rfcomm*"}),
#'   and HTTP is selected otherwise.
#' @param host Deprecated alias for \code{target} (for backwards compatibility).
#' @param port HTTP port on the CYD module (default: 80) when using HTTP transport,
#'   or serial/COM port when passed as a string (e.g. \code{"COM10"}).
#' @param baud Baud rate for Bluetooth/USB serial communication (default: 115200).
#' @param path Endpoint path on the CYD when using HTTP (default: "/api/notify").
#' @param min_level Granularity level: "inner" (default, enables desk screen live updates)
#'   or "outer" (milestones only).
#' @param events Vector of event types to dispatch.
#' @param throttle_sec Minimum interval in seconds between CYD screen updates (default: 2.0).
#' @param timeout_sec Request or connection timeout in seconds (default: 2.0).
#' @return An \code{rnotify_channel} object.
#' @export
channel_cyd <- function(target = NULL,
                        transport = c("auto", "bluetooth", "serial", "http"),
                        host = NULL,
                        port = NULL,
                        baud = 115200,
                        path = "/api/notify",
                        min_level = "inner",
                        events = c("start", "progress", "step", "complete", "error", "catastrophic"),
                        throttle_sec = 2.0,
                        timeout_sec = 2.0) {
  transport <- match.arg(transport)

  # Check if port was passed as a COM port: e.g. channel_cyd(port = "COM10")
  if (is.character(port) && grepl("^(COM[0-9]+|/dev/|bluetooth:)", port, ignore.case = TRUE)) {
    target <- port
    if (transport == "auto") transport <- "bluetooth"
    http_port <- 80L
  } else if (!is.null(host)) {
    target <- host
    http_port <- if (!is.null(port) && is.numeric(port)) as.integer(port) else 80L
  } else if (!is.null(target)) {
    http_port <- if (!is.null(port) && is.numeric(port)) as.integer(port) else 80L
  } else {
    # Check env vars
    bt_env <- Sys.getenv("CYD_BT_PORT", "")
    host_env <- Sys.getenv("CYD_HOST", "")
    port_env <- Sys.getenv("CYD_PORT", "")
    if (nzchar(bt_env)) {
      target <- bt_env
      if (transport == "auto") transport <- "bluetooth"
    } else if (nzchar(host_env)) {
      target <- host_env
    } else if (nzchar(port_env)) {
      target <- port_env
    } else {
      target <- "127.0.0.1"
    }
    http_port <- if (!is.null(port) && is.numeric(port)) as.integer(port) else 80L
  }

  # Auto-detect transport from target string
  if (transport == "auto") {
    if (grepl("^(COM[0-9]+|/dev/|bluetooth:)", target, ignore.case = TRUE)) {
      transport <- "bluetooth"
    } else {
      transport <- "http"
    }
  }

  # Clean target if prefixed
  target_clean <- sub("^bluetooth:", "", target, ignore.case = TRUE)

  # Persistent connection cache for serial/bluetooth
  con_env <- new.env(parent = emptyenv())
  con_env$con <- NULL

  close_serial_con <- function() {
    if (!is.null(con_env$con)) {
      tryCatch({
        close(con_env$con)
      }, error = function(e) NULL)
      con_env$con <- NULL
    }
  }

  write_serial <- function(port_name, json_str) {
    if (requireNamespace("serial", quietly = TRUE)) {
      # Escape double quotes for Tcl's string parser inside package serial
      tcl_str <- gsub('"', '\\"', json_str, fixed = TRUE)

      # Attempt to reuse or open connection
      if (is.null(con_env$con)) {
        con_name <- paste0("cyd_", gsub("[^A-Za-z0-9]", "_", port_name))
        c_obj <- serial::serialConnection(
          name = con_name,
          port = port_name,
          mode = sprintf("%d,n,8,1", as.integer(baud)),
          buffering = "none",
          newline = 1
        )
        tryCatch(open(c_obj), error = function(e) {
          stop(sprintf("Failed to open serial port %s: %s", port_name, conditionMessage(e)))
        })
        con_env$con <- c_obj
      }

      tryCatch({
        serial::write.serialConnection(con_env$con, paste0(tcl_str, "\n"))
      }, error = function(e) {
        close_serial_con()
        stop(sprintf("Failed to write to serial port %s: %s", port_name, conditionMessage(e)))
      })
      return(invisible(TRUE))
    } else if (.Platform$OS.type == "windows") {
      # Fallback via PowerShell .NET SerialPort without requiring external packages
      cmd <- sprintf(
        '$p = new-object System.IO.Ports.SerialPort "%s", %d; $p.Open(); $p.WriteLine(\x27%s\x27); $p.Close()',
        port_name, as.integer(baud), gsub("'", "''", json_str, fixed = TRUE)
      )
      res <- system2("powershell", c("-NoProfile", "-Command", cmd), stdout = FALSE, stderr = FALSE)
      if (res != 0) {
        stop(sprintf("Failed to write to serial port %s via PowerShell (exit code %d).", port_name, res))
      }
      return(invisible(TRUE))
    } else {
      # Fallback on Unix / Linux / macOS using file connection
      con <- file(port_name, open = "w")
      on.exit(try(close(con), silent = TRUE), add = TRUE)
      writeLines(json_str, con)
      return(invisible(TRUE))
    }
  }

  handler <- function(payload) {
    if (!nzchar(target_clean)) {
      warning("[rNotify: CYD] CYD target (host or COM port) is not configured.", call. = FALSE)
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

    # Dispatch via selected transport
    if (transport %in% c("bluetooth", "serial")) {
      write_serial(target_clean, json_str)
      if (payload$event %in% c("complete", "error", "catastrophic")) {
        close_serial_con()
      }
    } else {
      # HTTP Transport
      url <- sprintf("http://%s:%d%s", target_clean, http_port, path)

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
    }

    invisible(TRUE)
  }

  ch <- new_channel(
    name = "cyd",
    handler = handler,
    min_level = min_level,
    events = events,
    throttle_sec = throttle_sec,
    target = target_clean,
    transport = transport,
    baud = baud
  )
  ch$target <- target_clean
  ch$transport <- transport
  ch$baud <- baud
  ch
}

#' Cheap Yellow Display (CYD) Bluetooth Channel
#'
#' Convenience constructor for sending rNotify job telemetry to a CYD module
#' paired over Bluetooth Serial (SPP).
#'
#' @param port Bluetooth virtual COM port (e.g., \code{"COM8"}, \code{"COM10"} on Windows,
#'   \code{"/dev/rfcomm0"} on Linux, or \code{"/dev/tty.rNotify-CYD"} on macOS).
#'   Defaults to \code{Sys.getenv("CYD_BT_PORT", "COM8")}.
#' @param baud Baud rate for Bluetooth serial communication (default: 115200).
#' @param min_level Granularity level: "inner" (default, enables desk screen live updates)
#'   or "outer" (milestones only).
#' @param events Vector of event types to dispatch.
#' @param throttle_sec Minimum interval in seconds between CYD screen updates (default: 2.0).
#' @param timeout_sec Timeout in seconds (default: 2.0).
#' @return An \code{rnotify_channel} object.
#' @export
#' @examples
#' \dontrun{
#' # Connect to paired Bluetooth CYD on COM10
#' cyd <- channel_cyd_bluetooth("COM10")
#' job <- notify_job("Model Training", channels = cyd)
#' }
channel_cyd_bluetooth <- function(port = Sys.getenv("CYD_BT_PORT", "COM8"),
                                  baud = 115200,
                                  min_level = "inner",
                                  events = c("start", "progress", "step", "complete", "error", "catastrophic"),
                                  throttle_sec = 2.0,
                                  timeout_sec = 2.0) {
  channel_cyd(
    target = port,
    transport = "bluetooth",
    baud = baud,
    min_level = min_level,
    events = events,
    throttle_sec = throttle_sec,
    timeout_sec = timeout_sec
  )
}

#' Cheap Yellow Display (CYD) USB Serial Channel
#'
#' Convenience constructor for sending rNotify job telemetry to a CYD module
#' connected directly via USB cable.
#'
#' @param port Serial port (e.g., \code{"COM7"} on Windows or \code{"/dev/ttyUSB0"} on Linux).
#'   Defaults to \code{Sys.getenv("CYD_SERIAL_PORT", "COM7")}.
#' @param baud Baud rate for USB serial communication (default: 115200).
#' @param min_level Granularity level: "inner" (default, enables desk screen live updates)
#'   or "outer" (milestones only).
#' @param events Vector of event types to dispatch.
#' @param throttle_sec Minimum interval in seconds between CYD screen updates (default: 2.0).
#' @param timeout_sec Timeout in seconds (default: 2.0).
#' @return An \code{rnotify_channel} object.
#' @export
#' @examples
#' \dontrun{
#' # Connect to wired USB CYD on COM7
#' cyd <- channel_cyd_serial("COM7")
#' job <- notify_job("Simulations", channels = cyd)
#' }
channel_cyd_serial <- function(port = Sys.getenv("CYD_SERIAL_PORT", "COM7"),
                               baud = 115200,
                               min_level = "inner",
                               events = c("start", "progress", "step", "complete", "error", "catastrophic"),
                               throttle_sec = 2.0,
                               timeout_sec = 2.0) {
  channel_cyd(
    target = port,
    transport = "serial",
    baud = baud,
    min_level = min_level,
    events = events,
    throttle_sec = throttle_sec,
    timeout_sec = timeout_sec
  )
}
