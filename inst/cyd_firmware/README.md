# rNotify CYD (Cheap Yellow Display) Firmware Guide

This directory contains the ESP32 reference firmware for displaying real-time job metrics, dual-stage nested loop progress bars, status colors, and ETAs on a **Cheap Yellow Display** (ESP32-2432S028R).

## Hardware Specifications
- **Module**: ESP32-2432S028R (2.8" or 2.4" 320x240 TFT LCD with ILI9341 driver)
- **Connectivity**: 2.4 GHz Wi-Fi
- **Screen Layout**:
  - **Header Banner**: Color-coded job state (`#00CCFF` for Running, `#00FF00` for Complete, `#FF3333` for Failed, `#FF0000` for Crashed)
  - **Outer Progress Bar**: Overall job percentage & step count
  - **Inner Progress Bar**: Subtask / nested loop percentage & step count
  - **Metrics Card**: Elapsed runtime & projected ETA
  - **IP Footer**: Shows device Wi-Fi IP address for quick configuration in R

## Setup Instructions

### 1. Arduino IDE Setup
1. Install **ESP32 Board Support** in the Arduino IDE Boards Manager (`ESP32 by Espressif Systems`).
2. Select Board: **ESP32 Dev Module**.
3. Install Libraries via Library Manager:
   - `TFT_eSPI` by Bodmer
   - `ArduinoJson` (v6 or v7) by Benoît Blanchon

### 2. Configure `TFT_eSPI`
Open your Arduino library directory: `libraries/TFT_eSPI/User_Setup.h` (or select the preset for ESP32-2432S028R in `User_Setup_Select.h`):
- Driver: `#define ILI9341_2_DRIVER`
- TFT Pins:
  - `TFT_MISO 12`
  - `TFT_MOSI 13`
  - `TFT_SCLK 14`
  - `TFT_CS   15`
  - `TFT_DC    2`
  - `TFT_RST  -1`
  - `TFT_BL   21`

### 3. Flash Firmware
1. Open `cyd_notify.ino`.
2. Update `WIFI_SSID` and `WIFI_PASSWORD` with your network credentials.
3. Upload to your CYD module via micro-USB.
4. Note the IP address displayed on screen after connection (e.g. `192.168.1.150`).

### 4. Configure in R
Set your CYD IP address in `~/.Renviron` or directly in R:
```r
# In ~/.Renviron:
# CYD_HOST=192.168.1.150

library(rNotify)

# Use with notify_job
job <- notify_job(
  title = "Lake Creel Model",
  channels = channel_cyd(host = "192.168.1.150")
)
```
