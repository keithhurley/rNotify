test_that("rnotify_configure registers and resolves channels by name and all", {
  ch1 <- new_channel("desk_test", function(p) NULL)
  ch2 <- new_channel("push_test", function(p) NULL)

  rnotify_configure(desktop = ch1, push = ch2)

  configured <- rnotify_get_configured()
  expect_equal(length(configured), 2)
  expect_true(all(c("desktop", "push") %in% names(configured)))

  # Resolve "all"
  all_ch <- resolve_channels("all")
  expect_equal(length(all_ch), 2)

  # Resolve subset
  sub_ch <- resolve_channels("desktop")
  expect_equal(length(sub_ch), 1)
  expect_equal(sub_ch[[1]]$name, "desk_test")

  # Resolve explicit channel object
  direct_ch <- resolve_channels(ch1)
  expect_equal(length(direct_ch), 1)
})

test_that("announce_channels formats message without error", {
  ch1 <- new_channel("desktop", function(p) NULL)
  expect_message(
    announce_channels("Statewide Survey", list(ch1), pid = 1234, sentinel_active = TRUE),
    "Statewide Survey"
  )
})
