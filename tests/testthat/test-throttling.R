test_that("throttler respects milestone percentages", {
  th <- create_throttler(milestones = c(25, 50, 75, 100))

  # 10% - should not fire
  expect_false(th$should_dispatch(step = 10, total = 100))

  # 25% - should fire
  expect_true(th$should_dispatch(step = 25, total = 100))
  th$record_dispatch(step = 25, total = 100)

  # 26% - already fired 25%, should not fire
  expect_false(th$should_dispatch(step = 26, total = 100))

  # 50% - should fire
  expect_true(th$should_dispatch(step = 50, total = 100))
  th$record_dispatch(step = 50, total = 100)
})

test_that("throttler respects time interval throttling", {
  th <- create_throttler(throttle_sec = 10)

  # First check: should fire
  expect_true(th$should_dispatch(step = 1, total = 100))
  th$record_dispatch(step = 1, total = 100)

  # Immediately after: should NOT fire
  expect_false(th$should_dispatch(step = 2, total = 100))

  # Force always fires
  expect_true(th$should_dispatch(step = 2, total = 100, force = TRUE))
})

test_that("throttler handles pct_step intervals", {
  th <- create_throttler(pct_step = 20)

  # 5%
  expect_false(th$should_dispatch(step = 5, total = 100))

  # 20%
  expect_true(th$should_dispatch(step = 20, total = 100))
  th$record_dispatch(step = 20, total = 100)

  # 30% (same bucket)
  expect_false(th$should_dispatch(step = 30, total = 100))

  # 40% (next bucket)
  expect_true(th$should_dispatch(step = 40, total = 100))
})
