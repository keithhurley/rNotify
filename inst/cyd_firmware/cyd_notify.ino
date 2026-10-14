/*
 * rNotify CYD (Cheap Yellow Display) ESP32 Firmware
 * Hardware: ESP32-2432S028R (2.8" 320x240) / ESP32-3248S035 (3.5" 480x320)
 *
 * Transports Supported:
 * 1. Bluetooth Serial (SPP) - Device Name: "rNotify-CYD"
 * 2. USB Serial (115200 baud)
 * 3. Optional Wi-Fi HTTP REST (POST http://<CYD_IP>/api/notify)
 *
 * UI Architecture:
 * - Responsive Cyberpunk / Glassmorphism Dark HUD Theme (Auto-scales 320x240 & 480x320)
 * - Glossy neon progress bars with specular sheen highlights
 * - Dual-loop telemetry (Cyan primary outer loop + Neon Purple inner subtask loop)
 * - Side-by-side modular HUD metric cards (Elapsed & ETA digital displays)
 * - Dynamic status pills with live status glow (RUNNING, COMPLETE, FAILED, STARTING)
 * - Full flicker-free selective partial redraw engine
 * - Interactive BOOT button (GPIO 0) demo cycle mode
 *
 * Dependencies (install via Arduino Library Manager or arduino-cli):
 * - TFT_eSPI (configured for CYD display)
 * - ArduinoJson (v6 or v7)
 * - BluetoothSerial (included with ESP32 core)
 */

#include <BluetoothSerial.h>
#include <esp_gap_bt_api.h>
#include <TFT_eSPI.h>
#include <ArduinoJson.h>
#include <Preferences.h>

#define ENABLE_WIFI 0

#if ENABLE_WIFI
#include <WiFi.h>
#include <WebServer.h>
WebServer server(80);
const char* WIFI_SSID     = "YOUR_WIFI_SSID";
const char* WIFI_PASSWORD = "YOUR_WIFI_PASSWORD";
#endif

// Bluetooth Serial Port Profile (SPP)
BluetoothSerial SerialBT;
const char* BT_DEVICE_NAME = "rNotify-CYD";
static bool bt_is_connected = false;

// Forward declaration for idle screen
void showIdleScreen();

void btCallback(esp_spp_cb_event_t event, esp_spp_cb_param_t *param) {
  if (event == ESP_SPP_SRV_OPEN_EVT) {
    Serial.println("[rNotify: BT] Client Connected!");
    bt_is_connected = true;
  } else if (event == ESP_SPP_CLOSE_EVT) {
    Serial.println("[rNotify: BT] Client Disconnected!");
    bt_is_connected = false;
  }
}

// TFT Display instance (handles TOUCH_CS 33 and display SPI via User_Setup.h)
TFT_eSPI tft = TFT_eSPI();

// --- Touchscreen IRQ Pin (GPIO 36) ---
#define TOUCH_IRQ 36

// Host connection tracking (reported from R or auto)
static String last_host_port = "";
static String last_transport = "";

// --- Hardware Pins (ESP32 CYD variants) ---
#define PIN_LED_RED   4   // Active LOW RGB LED
#define PIN_LED_GREEN 16  // Active LOW RGB LED
#define PIN_LED_BLUE  17  // Active LOW RGB LED
#define PIN_BOOT_BTN  0   // Onboard BOOT switch for cycling interactive demo

// --- 16-Bit 565 RGB Color Macro ---
#define RGB565(r,g,b) (((((uint16_t)(r)) & 0xF8) << 8) | ((((uint16_t)(g)) & 0xFC) << 3) | (((uint16_t)(b)) >> 3))

// --- Cyberpunk / Glassmorphism Palette (16-bit 565 RGB) ---
// Midnight & Slate Backgrounds
#define COLOR_BG            RGB565(10, 14, 23)     // Deep Midnight (#0A0E17)
#define COLOR_NAVBAR        RGB565(15, 23, 42)     // Dark Navy Header (#0F172A)
#define COLOR_CARD_BG       RGB565(20, 28, 48)     // Sleek Slate Container (#141C30)
#define COLOR_CARD_BORDER   RGB565(42, 58, 88)     // Subtle Cyber Blue Border (#2A3A58)
#define COLOR_TRACK_BG      RGB565(12, 18, 30)     // Recessed Track (#0C121E)
#define COLOR_TRACK_BORDER  RGB565(28, 38, 58)     // Track Border (#1C263A)

// Neon Accent Palette
#define COLOR_CYAN_NEON     RGB565(0, 235, 255)    // Electric Cyan (#00EBFF)
#define COLOR_CYAN_GLOW     RGB565(0, 150, 220)    // Soft Cyan Glow
#define COLOR_GREEN_NEON    RGB565(0, 245, 110)    // Laser Emerald Green (#00F56E)
#define COLOR_GREEN_GLOW    RGB565(0, 140, 60)     // Emerald Glow
#define COLOR_AMBER_NEON    RGB565(255, 185, 0)    // Cyber Gold / Amber (#FFB900)
#define COLOR_PURPLE_NEON   RGB565(210, 75, 255)   // Electric Violet / Magenta (#D24BFF)
#define COLOR_PURPLE_SHEEN  RGB565(245, 175, 255)  // Light Violet Specular
#define COLOR_RED_NEON      RGB565(255, 50, 80)    // Neon Crimson / Coral Red (#FF3250)
#define COLOR_BLUE_NEON     RGB565(56, 189, 248)   // Sky Blue (#38BDF8)

// Typography Palette
#define COLOR_WHITE         0xFFFF                 // Pure Crisp White
#define COLOR_TEXT_SILVER   RGB565(203, 213, 225)  // Cool Silver (#CBD5E1)
#define COLOR_TEXT_MUTED    RGB565(100, 116, 139)  // Tech Slate Muted (#64748B)

