test_that("format_duration formats seconds properly", {
  expect_equal(format_duration(0), "00:00:00")
  expect_equal(format_duration(65), "00:01:05")
  expect_equal(format_duration(3665), "01:01:05")
  expect_equal(format_duration(NA), "--:--:--")
  expect_equal(format_duration(NULL), "--:--:--")
  expect_equal(format_duration(-10), "--:--:--")
})

test_that("calc_eta computes accurate time projections", {
  # 50 seconds for 50 out of 100 steps -> 50 sec remaining
  eta <- calc_eta(elapsed_sec = 50, current_step = 50, total_steps = 100)
  expect_equal(eta$eta_sec, 50)
  expect_equal(eta$eta_fmt, "00:00:50")

  # Complete
  eta_done <- calc_eta(elapsed_sec = 100, current_step = 100, total_steps = 100)
  expect_equal(eta_done$eta_sec, 0)
  expect_equal(eta_done$eta_fmt, "00:00:00")

  # Invalid inputs
  eta_invalid <- calc_eta(10, 0, 100)
  expect_true(is.na(eta_invalid$eta_sec))
})

test_that("is_pid_alive checks active process", {
  expect_true(is_pid_alive(Sys.getpid()))
  expect_false(is_pid_alive(99999999))
})
