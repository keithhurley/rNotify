test_that("new_payload constructs valid single-stage payload", {
  p <- new_payload(
    event = "progress",
    title = "Test Job",
    message = "Halfway done",
    step = 50,
    total = 100,
    elapsed_sec = 120,
    channels_active = c("pushover", "desktop")
  )

  expect_s3_class(p, "rnotify_payload")
  expect_equal(p$event, "progress")
  expect_equal(p$status, "running")
  expect_equal(p$progress$pct, 50.0)
  expect_equal(p$progress$eta_sec, 120.0)
  expect_equal(p$progress$eta_fmt, "00:02:00")
  expect_equal(p$channels_active, c("pushover", "desktop"))

  summary_txt <- as_summary_text(p)
  expect_true(grepl("PROGRESS", summary_txt))
  expect_true(grepl("50.0%", summary_txt))
})

test_that("new_payload computes composite nested progress accurately", {
  # Lake 2 of 4 (step = 2, total = 4), iteration 500 of 1000 (inner_step = 500, inner_total = 1000)
  # Completed so far: 1 full lake + 0.5 = 1.5 out of 4 -> 37.5%
  p <- new_payload(
    event = "progress",
    title = "Nested Model",
    step = 2,
    total = 4,
    elapsed_sec = 150,
    inner_step = 500,
    inner_total = 1000,
    inner_message = "MCMC Rep 500"
  )

  expect_equal(p$progress$pct, 37.5)
  expect_equal(p$progress$inner_pct, 50.0)
  # 1.5 units took 150s (100s/unit), 2.5 remaining units -> 250s ETA
  expect_equal(p$progress$eta_sec, 250.0)
})

test_that("catastrophic payload formats alert text properly", {
  p <- new_payload(
    event = "catastrophic",
    title = "Failed Run",
    message = "Process died abruptly"
  )

  expect_equal(p$status, "crashed")
  txt <- as_summary_text(p)
  expect_true(grepl("CRITICAL", txt))
  expect_true(grepl("UNKNOWN", txt))
})
