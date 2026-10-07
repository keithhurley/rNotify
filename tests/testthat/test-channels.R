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
