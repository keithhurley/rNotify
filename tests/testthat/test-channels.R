test_that("safe_dispatch isolates faulty channels without crashing", {
  # Handler intentionally explodes
  broken_handler <- function(payload) {
    stop("Network socket reset by peer!")
  }

  ch <- new_channel("faulty_service", broken_handler)
  p <- new_payload(event = "start", title = "Robustness Test")

  # Must not crash! Should return FALSE and emit warning
  expect_warning(res <- safe_dispatch(ch, p), "Delivery failed on channel 'faulty_service'")
  expect_false(res)
})

test_that("channels filter inner events based on min_level", {
  received_events <- list()
  mock_handler <- function(p) {
    received_events <<- c(received_events, list(p))
  }

  # Outer-only channel (e.g. mobile push)
  ch_outer <- new_channel("mock_push", mock_handler, min_level = "outer")

  # Inner-enabled channel (e.g. CYD screen)
  ch_inner <- new_channel("mock_cyd", mock_handler, min_level = "inner")

  p_inner <- new_payload(event = "progress", title = "Subtask Rep 5", inner_step = 5, inner_total = 10)

  # Outer channel should skip inner event
  expect_false(safe_dispatch(ch_outer, p_inner, is_inner = TRUE))

  # Inner channel should accept inner event
  expect_true(safe_dispatch(ch_inner, p_inner, is_inner = TRUE))
})

test_that("channel_cyd supports bluetooth, serial, and http transports", {
  # Auto-detection from COM port
  ch_bt <- channel_cyd(target = "COM8")
  expect_equal(ch_bt$name, "cyd")
  expect_equal(ch_bt$transport, "bluetooth")
  expect_equal(ch_bt$target, "COM8")

  # Bluetooth dedicated constructor
  ch_bt_helper <- channel_cyd_bluetooth(port = "COM9")
  expect_equal(ch_bt_helper$name, "cyd")
  expect_equal(ch_bt_helper$transport, "bluetooth")
  expect_equal(ch_bt_helper$target, "COM9")

  # Serial dedicated constructor
  ch_ser <- channel_cyd_serial(port = "COM7")
  expect_equal(ch_ser$name, "cyd")
  expect_equal(ch_ser$transport, "serial")
  expect_equal(ch_ser$target, "COM7")

  # HTTP auto-detection
  ch_http <- channel_cyd(target = "192.168.1.150")
  expect_equal(ch_http$transport, "http")
  expect_equal(ch_http$target, "192.168.1.150")

  # Port argument passed as COM port
  ch_port <- channel_cyd(port = "COM10")
  expect_equal(ch_port$transport, "bluetooth")
  expect_equal(ch_port$target, "COM10")

  # detect_cyd_port function runs safely
  expect_true(is.character(detect_cyd_port("any")) || is.null(detect_cyd_port("any")))
  expect_true(is.character(detect_cyd_port("bluetooth")) || is.null(detect_cyd_port("bluetooth")))
  expect_true(is.character(detect_cyd_port("serial")) || is.null(detect_cyd_port("serial")))
})

test_that("cyd_demo formats and transmits showcase modes correctly", {
  dispatched <- list()
  mock_cyd <- new_channel("cyd", function(p) {
    dispatched <<- c(dispatched, list(p))
  })
  mock_cyd$transport <- "bluetooth"

  expect_invisible(cyd_demo(channel = mock_cyd, mode = "running"))
  expect_equal(length(dispatched), 1)
  expect_equal(dispatched[[1]]$title, "Bayesian MCMC Fit")
  expect_equal(dispatched[[1]]$event, "progress")

  expect_invisible(cyd_demo(channel = mock_cyd, mode = "complete"))
  expect_equal(length(dispatched), 2)
  expect_equal(dispatched[[2]]$title, "Bootstrap Simulation")
  expect_equal(dispatched[[2]]$event, "complete")

  expect_invisible(cyd_demo(channel = mock_cyd, mode = "error"))
  expect_equal(length(dispatched), 3)
  expect_equal(dispatched[[3]]$title, "High-Dim Optimization")
  expect_equal(dispatched[[3]]$event, "error")

  expect_error(cyd_demo(channel = "not_a_channel"), "must be an rNotify channel object")
})

