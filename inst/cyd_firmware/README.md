# rNotify CYD (Cheap Yellow Display) Firmware Guide

This directory contains the ESP32 firmware for displaying real-time job metrics, dual-stage nested loop progress bars, status colors, and ETAs on a **Cheap Yellow Display** (ESP32-2432S028R).

## Modern Cyberpunk Telemetry HUD Features

The firmware features a modern, demonstration-ready **Cyberpunk / Glassmorphism Dark HUD** interface:
- **Artistic Boot / Standby Screen**: Features a prominent stylized **"R-Notify"** centerpiece with multi-layered 3D neon glow (Cyan, Purple, and Laser Emerald accents).
- **Dual Live Connection Dashboards**:
  - **Bluetooth Link Card**: Live connection indicator (`READY TO PAIR` vs `CONNECTED`), device name (`rNotify-CYD`), host COM port, and RFCOMM protocol metrics. Dynamically updates when paired devices connect or disconnect!
  - **USB Cable Serial Card**: Live wired interface status (`CONNECTED`), UART driver readout (`CH340 / CP210x`), and host COM port.
- **Touchscreen Corner System Reset**: A dedicated `[RST]` touchscreen button in the top-right corner of **all screens** provides a one-touch system reboot (`ESP.restart()`), making physical button access unnecessary when mounted in an enclosure or desktop case.
- **Top Telemetry Navbar**: Branded `rNotify` pill chip, glowing status indicators (`● RUNNING`, `✔ COMPLETE`, `✖ FAILED`, `⚡ STARTING`), host port indicator, and corner reset button.
- **Glossy Neon Progress Bars**: Rounded capsule tracks with specular sheen highlights for a glossy glass-tube / illuminated LED effect. Distinct vibrant colorways for outer loop (Electric Cyan) and nested subtasks (Electric Violet / Magenta).
- **Side-by-Side Modular HUD Metric Cards**: Dedicated digital clock readout tiles for `TIME ELAPSED` and `PROJECTED ETA` with glowing accent lines.
- **Zero-Flicker Differential Redraw**: Smart bounding-box partial updates ensure butter-smooth rendering without screen wipes or flashing during rapid updates.
- **Interactive Hardware Demo Mode**: Press the physical **BOOT** button (GPIO 0) on the CYD to instantly cycle through live preview screens without needing an active R connection!

## Supported Transports
1. **Bluetooth Serial (SPP)** (Recommended): Wireless connection directly to your workstation via Bluetooth (Device: `rNotify-CYD`). Zero network configuration or Wi-Fi required!
2. **USB Serial**: Direct wired connection over micro-USB cable at 115200 baud.
3. **Wi-Fi REST**: Over local network via HTTP POST to `/api/notify`.

## Hardware Specifications
- **Module**: ESP32-2432S028R (2.8" 320x240 TFT LCD with ILI9341 / ST7789 driver)
- **Touchscreen**: XPT2046 Resistive Touch Controller (VSPI: CLK=25, MISO=39, MOSI=32, CS=33, IRQ=36)
- **Wireless**: Bluetooth Classic (SPP), 2.4 GHz Wi-Fi
- **Status LED**: Onboard RGB LED (Pins 4, 16, 17 - active LOW):
  - *Idle / Standby*: Off (LED dark)
  - *Start (`start`)*: Amber / Yellow (`255, 150, 0`)
  - *Running (`progress`, `step`)*: Electric Cyan (`0, 160, 255`)
  - *Complete (`complete`)*: Bright Green (`0, 255, 0`)
  - *Failed (`error`, `catastrophic`)*: Neon Red (`255, 0, 0`)
- **System Controls**:
  - *Touchscreen*: On-screen `[RST]` button in top-right corner of every screen
  - *BOOT Button*: Onboard GPIO 0 button for cycling interactive demo mode

## Setup Instructions

### 1. Arduino Configuration
1. Install **ESP32 Board Support** in the Arduino IDE Boards Manager (`ESP32 by Espressif Systems`).
2. Select Board: **ESP32 Dev Module**.
3. Partition Scheme: **Huge APP (3MB No OTA/1MB SPIFFS)**.
4. Install Libraries:
   - `TFT_eSPI` by Bodmer
   - `ArduinoJson` (v6 or v7) by Benoît Blanchon
   - `XPT2046_Touchscreen` by Paul Stoffregen

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

### 4. Interactive Preview Test
Once flashed, you can immediately test the display by pressing the **BOOT** button on the back of the CYD module:
1. **Click 1**: Standby Cyberdeck Console
2. **Click 2**: Running Simulation (Dual neon progress bars & active HUD timers)
3. **Click 3**: Job Complete (Laser emerald glow & checkmark)
4. **Click 4**: Failed Job Alert (Neon crimson error diagnosis)

### 5. Pair with Computer (Bluetooth)
1. Open Windows **Settings > Bluetooth & devices > Add device**.
2. Select **`rNotify-CYD`** and click Pair.
3. Check the assigned **Outgoing COM Port** in Device Manager (e.g., `COM8`).

### 6. Use Inside R
```r
library(rNotify)

# Bluetooth wireless connection (auto-detects port or specify port = "COM10")
cyd <- channel_cyd_bluetooth()

# Or wired USB connection (auto-detects port or specify port = "COM7")
# cyd <- channel_cyd_serial()

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

### 7. Resetting to Standby (Idle Screen)
Once your work is done and you want to return the display to its standby console:
```r
job$reset()    # Clears telemetry, turns off LED, and restores idle screen
cyd$reset()    # Or call directly on the channel
cyd_reset(cyd) # Or via standalone helper
```

### 8. Touchscreen System Reset (`[RST]`)
When mounted inside an enclosure where the rear reset button is inaccessible, tap the neon **`[RST]`** button in the top-right corner of the screen. The screen highlights the button, shows a system reboot dialog, and cleanly restarts the ESP32.