// --- Onboard RGB LED Control (Active LOW) ---
void setRgbLed(uint8_t r, uint8_t g, uint8_t b) {
  digitalWrite(PIN_LED_RED,   r > 30 ? LOW : HIGH);
  digitalWrite(PIN_LED_GREEN, g > 30 ? LOW : HIGH);
  digitalWrite(PIN_LED_BLUE,  b > 30 ? LOW : HIGH);
}

void initRgbLed() {
  pinMode(PIN_LED_RED, OUTPUT);
  pinMode(PIN_LED_GREEN, OUTPUT);
  pinMode(PIN_LED_BLUE, OUTPUT);
  setRgbLed(0, 0, 0); // Off
}

// Convert Hex String "#RRGGBB" to 16-bit 565 color
uint16_t parseHexColor(const char* hex) {
  if (!hex || hex[0] != '#') return COLOR_CYAN_NEON;
  long number = strtol(&hex[1], NULL, 16);
  long r = (number >> 16) & 0xFF;
  long g = (number >> 8) & 0xFF;
  long b = number & 0xFF;
  return RGB565(r, g, b);
}

// Draw string safely with max character clamp to prevent layout overflowing
void drawTruncatedString(const char* str, int x, int y, int max_chars, int size, uint16_t color) {
  if (!str) return;
  char buf[64];
  int len = strlen(str);
  if (len > max_chars) {
    if (max_chars > 3) {
      strncpy(buf, str, max_chars - 3);
      buf[max_chars - 3] = '.';
      buf[max_chars - 2] = '.';
      buf[max_chars - 1] = '.';
      buf[max_chars] = '\0';
    } else {
      strncpy(buf, str, max_chars);
      buf[max_chars] = '\0';
    }
  } else {
    strncpy(buf, str, sizeof(buf) - 1);
    buf[sizeof(buf) - 1] = '\0';
  }
  tft.setTextSize(size);
  tft.setTextColor(color);
  tft.drawString(buf, x, y);
}

// Draw a modern rounded capsule pill badge with optional glowing status dot
void drawPillBadge(int x, int y, int w, int h, const char* text, uint16_t bg, uint16_t border, uint16_t fg, bool has_dot = false, uint16_t dot_color = 0) {
  tft.fillRoundRect(x, y, w, h, h / 2, bg);
  tft.drawRoundRect(x, y, w, h, h / 2, border);
  int text_x = x + 8;
  if (has_dot) {
    tft.fillCircle(x + 8, y + (h / 2), 3, dot_color);
    text_x = x + 16;
  }
  tft.setTextSize(1);
  tft.setTextColor(fg, bg);
  tft.drawString(text, text_x, y + ((h - 8) / 2));
}

// Draw a futuristic progress bar with recessed track and top specular sheen line
void drawGlossyBar(int x, int y, int w, int h, int pct, uint16_t fill_color, uint16_t sheen_color) {
  pct = constrain(pct, 0, 100);
  tft.fillRoundRect(x, y, w, h, 4, COLOR_TRACK_BG);
  tft.drawRoundRect(x, y, w, h, 4, COLOR_TRACK_BORDER);

  int max_fill_w = w - 4;
  int fill_w = (max_fill_w * pct) / 100;
  if (fill_w > 0) {
    int rad = 3;
    if (fill_w < 6) rad = 1;
    tft.fillRoundRect(x + 2, y + 2, fill_w, h - 4, rad, fill_color);
    if (fill_w > 8 && (h - 4) >= 8) {
      tft.drawFastHLine(x + 4, y + 3, fill_w - 6, sheen_color);
    }
  }
}

// Draw a side-by-side modular HUD metric card for digital time stats
void drawMetricCard(int x, int y, int w, int h, const char* label, const char* val, uint16_t accent_color, uint16_t val_color, const char* sublabel = "") {
  tft.fillRoundRect(x, y, w, h, 6, COLOR_CARD_BG);
  tft.drawRoundRect(x, y, w, h, 6, COLOR_CARD_BORDER);

  // Top glowing neon accent lines
  tft.drawFastHLine(x + 8, y, w - 16, accent_color);
  tft.drawFastHLine(x + 12, y + 1, w - 24, accent_color);

  // Accent dot & metric label
  tft.fillCircle(x + 14, y + 14, 3, accent_color);
  tft.setTextSize(1);
  tft.setTextColor(COLOR_TEXT_SILVER, COLOR_CARD_BG);
  tft.drawString(label, x + 24, y + 10);

  // Large bold digital value
  tft.setTextSize(2);
  tft.setTextColor(val_color, COLOR_CARD_BG);
  tft.drawString(val, x + 14, y + 28);

  // Sublabel / description
  if (sublabel && strlen(sublabel) > 0) {
    tft.setTextSize(1);
    tft.setTextColor(COLOR_TEXT_MUTED, COLOR_CARD_BG);
    tft.drawString(sublabel, x + 14, y + 52);
  }
}

// --- Touchscreen Corner Reset Button ---
void drawCornerResetButton() {
  int W = tft.width();
  int btn_w = (W > 320) ? 56 : 46;
  int btn_h = (W > 320) ? 24 : 22;
  int btn_x = W - btn_w - 5;
  int btn_y = 4;

  tft.fillRoundRect(btn_x, btn_y, btn_w, btn_h, 4, RGB565(45, 12, 18));
  tft.drawRoundRect(btn_x, btn_y, btn_w, btn_h, 4, COLOR_RED_NEON);

  // Glowing Red indicator dot
  tft.fillCircle(btn_x + 9, btn_y + (btn_h / 2), 3, COLOR_RED_NEON);

  tft.setTextSize(1);
  tft.setTextColor(COLOR_WHITE, RGB565(45, 12, 18));
  tft.drawString("RST", btn_x + 18, btn_y + (btn_h / 2) - 4);
}

