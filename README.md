# rNotify

> **Resilient Multi-Channel Notifications, Nested Progress Tracking & Catastrophic Crash Monitoring for R Workflows**

[![R-CMD-check](https://img.shields.io/badge/R--CMD--check-passing-brightgreen.svg)]()
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

`rNotify` is an R package designed for data scientists, statisticians, and researchers executing long-running computational jobs (such as MCMC chains, spatial bootstrap iterations, machine learning models, or batch ETL).

It features **zero-impact fault isolation**, **multiplexed multi-channel dispatch**, **single-stage and nested loop progress tracking with composite ETAs**, **fine-grained throttling**, and a **detached background sentinel (dead man's switch)** that catches sudden R session aborts, segfaults, or process terminations.

---

## Supported Notification Channels

| Channel | Driver Function | Target Medium | Level Support |
| :--- | :--- | :--- | :--- |
| **Pushover** | `channel_pushover()` | iOS & Android Push | Outer / Milestones |
| **ntfy.sh** | `channel_ntfy()` | Open-source mobile & desktop push | Outer / Milestones |
| **Email** | `channel_email()` | SMTP / RFC 2822 Email | Outer / Milestones |
| **Desktop** | `channel_desktop()` | Windows Toast + Audible Chimes | Outer / Milestones |
| **CYD Display** | `channel_cyd()` | ESP32 Cheap Yellow Display (320×240 TFT) | **Inner & Outer (Live Screen)** |
| **Webhook** | `channel_webhook()` | Custom JSON HTTP POST (Slack/Discord/Custom) | Inner or Outer |

---

## Installation

Install directly from GitHub via `devtools` or `remotes`:

```r
# install.packages("devtools")
devtools::install_github("keithhurley/rNotify")
```

---

## Quick Start

### 1. Configure Channels (1, Few, or All)
You can configure your default notification destinations once in your script or `~/.Rprofile`:

```r
library(rNotify)

rnotify_configure(
  desktop  = channel_desktop(),
  pushover = channel_pushover(), # reads PUSHOVER_USER & PUSHOVER_TOKEN from .Renviron
  ntfy     = channel_ntfy(topic = "keith-jobs"),
  cyd      = channel_cyd(host = "192.168.1.150") # ESP32 display on your desk
)
```

At job initialization, `rNotify` reports active channels in the console:
```text
[rNotify] ========================================================
[rNotify] Job Initialized: 'Annual Creel Simulation' (PID: 14820)
[rNotify] Active Channels (3): Pushover, CYD (192.168.1.150:80), Desktop
[rNotify] Crash Sentinel: Active (Dead Man's Switch monitoring PID 14820)
[rNotify] ========================================================
```

---

## Workflow Patterns

### Pattern A: High-Level Expression Wrapper (`with_notify`)
Wrap an entire script, simulation, or model block. It automatically times execution, handles progress, dispatches completion summaries, and catches unhandled errors:

```r
result <- with_notify(
  title = "Annual Creel Simulation",
  channels = "all",
  expr = {
    notify_step("Loading survey covariates...")
    data <- load_survey_data()
    
    notify_step("Fitting hierarchical Bayesian model...")
    fit <- fit_bayesian_model(data)
    
    saveRDS(fit, "model_output.rds")
    fit
  }
)
```

If an error occurs inside `expr`, `rNotify` dispatches a high-priority `❌ Job Failed` notification containing the error message and call stack to all active channels before re-throwing the error in R.

---

### Pattern B: Single-Stage Loop with Throttling (`notify_job`)
For iterative loops where you want progress updates without spamming your channels:

```r
job <- notify_job(
  title = "Lake Indexing",
  channels = c("pushover", "desktop"),
  total_steps = 100,
  milestones = c(25, 50, 75, 100), # Triggers at 25%, 50%, 75%, 100%
  throttle_sec = 120               # Never ping faster than once every 2 mins
)

job$start("Starting processing of 100 lakes...")

for (i in 1:100) {
  process_lake(i)
  job$progress(step = i, message = sprintf("Finished lake %d/100", i))
}

job$complete("All 100 lakes successfully indexed.")
```

---

### Pattern C: Nested Loops (Outer $\times$ Inner Subtasks)
When you have nested loops (e.g. 50 lakes $\times$ 1,000 bootstrap iterations), you want live inner updates on your desk screen (CYD) without flooding your phone with 50,000 push alerts.

`rNotify` handles this with **hierarchical subtasks**, **granularity filtering**, and **composite global ETAs**:

```r
job <- notify_job(
  title = "Statewide Creel Simulation",
  channels = list(
    channel_cyd(host = "192.168.1.150", throttle_sec = 2), # Live 2s updates on desk
    channel_pushover(min_level = "outer", throttle_sec = 900), # Phone pings only on outer milestones
    channel_desktop(events = c("complete", "error"))           # Audio chime when finished
  ),
  total_steps = length(lakes)
)

job$start()

for (i in seq_along(lakes)) {
  # Subtask coordinates with master job
  sub <- job$subtask(title = lakes[i], total_steps = 1000, step_num = i)
  
  for (rep in 1:1000) {
    run_iteration(rep)
    
    # High-frequency inner update: updates CYD screen, skipped on Pushover
    sub$progress(step = rep, message = sprintf("Bootstrap rep %d", rep))
  }
  
  sub$complete()
}

job$complete("Simulation finished.")
```

#### Composite Global ETA Formula
Instead of resetting the ETA clock on every inner loop, `rNotify` calculates the global completion state:

$$\text{Global \%} = \frac{(i_{\text{outer}} - 1) + \left(\frac{j_{\text{inner}}}{N_{\text{inner}}}\right)}{N_{\text{outer}}} \times 100$$

---

## Catastrophic Crash Detection ("Dead Man's Switch")

Standard R scripts cannot notify you if R hard-crashes (such as a C-level segmentation fault, out-of-memory crash, Windows process kill, or machine reboot).

`rNotify` solves this via a **Detached Background Sentinel**:
1. At job initialization, `rNotify` spawns an independent background watcher process passing the main R session's OS process ID (PID).
2. The sentinel polls the OS process table every 10–15 seconds.
3. If the main R process finishes cleanly, the completion finalizer signals the sentinel to shut down.
4. If the main R PID **suddenly vanishes** without setting the completion flag, the sentinel detects the crash and broadcasts an emergency alert to all channels:
   > 🚨 **CRITICAL: R SESSION TERMINATED ABRUPTLY**  
   > **Job**: *Annual Creel Simulation*  
   > **PID**: 14820 terminated unexpectedly.  
   > **Status**: UNKNOWN / CRASHED. No further notifications are forthcoming.

---

## Cheap Yellow Display (CYD) Hardware Support

`rNotify` includes reference firmware for the **ESP32-2432S028R** Cheap Yellow Display module in `inst/cyd_firmware/`. 

It supports three connectivity modes from inside R:
- **Bluetooth Serial (SPP)** (Wireless): Pair `rNotify-CYD` and drive directly from R via `channel_cyd_bluetooth("COM8")` with zero network setup.
- **USB Serial** (Wired): Direct plug-and-play via `channel_cyd_serial("COM7")`.
- **Wi-Fi REST** (Network): HTTP POST updates via `channel_cyd(host = "192.168.1.150")`.

Features:
- Color-coded status header (Cyan = Running, Green = Complete, Red = Failed/Crashed)
- Onboard active-LOW RGB status LED
- Outer loop progress bar & percentage
- Inner loop / subtask progress bar & percentage
- Elapsed runtime and projected ETA
- Active transport and connection footer

See [`inst/cyd_firmware/README.md`](inst/cyd_firmware/README.md) and the [CYD Setup Vignette](vignettes/cyd-setup-and-usage.Rmd) for complete instructions.

---

## License

MIT © Keith Hurley
