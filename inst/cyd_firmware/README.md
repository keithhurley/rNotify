# rNotify CYD (Cheap Yellow Display) Firmware Guide

This directory contains the ESP32 firmware for displaying real-time job metrics, dual-stage nested loop progress bars, status colors, and ETAs on a **Cheap Yellow Display** (ESP32-2432S028R).

## Supported Transports
1. **Bluetooth Serial (SPP)** (Recommended): Wireless connection directly to your workstation via Bluetooth (Device: `rNotify-CYD`). Zero network configuration or Wi-Fi required!
2. **USB Serial**: Direct wired connection over micro-USB cable at 115200 baud.
3. **Wi-Fi REST**: Over local network via HTTP POST to `/api/notify`.

## Hardware Specifications
- **Module**: ESP32-2432S028R (2.8" 320x240 TFT LCD with ILI9341 driver)
- **Wireless**: Bluetooth Classic (SPP), 2.4 GHz Wi-Fi
- **Status LED**: Onboard RGB LED (Pins 4, 16, 17 - active LOW)
- **Screen Layout**:
  - **Header Banner**: Color-coded job state (`#00CCFF` for Running, `#00FF00` for Complete, `#FF3333` for Failed, `#FF0000` for Crashed)
  - **Outer Progress Bar**: Overall job percentage & step count
  - **Inner Progress Bar**: Subtask / nested loop percentage & step count
  - **Metrics Card**: Elapsed runtime & projected ETA
  - **Footer Status**: Shows active transport / device name

## Setup Instructions

### 1. Arduino Configuration
1. Install **ESP32 Board Support** in the Arduino IDE Boards Manager (`ESP32 by Espressif Systems`).
2. Select Board: **ESP32 Dev Module**.
3. Partition Scheme: **Huge APP (3MB No OTA/1MB SPIFFS)**.
4. Install Libraries:
   - `TFT_eSPI` by Bodmer
   - `ArduinoJson` (v6 or v7) by Benoît Blanchon

### 2. Configure `TFT_eSPI`
Open `libraries/TFT_eSPI/User_Setup.h`:
- Driver: `#define ILI9341_2_DRIVER`
- Pins:
  - `TFT_MISO 12`, `TFT_MOSI 13`, `TFT_SCLK 14`
  - `TFT_CS 15`, `TFT_DC 2`, `TFT_RST -1`
  - `TFT_BL 21` (Backlight)

### 3. Flash Firmware
Using Arduino IDE or `arduino-cli`:
```powershell
arduino-cli compile --fqbn esp32:esp32:esp32:PartitionScheme=huge_app cyd_notify.ino
arduino-cli upload -p <COM_PORT> --fqbn esp32:esp32:esp32:PartitionScheme=huge_app cyd_notify.ino
```

### 4. Pair with Computer (Bluetooth)
1. Open Windows **Settings > Bluetooth & devices > Add device**.
2. Select **`rNotify-CYD`** and click Pair.
3. Check the assigned **Outgoing COM Port** in Device Manager (e.g., `COM8`).

### 5. Use Inside R
```r
library(rNotify)

# Bluetooth wireless connection
cyd <- channel_cyd_bluetooth(port = "COM8")

# Or wired USB connection
# cyd <- channel_cyd_serial(port = "COM7")

job <- notify_job(
  title = "Bootstrap Simulation",
  channels = list(cyd, channel_desktop()),
  total_steps = 100
)

job$start("Running iterations...")
for (i in 1:100) {
  Sys.sleep(0.05)
  notify_step(job, step = i)
}
job$complete("Job complete!")
```