// --- Check Touchscreen System Reset ---
void checkTouchReset() {
  // 1. Boot grace period: NEVER trigger reset within first 4 seconds after boot
  if (millis() < 4000) return;

  uint16_t tx = 0, ty = 0;
  if (tft.getTouch(&tx, &ty, 400)) {
    int W = tft.width();
    int H = tft.height();
    int btn_w = (W > 320) ? 56 : 46;
    int btn_h = (W > 320) ? 24 : 22;
    int btn_x = W - btn_w - 5;
    int btn_y = 4;

    static unsigned long last_touch_log = 0;
    if (millis() - last_touch_log > 200) {
      last_touch_log = millis();
      Serial.printf("[rNotify Touch] Screen: (%d, %d)\n", tx, ty);
    }

    // 2. Check if touch is within top-right corner reset button (with generous hit margin)
    bool in_corner = (tx >= (btn_x - 15) && ty <= (btn_y + btn_h + 15));

    if (in_corner) {
      // Debounce: must be held for 250ms
      static unsigned long press_start = 0;
      if (press_start == 0) {
        press_start = millis();
        return;
      }
      if (millis() - press_start < 250) {
        return;
      }
      press_start = 0;

      Serial.println("[rNotify] Touchscreen Reset triggered! Rebooting ESP32 CYD...");

      // 1. Highlight button
      tft.fillRoundRect(btn_x, btn_y, btn_w, btn_h, 4, COLOR_RED_NEON);
      tft.setTextSize(1);
      tft.setTextColor(COLOR_WHITE, COLOR_RED_NEON);
      tft.drawString("RST!", btn_x + 14, btn_y + (btn_h / 2) - 4);

      // 2. High-vis Red LED feedback
      setRgbLed(255, 0, 0);

      // 3. Central reboot alert dialog
      int modal_w = (W > 320) ? 280 : 200;
      int modal_h = 60;
      int modal_x = (W - modal_w) / 2;
      int modal_y = (H - modal_h) / 2;

      tft.fillRoundRect(modal_x, modal_y, modal_w, modal_h, 6, RGB565(20, 28, 48));
      tft.drawRoundRect(modal_x, modal_y, modal_w, modal_h, 6, COLOR_RED_NEON);
      tft.drawFastHLine(modal_x + 10, modal_y, modal_w - 20, COLOR_RED_NEON);

      tft.setTextSize(1);
      tft.setTextColor(COLOR_RED_NEON, RGB565(20, 28, 48));
      tft.drawCentreString("// SYSTEM REBOOT //", W / 2, modal_y + 12, 1);

      tft.setTextSize(2);
      tft.setTextColor(COLOR_WHITE, RGB565(20, 28, 48));
      tft.drawCentreString("REBOOTING...", W / 2, modal_y + 30, 1);

      delay(500);
      setRgbLed(0, 0, 0);
      ESP.restart();
    }
  }
}

