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

  # Subtask nested loop: subtask() dispatches step 0 to reset inner bar
  sub <- job$subtask("Sub 1", total_steps = 10, step_num = 1)
  expect_equal(dispatched[[2]]$progress$inner_step, 0)

  sub$progress(5, "Rep 5")
  expect_equal(length(dispatched), 3)
  expect_equal(dispatched[[3]]$progress$inner_step, 5)

  sub$complete()
  expect_equal(length(dispatched), 4)

  job$complete("All done")
  expect_equal(length(dispatched), 5)
  expect_equal(dispatched[[5]]$event, "complete")
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

test_that("job$step auto-increments and job$finish alias works", {
  dispatched <- list()
  mock_channel <- new_channel(
    name = "mock",
    handler = function(p) {
      dispatched <<- c(dispatched, list(p))
    }
  )

  job <- notify_job(
    title = "Step Test",
    channels = list(mock_channel),
    total_steps = 3,
    throttle_sec = 0,
    use_sentinel = FALSE,
    announce = FALSE
  )

  job$start()
  job$step("First batch")
  expect_equal(job$current_step, 1)
  expect_equal(dispatched[[length(dispatched)]]$progress$step, 1)

  job$step("Second batch")
  expect_equal(job$current_step, 2)
  expect_equal(dispatched[[length(dispatched)]]$progress$step, 2)

  job$finish("All completed successfully")
  expect_equal(dispatched[[length(dispatched)]]$event, "complete")
})

test_that("subtask inner loop progress dispatches to inner channels with default 60s outer throttle", {
  inner_dispatches <- list()
  mock_cyd <- new_channel(
    name = "cyd",
    handler = function(p) {
      inner_dispatches <<- c(inner_dispatches, list(p))
    },
    min_level = "inner"
  )

  # Default job has throttle_sec = 60
  job <- notify_job(
    title = "Statewide Creel Index",
    channels = list(mock_cyd),
    total_steps = 10,
    use_sentinel = FALSE,
    announce = FALSE
  )

  job$start("Starting statewide run...")
  sub <- job$subtask("Lake 1", total_steps = 100, step_num = 1)

  # Inner loop iterations should dispatch to inner channel
  sub$progress(step = 10, message = "Iteration 10")
  sub$progress(step = 20, message = "Iteration 20")

  expect_true(length(inner_dispatches) >= 3) # start + init(0) + inner steps
  sub$complete()

  # Main loop moves to next iteration and creates next subtask
  sub2 <- job$subtask("Lake 2", total_steps = 100, step_num = 2)
  last_item <- inner_dispatches[[length(inner_dispatches)]]
  expect_equal(last_item$progress$inner_step, 0) # resets to 0 on new subtask!
  expect_equal(last_item$progress$step, 2)
  expect_equal(last_item$progress$inner_message, "[Lake 2] Starting...")

  sub2$progress(step = 50, message = "Iteration 50")
  last_item2 <- inner_dispatches[[length(inner_dispatches)]]
  expect_equal(last_item2$progress$inner_step, 50)

  sub2$complete()
  job$complete()
})
