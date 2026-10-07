test_that("NotifyJob lifecycle coordinates events and subtasks", {
  dispatched <- list()
  mock_channel <- new_channel(
    name = "mock",
    handler = function(p) {
      dispatched <<- c(dispatched, list(p))
    },
    min_level = "inner"
  )

  job <- notify_job(
    title = "Test Lifecycle",
    channels = list(mock_channel),
    total_steps = 2,
    throttle_sec = 0,
    use_sentinel = FALSE,
    announce = FALSE
  )

  job$start("Starting job")
  expect_equal(length(dispatched), 1)
  expect_equal(dispatched[[1]]$event, "start")

  # Subtask nested loop
  sub <- job$subtask("Sub 1", total_steps = 10, step_num = 1)
  sub$progress(5, "Rep 5")
  expect_equal(length(dispatched), 2)
  expect_equal(dispatched[[2]]$progress$inner_step, 5)

  sub$complete()
  expect_equal(length(dispatched), 3)

  job$complete("All done")
  expect_equal(length(dispatched), 4)
  expect_equal(dispatched[[4]]$event, "complete")
})

test_that("with_notify catches and notifies errors while rethrowing", {
  dispatched <- list()
  mock_channel <- new_channel(
    name = "mock",
    handler = function(p) {
      dispatched <<- c(dispatched, list(p))
    }
  )

  expect_error(
    with_notify(
      title = "Failing Script",
      channels = list(mock_channel),
      use_sentinel = FALSE,
      announce = FALSE,
      expr = {
        notify_step("Step before failure")
        stop("Simulated fatal calculation error!")
      }
    ),
    "Simulated fatal calculation error!"
  )

  # Check that error was caught and dispatched
  events <- vapply(dispatched, function(p) p$event, character(1))
  expect_true("error" %in% events)
  err_payload <- dispatched[[which(events == "error")[1]]]
  expect_true(grepl("Simulated fatal", err_payload$details$error_message))
})