// --- Artistic Boot & Standby / Idle Screen ---
void showIdleScreen() {
  int W = tft.width();
  int H = tft.height();
  int card_w = W - 14;

  tft.fillScreen(COLOR_BG);

  // 1. Top Cyber Navbar (y=4, h=22)
  tft.fillRoundRect(7, 4, card_w, 22, 4, COLOR_NAVBAR);
  tft.drawRoundRect(7, 4, card_w, 22, 4, COLOR_CARD_BORDER);

  // Left Brand Badge
  drawPillBadge(11, 6, 72, 18, "rNotify", COLOR_CARD_BG, COLOR_CYAN_NEON, COLOR_CYAN_NEON, false);

  // Center Navbar Status
  tft.setTextSize(1);
  tft.setTextColor(COLOR_TEXT_SILVER, COLOR_NAVBAR);
  tft.drawString("TELEMETRY DECK // IDLE", 90, 11);

  // Top-Right Corner Touchscreen Reset Button
  drawCornerResetButton();

  // 2. Main Artistic Hero Focal Point: "R-Notify"
  int hero_y = 30;
  int hero_h = (H > 240) ? 80 : 66;
  tft.fillRoundRect(7, hero_y, card_w, hero_h, 6, COLOR_CARD_BG);
  tft.drawRoundRect(7, hero_y, card_w, hero_h, 6, COLOR_CARD_BORDER);

  // Multi-color glowing accent line on top of hero card (Cyan -> Purple -> Emerald)
  int seg_w = (card_w - 20) / 3;
  tft.drawFastHLine(17, hero_y, seg_w, COLOR_CYAN_NEON);
  tft.drawFastHLine(17 + seg_w, hero_y, seg_w, COLOR_PURPLE_NEON);
  tft.drawFastHLine(17 + seg_w * 2, hero_y, card_w - 20 - seg_w * 2, COLOR_GREEN_NEON);
  tft.drawFastHLine(25, hero_y + 1, card_w - 36, COLOR_CYAN_GLOW);

  // Cyber decorative corner tags
  tft.setTextSize(1);
  tft.setTextColor(COLOR_PURPLE_NEON, COLOR_CARD_BG);
  tft.drawString("// STATISTICAL MONITOR //", 18, hero_y + 8);

  tft.setTextColor(COLOR_TEXT_MUTED, COLOR_CARD_BG);
  tft.drawRightString("ESP32-CYD", card_w - 6, hero_y + 8, 1);

  // Large Glowing Artistic "R-Notify" Title (3D Layered Neon Glow)
  tft.setTextSize(3);
  tft.setTextColor(COLOR_PURPLE_NEON, COLOR_CARD_BG);
  tft.drawString("R-Notify", 24, hero_y + 24);
  tft.setTextColor(COLOR_CYAN_GLOW, COLOR_CARD_BG);
  tft.drawString("R-Notify", 23, hero_y + 23);
  tft.setTextColor(COLOR_WHITE, COLOR_CARD_BG);
  tft.drawString("R-Notify", 22, hero_y + 22);

  // Hero Subtitle Badge
  tft.setTextSize(1);
  tft.setTextColor(COLOR_CYAN_NEON, COLOR_CARD_BG);
  tft.drawString("AUTONOMOUS JOB HUD", 175, hero_y + 25);
  tft.setTextColor(COLOR_TEXT_SILVER, COLOR_CARD_BG);
  tft.drawString("Real-Time R Telemetry", 175, hero_y + 38);

  // 3. Dual Telemetry Indicators (Bluetooth & USB Cable)
  int row_y = hero_y + hero_h + 6;
  int row_h = H - row_y - 24;
  int col_w = (card_w - 6) / 2;
  int col1_x = 7;
  int col2_x = 7 + col_w + 6;

  // --- Column 1: Bluetooth Link ---
  tft.fillRoundRect(col1_x, row_y, col_w, row_h, 6, COLOR_CARD_BG);
  tft.drawRoundRect(col1_x, row_y, col_w, row_h, 6, COLOR_CARD_BORDER);
  tft.drawFastHLine(col1_x + 8, row_y, col_w - 16, COLOR_BLUE_NEON);

  // Bluetooth Header
  tft.fillCircle(col1_x + 12, row_y + 11, 3, COLOR_BLUE_NEON);
  tft.setTextSize(1);
  tft.setTextColor(COLOR_BLUE_NEON, COLOR_CARD_BG);
  tft.drawString("BLUETOOTH LINK", col1_x + 20, row_y + 8);

  bool bt_active = SerialBT.hasClient() || bt_is_connected;
  int num_bonded = esp_bt_gap_get_bond_device_num();
  bool bt_bonded = (num_bonded > 0) || (last_transport == "bluetooth");

  if (bt_active) {
    drawPillBadge(col1_x + 8, row_y + 22, col_w - 16, 18, "CONNECTED", RGB565(10, 40, 20), COLOR_GREEN_NEON, COLOR_GREEN_NEON, true, COLOR_GREEN_NEON);
  } else if (bt_bonded) {
    drawPillBadge(col1_x + 8, row_y + 22, col_w - 16, 18, "PAIRED (STANDBY)", RGB565(15, 30, 48), COLOR_BLUE_NEON, COLOR_BLUE_NEON, true, COLOR_BLUE_NEON);
  } else {
    drawPillBadge(col1_x + 8, row_y + 22, col_w - 16, 18, "READY TO PAIR", RGB565(40, 30, 10), COLOR_AMBER_NEON, COLOR_AMBER_NEON, true, COLOR_AMBER_NEON);
  }

  // Device Name
  tft.setTextSize(1);
  tft.setTextColor(COLOR_TEXT_SILVER, COLOR_CARD_BG);
  tft.drawString(BT_DEVICE_NAME, col1_x + 10, row_y + 44);

  // Host Port info
  tft.setTextColor(COLOR_WHITE, COLOR_CARD_BG);
  if (last_transport == "bluetooth" && last_host_port.length() > 0) {
    tft.drawString("Host: " + last_host_port, col1_x + 10, row_y + 58);
  } else if (last_host_port.length() > 0 && last_host_port.startsWith("COM")) {
    tft.drawString("Host: " + last_host_port, col1_x + 10, row_y + 58);
  } else {
    tft.setTextColor(COLOR_TEXT_MUTED, COLOR_CARD_BG);
    tft.drawString("Host: Auto (COM8-11)", col1_x + 10, row_y + 58);
  }

  // Speed / Protocol
  tft.setTextColor(COLOR_TEXT_MUTED, COLOR_CARD_BG);
  tft.drawString("115200 Baud | SPP", col1_x + 10, row_y + 72);

  // --- Column 2: USB Cable Serial ---
  tft.fillRoundRect(col2_x, row_y, col_w, row_h, 6, COLOR_CARD_BG);
  tft.drawRoundRect(col2_x, row_y, col_w, row_h, 6, COLOR_CARD_BORDER);
  tft.drawFastHLine(col2_x + 8, row_y, col_w - 16, COLOR_CYAN_NEON);

  // Cable Header
  tft.fillCircle(col2_x + 12, row_y + 11, 3, COLOR_CYAN_NEON);
  tft.setTextSize(1);
  tft.setTextColor(COLOR_CYAN_NEON, COLOR_CARD_BG);
  tft.drawString("USB CABLE SERIAL", col2_x + 20, row_y + 8);

  // Cable Status Pill
  drawPillBadge(col2_x + 8, row_y + 22, col_w - 16, 18, "CONNECTED", RGB565(10, 30, 48), COLOR_CYAN_NEON, COLOR_CYAN_NEON, true, COLOR_CYAN_NEON);

  // USB Driver
  tft.setTextSize(1);
  tft.setTextColor(COLOR_TEXT_SILVER, COLOR_CARD_BG);
  tft.drawString("CH340 / CP210x UART", col2_x + 10, row_y + 44);

  // Cable Host Port info
  tft.setTextColor(COLOR_WHITE, COLOR_CARD_BG);
  if (last_transport == "serial" && last_host_port.length() > 0) {
    tft.drawString("Host: " + last_host_port, col2_x + 10, row_y + 58);
  } else if (last_host_port.length() > 0 && last_host_port.startsWith("COM")) {
    tft.drawString("Host: " + last_host_port, col2_x + 10, row_y + 58);
  } else {
    tft.setTextColor(COLOR_TEXT_MUTED, COLOR_CARD_BG);
    tft.drawString("Host: Auto (COM12)", col2_x + 10, row_y + 58);
  }

  // Speed / Protocol
  tft.setTextColor(COLOR_TEXT_MUTED, COLOR_CARD_BG);
  tft.drawString("115200 Baud | USB", col2_x + 10, row_y + 72);

  // 4. Footer Strip
  int footer_y = H - 18;
  tft.drawFastHLine(7, footer_y - 2, card_w, COLOR_TRACK_BORDER);
  tft.fillCircle(14, footer_y + 6, 3, COLOR_CYAN_NEON);
  tft.setTextSize(1);
  tft.setTextColor(COLOR_CYAN_NEON, COLOR_BG);
  tft.drawString("STANDBY", 22, footer_y + 2);

  tft.setTextColor(COLOR_TEXT_MUTED, COLOR_BG);
  tft.drawString("Listening...  |  Touch [RST] to Reboot CYD", 76, footer_y + 2);

  setRgbLed(0, 0, 0); // Off (Standby / Idle)
}

