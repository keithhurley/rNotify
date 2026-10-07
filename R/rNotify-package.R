#' rNotify: Resilient Multi-Channel Notifications and Progress Tracking for Long-Running R Jobs
#'
#' @description
#' Provides a fault-isolated, multiplexed notification and process-monitoring
#' framework for R scripts, statistical simulations, and long-running computational
#' jobs. Features multi-channel dispatch to mobile devices, desk displays,
#' email, desktop notifications, and webhooks. Includes single-stage and nested loop
#' progress tracking with composite ETAs, multi-tier throttling, and a detached
#' background sentinel (dead man's switch) that alerts channels if the R session
#' crashes or aborts unexpectedly.
#'
#' @details
#' The primary components of \pkg{rNotify} include:
#'
#' \subsection{Workflow Interfaces}{
#' \itemize{
#'   \item \code{\link{with_notify}}: Functional expression wrapper that automatically
#'     measures runtime, sends start and completion notices, and catches unhandled errors.
#'   \item \code{\link{notify_job}}: Stateful lifecycle controller (\code{\link{NotifyJob}})
#'     for manual step progression, throttled iteration loops, and nested subtasks.
#' }
#' }
#'
#' \subsection{Notification Channel Drivers}{
#' \itemize{
#'   \item \code{\link{channel_pushover}}: Real-time mobile push notifications for iOS and Android.
#'   \item \code{\link{channel_ntfy}}: Free, open-source push notifications via ntfy.sh or self-hosted topics.
#'   \item \code{\link{channel_cyd}}: Live Wi-Fi telemetry to an ESP32 Cheap Yellow Display module.
#'   \item \code{\link{channel_desktop}}: Native OS toast popups and audible completion chimes.
#'   \item \code{\link{channel_email}}: Automated summary emails via SMTP.
#'   \item \code{\link{channel_webhook}}: Generic JSON HTTP POST dispatches to any webhook URL.
#' }
#' }
#'
#' \subsection{Configuration & Throttling}{
#' \itemize{
#'   \item \code{\link{rnotify_configure}}: Save global channel presets across your workstation.
#'   \item \code{\link{create_throttler}}: Fine-grained rate limiting using time intervals,
#'     percentage milestones, and step increments.
#' }
#' }
#'
#' \subsection{Catastrophic Crash Sentinel (Dead Man's Switch)}{
#' When enabled, \pkg{rNotify} launches a detached background process monitoring the
#' main R session PID. If the R process unexpectedly terminates without a clean exit
#' (such as an out-of-memory kill, C-level segfault, or forced kill), the sentinel
#' broadcasts an emergency alert to all configured channels stating that the job bombed
#' and status is unknown.
#' }
#'
#' \subsection{Vignettes & User Guides}{
#' The package includes three detailed HTML guides:
#' \itemize{
#'   \item \strong{Getting Started}: \code{vignette("getting-started", package = "rNotify")}
#'     \cr Walkthrough of credential configuration, channel setups, throttles, single-stage
#'     and nested loop tracking, and error handling.
#'   \item \strong{Cheap Yellow Display (CYD) Hardware & Setup}: \code{vignette("cyd-setup-and-usage", package = "rNotify")}
#'     \cr Hardware specifications, ESP32 pinouts, Arduino IDE / PlatformIO firmware flashing,
#'     and driving the 320x240 LCD display over Wi-Fi.
#'   \item \strong{Architecture & Technical Reference}: \code{vignette("package-guide", package = "rNotify")}
#'     \cr Deep dive into the payload schema, fault isolation guarantees, throttling engine,
#'     and the background crash sentinel (dead man's switch).
#' }
#' To open an interactive browser with all guides:
#' \preformatted{browseVignettes("rNotify")}
#' }
#'
#' @name rNotify-package
#' @aliases rNotify
#' @author Keith Hurley \email{keith.l.hurley@@gmail.com}
#' @seealso
#' Useful links:
#' \itemize{
#'   \item \url{https://github.com/keithhurley/rNotify}
#'   \item Report bugs at \url{https://github.com/keithhurley/rNotify/issues}
#' }
"_PACKAGE"