// Forward declaration for demo cycle
void runDemoCycle();

// --- Flicker-Free Selective Redraw State Tracking ---
static bool is_screen_active = false;
static String last_title = "";
static String last_status = "";
static int last_progress_pct = -1;
static int last_inner_pct = -1;
static String last_message = "";
static String last_elapsed = "";
static String last_eta = "";
static String last_step_info = "";
static String last_inner_info = "";
static bool last_had_inner = false;

// Reset all display and telemetry states back to clean boot/standby console
void resetScreenState() {
  is_screen_active = false;
  last_title = "";
  last_status = "";
  last_progress_pct = -1;
  last_inner_pct = -1;
  last_message = "";
  last_elapsed = "";
  last_eta = "";
  last_step_info = "";
  last_inner_info = "";
  last_had_inner = false;
  showIdleScreen();
}

// --- Live Telemetry Rendering Engine ---
void renderPayload(const JsonDocument& doc) {
  int W = tft.width();
  int H = tft.height();
  int card_w = W - 14;

  const char* title       = doc["title"] | "R Job";
  const char* status_text = doc["status_text"] | "RUNNING";
  const char* color_hex   = doc["status_color"] | "#00F0FF";
  int progress_pct        = doc["progress_pct"] | 0;
  const char* step_info   = doc["step_info"] | "";
  int inner_pct           = doc["inner_pct"] | 0;
  const char* inner_info  = doc["inner_info"] | "";
  const char* message     = doc["message"] | "";
  const char* elapsed     = doc["elapsed"] | "00:00:00";
  const char* eta         = doc["eta"] | "--:--:--";

  bool is_complete   = (strcmp(status_text, "COMPLETE") == 0);
  bool is_failed     = (strcmp(status_text, "FAILED") == 0 || strcmp(status_text, "CRASHED") == 0);
  bool is_started    = (strcmp(status_text, "STARTED") == 0);
  bool is_term_state = is_complete || is_failed;

  // Modern Neon Status Colors
  uint16_t status_color = COLOR_CYAN_NEON;
  uint16_t status_sheen = COLOR_WHITE;
  uint16_t badge_bg     = RGB565(10, 30, 48);

  if (is_complete) {
    status_color = COLOR_GREEN_NEON;
    status_sheen = RGB565(180, 255, 200);
    badge_bg     = RGB565(10, 40, 20);
    setRgbLed(0, 255, 0); // Bright Green
  } else if (is_failed) {
    status_color = COLOR_RED_NEON;
    status_sheen = RGB565(255, 180, 190);
    badge_bg     = RGB565(50, 10, 20);
    setRgbLed(255, 0, 30); // Crimson Red
  } else if (is_started) {
    status_color = COLOR_AMBER_NEON;
    status_sheen = RGB565(255, 240, 180);
    badge_bg     = RGB565(40, 30, 10);
    setRgbLed(255, 150, 0); // Amber
  } else {
    // RUNNING or custom
    status_color = parseHexColor(color_hex);
    if (status_color == COLOR_CYAN_NEON) status_sheen = COLOR_WHITE;
    else status_sheen = RGB565(200, 240, 255);
    badge_bg     = RGB565(10, 30, 48);
    setRgbLed(0, 160, 255); // Electric Cyan
  }

  // Layout Dynamic Coordinates
  int job_y   = 29;
  int job_h   = (H > 240) ? 50 : 44;
  int outer_y = (H > 240) ? 86 : 76;
  int bar_h   = (H > 240) ? 16 : 14;
  int inner_y = (H > 240) ? 122 : 108;
  int hud_y   = (H > 240) ? 172 : 140;
  int hud_h   = (H > 240) ? 104 : 76;
  int half_w  = (card_w / 2) - 4;
  int left_x  = 7;
  int right_x = 7 + half_w + 8;
  int footer_y = H - 19;

  bool has_inner = (strlen(inner_info) > 0 || inner_pct > 0);
  bool is_new_job = !is_screen_active || (last_title != title) || is_started || is_term_state;

  if (is_new_job) {
    tft.fillScreen(COLOR_BG);
    is_screen_active = !is_term_state;
    last_title = title;
    last_status = status_text;
    last_had_inner = has_inner;
    last_progress_pct = -1;
    last_inner_pct = -1;
    last_message = "";
    last_elapsed = "";
    last_eta = "";
    last_step_info = "";
    last_inner_info = "";

    // 1. Top Cyber Navbar (y=4, h=22)
    tft.fillRoundRect(7, 4, card_w, 22, 4, COLOR_NAVBAR);
    tft.drawRoundRect(7, 4, card_w, 22, 4, COLOR_CARD_BORDER);

    // Left Brand Pill
    drawPillBadge(11, 6, 62, 18, "rNotify", COLOR_CARD_BG, COLOR_CYAN_NEON, COLOR_CYAN_NEON, false);

    // Center Status Pill
    drawPillBadge(77, 6, 110, 18, status_text, badge_bg, status_color, status_color, true, status_color);

    // Right Transport Pill
    String trans_pill = (last_host_port.length() > 0) ? last_host_port : "BT/USB";
    drawPillBadge(191, 6, 66, 18, trans_pill.c_str(), COLOR_CARD_BG, COLOR_CARD_BORDER, COLOR_TEXT_SILVER, false);

    // Top-Right Corner Touchscreen Reset Button
    drawCornerResetButton();

    // 2. Job Hero Card
    tft.fillRoundRect(7, job_y, card_w, job_h, 5, COLOR_CARD_BG);
    tft.drawRoundRect(7, job_y, card_w, job_h, 5, COLOR_CARD_BORDER);

    // Vertical neon status bar
    tft.fillRoundRect(7, job_y, 4, job_h, 2, status_color);

    // Job Title
    int max_title_chars = (W > 320) ? 36 : 24;
    drawTruncatedString(title, 18, job_y + 4, max_title_chars, 2, COLOR_WHITE);

    // 3. Outer Progress Section Header
    tft.setTextSize(1);
    tft.setTextColor(COLOR_CYAN_GLOW, COLOR_BG);
    tft.drawString("OUTER PROGRESS", 8, outer_y + 1);

    // 4. Subtask Loop Header & Recessed Track
    tft.setTextSize(1);
    tft.setTextColor(COLOR_PURPLE_NEON, COLOR_BG);
    tft.drawString("SUBTASK LOOP", 8, inner_y + 1);
    drawGlossyBar(8, inner_y + 15, card_w, (H > 240 ? 14 : 12), 0, COLOR_PURPLE_NEON, COLOR_PURPLE_SHEEN);

    // 5. Dual HUD Metric Cards (Side-by-Side Responsive Layout)
    // Left: Elapsed
    drawMetricCard(left_x, hud_y, half_w, hud_h, "TIME ELAPSED", elapsed, COLOR_CYAN_NEON, COLOR_WHITE, "SESSION TIMER");

    // Right: ETA
    const char* eta_val = is_complete ? "COMPLETE" : (is_failed ? "ABORTED" : eta);
    uint16_t eta_color = is_complete ? COLOR_GREEN_NEON : (is_failed ? COLOR_RED_NEON : COLOR_AMBER_NEON);
    drawMetricCard(right_x, hud_y, half_w, hud_h, "PROJECTED ETA", eta_val, eta_color, eta_color, is_complete ? "JOB SUCCESS" : "TIME REMAINING");

    // 6. Footer Telemetry Strip
    tft.drawFastHLine(8, footer_y - 2, card_w, COLOR_TRACK_BORDER);
    tft.fillCircle(14, footer_y + 6, 3, COLOR_CYAN_NEON);
    tft.setTextSize(1);
    tft.setTextColor(COLOR_TEXT_MUTED, COLOR_BG);
    tft.drawString("LINK: rNotify-CYD (SPP)", 22, footer_y + 2);
    tft.drawString("DESK HUD v0.1", card_w - 65, footer_y + 2);
  } else if (last_status != status_text) {
    // Redraw status badge in top navbar if state changed
    last_status = status_text;
    drawPillBadge(86, 6, 120, 18, status_text, badge_bg, status_color, status_color, true, status_color);
  }

  // --- Dynamic Content Partial Redraws (Zero Screen Flicker) ---

  // 1. Message Line in Job Card
  if (last_message != message) {
    last_message = message;
    tft.fillRect(18, job_y + 24, card_w - 24, 16, COLOR_CARD_BG);
    char msg_buf[64];
    if (strlen(message) > 0) {
      snprintf(msg_buf, sizeof(msg_buf), "> %s", message);
    } else {
      snprintf(msg_buf, sizeof(msg_buf), "> %s", is_complete ? "Job finished." : "Executing batch...");
    }
    int max_msg_chars = (W > 320) ? 68 : 46;
    drawTruncatedString(msg_buf, 18, job_y + 25, max_msg_chars, 1, is_complete ? COLOR_GREEN_NEON : (is_failed ? COLOR_RED_NEON : COLOR_AMBER_NEON));
  }

  // 2. Outer Progress Step & Percentage
  if (last_progress_pct != progress_pct || last_step_info != step_info) {
    last_progress_pct = progress_pct;
    last_step_info = step_info;

    // Clear and redraw step count
    tft.fillRect(108, outer_y, 130, 12, COLOR_BG);
    tft.setTextSize(1);
    tft.setTextColor(COLOR_WHITE, COLOR_BG);
    if (strlen(step_info) > 0) {
      char step_buf[32];
      snprintf(step_buf, sizeof(step_buf), "Step %s", step_info);
      tft.drawString(step_buf, 108, outer_y + 1);
    }

    // Clear and redraw percentage badge
    tft.fillRect(card_w - 45, outer_y - 2, 52, 14, COLOR_BG);
    char pct_str[16];
    snprintf(pct_str, sizeof(pct_str), "%d%%", progress_pct);
    drawPillBadge(card_w - 40, outer_y - 2, 46, 14, pct_str, COLOR_CARD_BG, status_color, status_color, false);

    // Update outer progress bar fill
    drawGlossyBar(8, outer_y + 15, card_w, bar_h, progress_pct, status_color, status_sheen);
  }

  // 3. Inner Loop Subtask Progress
  if (last_inner_pct != inner_pct || last_inner_info != inner_info) {
    last_inner_pct = inner_pct;
    last_inner_info = inner_info;

    // Clear and redraw inner step count
    tft.fillRect(100, inner_y, 138, 12, COLOR_BG);
    tft.setTextSize(1);
    tft.setTextColor(COLOR_WHITE, COLOR_BG);
    if (strlen(inner_info) > 0) {
      char inner_buf[32];
      snprintf(inner_buf, sizeof(inner_buf), "Rep %s", inner_info);
      tft.drawString(inner_buf, 100, inner_y + 1);
    }

    // Clear and redraw inner percentage badge
    tft.fillRect(card_w - 45, inner_y - 2, 52, 14, COLOR_BG);
    char in_pct_str[16];
    snprintf(in_pct_str, sizeof(in_pct_str), "%d%%", inner_pct);
    drawPillBadge(card_w - 40, inner_y - 2, 46, 14, in_pct_str, COLOR_CARD_BG, COLOR_PURPLE_NEON, COLOR_PURPLE_NEON, false);

    // Update inner progress bar fill
    drawGlossyBar(8, inner_y + 15, card_w, (H > 240 ? 14 : 12), inner_pct, COLOR_PURPLE_NEON, COLOR_PURPLE_SHEEN);
  }

  // 4. Elapsed Time Digit Box inside Metric Card
  if (last_elapsed != elapsed) {
    last_elapsed = elapsed;
    tft.fillRect(left_x + 12, hud_y + 26, half_w - 20, 22, COLOR_CARD_BG);
    tft.setTextSize(2);
    tft.setTextColor(COLOR_WHITE, COLOR_CARD_BG);
    tft.drawString(elapsed, left_x + 14, hud_y + 28);
  }

  // 5. ETA Digit Box inside Metric Card
  if (last_eta != eta) {
    last_eta = eta;
    tft.fillRect(right_x + 12, hud_y + 26, half_w - 20, 22, COLOR_CARD_BG);
    tft.setTextSize(2);
    const char* eta_val = is_complete ? "COMPLETE" : (is_failed ? "ABORTED" : eta);
    uint16_t eta_color = is_complete ? COLOR_GREEN_NEON : (is_failed ? COLOR_RED_NEON : COLOR_AMBER_NEON);
    tft.setTextColor(eta_color, COLOR_CARD_BG);
    tft.drawString(eta_val, right_x + 14, hud_y + 28);
  }
}

// --- Interactive Hardware Demo Mode (Cycles through showcase screens) ---
void runDemoCycle() {
  static int demo_step = 0;
  demo_step = (demo_step + 1) % 4;

  if (demo_step == 0) {
    showIdleScreen();
  } else if (demo_step == 1) {
    StaticJsonDocument<512> doc;
    doc["title"] = "MCMC Bayesian Model";
    doc["status_text"] = "RUNNING";
    doc["status_color"] = "#00EBFF";
    doc["progress_pct"] = 42;
    doc["step_info"] = "2 / 4";
    doc["inner_pct"] = 68;
    doc["inner_info"] = "1360 / 2000";
    doc["message"] = "Sampling posterior distribution...";
    doc["elapsed"] = "00:08:42";
    doc["eta"] = "00:12:15";
    renderPayload(doc);
  } else if (demo_step == 2) {
    StaticJsonDocument<512> doc;
    doc["title"] = "Bootstrap Simulation";
    doc["status_text"] = "COMPLETE";
    doc["status_color"] = "#00F56E";
    doc["progress_pct"] = 100;
    doc["step_info"] = "1000 / 1000";
    doc["inner_pct"] = 100;
    doc["inner_info"] = "Done";
    doc["message"] = "Converged! All replicates successful.";
    doc["elapsed"] = "00:24:19";
    doc["eta"] = "DONE";
    renderPayload(doc);
  } else if (demo_step == 3) {
    StaticJsonDocument<512> doc;
    doc["title"] = "High-Dim Optimization";
    doc["status_text"] = "FAILED";
    doc["status_color"] = "#FF3250";
    doc["progress_pct"] = 35;
    doc["step_info"] = "35 / 100";
    doc["inner_pct"] = 0;
    doc["inner_info"] = "";
    doc["message"] = "Gradient explosion: Non-finite loss";
    doc["elapsed"] = "00:05:11";
    doc["eta"] = "--:--:--";
    renderPayload(doc);
  }
}

void processLine(const String& line) {
  if (line == "demo" || line == "{\"action\":\"demo\"}") {
    runDemoCycle();
    return;
  }
  if (line == "reset" || line == "{\"action\":\"reset\"}" || line == "{\"event\":\"reset\"}" || line.indexOf("\"reset\"") >= 0) {
    resetScreenState();
    return;
  }
  StaticJsonDocument<1024> doc;
  DeserializationError error = deserializeJson(doc, line);
  if (error) {
    if (line == "reset" || line.indexOf("reset") >= 0) {
      resetScreenState();
    } else {
      Serial.printf("[rNotify] JSON Parse Error: %s\n", error.c_str());
    }
    return;
  }

  const char* port = doc["port"] | "";
  const char* trans = doc["transport"] | "";
  if (strlen(port) > 0) {
    last_host_port = String(port);
  }
  if (strlen(trans) > 0) {
    last_transport = String(trans);
  }

  const char* act = doc["action"] | "";
  const char* evt = doc["event"] | "";
  if (strcmp(act, "reset") == 0 || strcmp(evt, "reset") == 0) {
    resetScreenState();
    return;
  }
  renderPayload(doc);
}

#if ENABLE_WIFI
void handleNotifyHttp() {
  if (server.method() != HTTP_POST) {
    server.send(405, "text/plain", "Method Not Allowed");
    return;
  }
  String body = server.arg("plain");
  processLine(body);
  server.send(200, "application/json", "{\"status\":\"ok\"}");
}
#endif

void setup() {
  Serial.begin(115200);
  delay(200);
  Serial.println("\n[rNotify] Starting CYD Cyberdeck Bluetooth & Serial Monitor...");

  // Power on display backlight across all CYD variants (GPIO 21 on 2.8", GPIO 27 on 3.5")
  pinMode(21, OUTPUT);
  digitalWrite(21, HIGH);
  pinMode(27, OUTPUT);
  digitalWrite(27, HIGH);

  // Configure onboard BOOT button (GPIO 0) for interactive demo mode
  pinMode(PIN_BOOT_BTN, INPUT_PULLUP);

  initRgbLed();
  setRgbLed(0, 0, 255); // Boot indication

  tft.init();
  tft.setRotation(1); // Landscape mode
  tft.fillScreen(COLOR_BG);

  // Ensure SD card CS (GPIO 5) is deselected HIGH so it doesn't pull SPI lines
  pinMode(5, OUTPUT);
  digitalWrite(5, HIGH);

  // Initialize Touch Calibration from NVS (Preferences)
  pinMode(TOUCH_IRQ, INPUT);
  Preferences prefs;
  prefs.begin("cyd_touch", false);
  uint16_t calData[5];
  bool need_cal = false;

  // Check if touch is held down at boot to force re-calibration
  if (digitalRead(TOUCH_IRQ) == LOW) {
    need_cal = true;
  } else if (prefs.isKey("calData")) {
    prefs.getBytes("calData", calData, sizeof(calData));
    tft.setTouch(calData);
    Serial.printf("[rNotify] Loaded touch calibration from NVS: {%d, %d, %d, %d, %d}\n",
                  calData[0], calData[1], calData[2], calData[3], calData[4]);
  } else {
    need_cal = true;
  }

  if (need_cal) {
    tft.fillScreen(COLOR_BG);
    tft.setTextColor(COLOR_WHITE, COLOR_BG);
    tft.setTextSize(2);
    tft.drawCentreString("TOUCH SCREEN CALIBRATION", tft.width() / 2, tft.height() / 2 - 25, 1);
    tft.setTextSize(1);
    tft.setTextColor(COLOR_CYAN_NEON, COLOR_BG);
    tft.drawCentreString("Touch each corner target as it appears...", tft.width() / 2, tft.height() / 2 + 10, 1);
    delay(1000);
    tft.calibrateTouch(calData, COLOR_CYAN_NEON, COLOR_BG, 18);
    prefs.putBytes("calData", calData, sizeof(calData));
    tft.setTouch(calData);
    Serial.printf("[rNotify] New touch calibration saved to NVS: {%d, %d, %d, %d, %d}\n",
                  calData[0], calData[1], calData[2], calData[3], calData[4]);
  }
  prefs.end();

  // Initialize Bluetooth Serial
  SerialBT.register_callback(btCallback);
  if (!SerialBT.begin(BT_DEVICE_NAME)) {
    Serial.println("[rNotify] An error occurred initializing Bluetooth");
  } else {
    Serial.printf("[rNotify] Bluetooth initialized! Device name: %s\n", BT_DEVICE_NAME);
  }

#if ENABLE_WIFI
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  server.on("/api/notify", HTTP_POST, handleNotifyHttp);
  server.begin();
#endif

  showIdleScreen();
  Serial.println("[rNotify] Ready to receive telemetry over Bluetooth or USB Serial.");
  Serial.println("[rNotify] Tip: Touch [RST] in top-right corner to perform system reset.");
}

void loop() {
  // 1. Check for touchscreen reset button press in top-right corner
  checkTouchReset();

  // 2. Refresh idle screen dynamically if Bluetooth client connects/disconnects while idling
  static bool last_bt_client_state = false;
  static unsigned long last_idle_refresh = 0;
  if (!is_screen_active && (millis() - last_idle_refresh > 1000)) {
    last_idle_refresh = millis();
    bool cur_bt_client_state = SerialBT.hasClient() || bt_is_connected;
    if (cur_bt_client_state != last_bt_client_state) {
      last_bt_client_state = cur_bt_client_state;
      showIdleScreen();
    }
  }

  // 3. Check for onboard BOOT button press (GPIO 0) to cycle demo preview
  static unsigned long last_btn_press = 0;
  if (digitalRead(PIN_BOOT_BTN) == LOW && (millis() - last_btn_press > 400)) {
    last_btn_press = millis();
    runDemoCycle();
  }

  // 4. Check for incoming Bluetooth data
  if (SerialBT.available()) {
    String line = SerialBT.readStringUntil('\n');
    line.trim();
    if (line.length() > 0) {
      Serial.println("[rNotify: BT Rx] " + line);
      processLine(line);
    }
  }

  // 5. Check for incoming USB Serial data
  if (Serial.available()) {
    String line = Serial.readStringUntil('\n');
    line.trim();
    if (line.length() > 0 && (line.startsWith("{") || line == "demo" || line == "reset")) {
      Serial.println("[rNotify: Serial Rx] " + line);
      processLine(line);
      Serial.println("{\"status\":\"ok\"}");
    }
  }

#if ENABLE_WIFI
  server.handleClient();
#endif
}
