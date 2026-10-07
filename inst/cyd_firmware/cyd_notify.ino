/*
 * rNotify CYD (Cheap Yellow Display) ESP32 Firmware
 * Hardware: ESP32-2432S028R (2.8" 320x240 TFT LCD with ILI9341)
 *
 * Transports Supported:
 * 1. Bluetooth Serial (SPP) - Device Name: "rNotify-CYD"
 * 2. USB Serial (115200 baud)
 * 3. Optional Wi-Fi HTTP REST (POST http://<CYD_IP>/api/notify)
 *
 * Dependencies (install via Arduino Library Manager or arduino-cli):
 * - TFT_eSPI (configured for ESP32-2432S028R)
 * - ArduinoJson (v6 or v7)
 * - BluetoothSerial (included with ESP32 core)
 */

#include <BluetoothSerial.h>
#include <TFT_eSPI.h>
#include <ArduinoJson.h>

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

// TFT Display instance
TFT_eSPI tft = TFT_eSPI();

// --- Onboard RGB LED Pins (ESP32-2432S028R, Active LOW) ---
#define PIN_LED_RED   4
#define PIN_LED_GREEN 16
#define PIN_LED_BLUE  17

// --- Status Colors (16-bit 565 RGB) ---
#define COLOR_BG        0x0000 // Black
#define COLOR_CARD_BG   0x18E3 // Dark Gray / Slate
#define COLOR_WHITE     0xFFFF
#define COLOR_CYAN      0x067F // Running / Start
#define COLOR_GREEN     0x07E0 // Success / Complete
#define COLOR_YELLOW    0xFDE0 // Warning / Setup
#define COLOR_RED       0xF800 // Failed / Crashed
#define COLOR_BAR_BG    0x39E7 // Gray bar track

void setRgbLed(uint8_t r, uint8_t g, uint8_t b) {
  // CYD onboard RGB LED is active-LOW
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

uint16_t parseHexColor(const char* hex) {
  if (!hex || hex[0] != '#') return COLOR_CYAN;
  long number = strtol(&hex[1], NULL, 16);
  long r = (number >> 16) & 0xFF;
  long g = (number >> 8) & 0xFF;
  long b = number & 0xFF;
  return tft.color565(r, g, b);
}

void drawProgressBar(int x, int y, int w, int h, int pct, uint16_t color) {
  tft.drawRect(x, y, w, h, COLOR_WHITE);
  tft.fillRect(x + 1, y + 1, w - 2, h - 2, COLOR_BAR_BG);
  int fill_w = ((w - 2) * constrain(pct, 0, 100)) / 100;
  if (fill_w > 0) {
    tft.fillRect(x + 1, y + 1, fill_w, h - 2, color);
  }
}

void showIdleScreen() {
  tft.fillScreen(COLOR_BG);

  // 1. Top Header Banner
  tft.fillRect(0, 0, 320, 28, COLOR_CYAN);
  tft.setTextColor(COLOR_BG, COLOR_CYAN);
  tft.setTextSize(2);
  tft.drawString("BLUETOOTH READY", 8, 6);

  tft.setTextSize(1);
  tft.setTextColor(COLOR_WHITE, COLOR_CYAN);
  tft.drawString("rNotify v0.1", 235, 10);

  // 2. Desk Monitor Title
  tft.setTextSize(2);
  tft.setTextColor(COLOR_WHITE, COLOR_BG);
  tft.drawString("rNotify Desk Monitor", 8, 38);

  // 3. Status Box
  tft.fillRect(8, 70, 304, 75, COLOR_CARD_BG);
  tft.drawRect(8, 70, 304, 75, COLOR_WHITE);

  tft.setTextColor(COLOR_CYAN, COLOR_CARD_BG);
  tft.setTextSize(1);
  tft.drawString("BLUETOOTH DEVICE NAME:", 18, 80);

  tft.setTextColor(COLOR_GREEN, COLOR_CARD_BG);
  tft.setTextSize(2);
  tft.drawString(BT_DEVICE_NAME, 18, 98);

  tft.setTextColor(0x7BEF, COLOR_CARD_BG);
  tft.setTextSize(1);
  tft.drawString("SPP Serial Link Active (or USB Serial)", 18, 126);

  // 4. Instructions
  tft.setTextColor(COLOR_WHITE, COLOR_BG);
  tft.setTextSize(1);
  tft.drawString("Inside R (Bluetooth or USB Serial):", 8, 158);
  tft.setTextColor(COLOR_YELLOW, COLOR_BG);
  tft.drawString("cyd <- channel_cyd(port = 'COM8')", 8, 174);
  tft.drawString("# or: cyd <- channel_cyd_bluetooth('COM8')", 8, 190);

  tft.setTextColor(0x7BEF, COLOR_BG);
  tft.drawString("Awaiting incoming R job telemetry...", 8, 212);

  setRgbLed(0, 100, 255); // Blue/Cyan
}

void renderPayload(const JsonDocument& doc) {
  const char* title       = doc["title"] | "R Job";
  const char* status_text = doc["status_text"] | "RUNNING";
  const char* color_hex   = doc["status_color"] | "#00CCFF";
  int progress_pct        = doc["progress_pct"] | 0;
  const char* step_info   = doc["step_info"] | "";
  int inner_pct           = doc["inner_pct"] | 0;
  const char* inner_info  = doc["inner_info"] | "";
  const char* message     = doc["message"] | "";
  const char* elapsed     = doc["elapsed"] | "--:--:--";
  const char* eta         = doc["eta"] | "--:--:--";

  uint16_t status_color = parseHexColor(color_hex);

  // Update onboard RGB LED based on status text
  if (strcmp(status_text, "COMPLETE") == 0) {
    setRgbLed(0, 255, 0); // Green
  } else if (strcmp(status_text, "FAILED") == 0 || strcmp(status_text, "CRASHED") == 0) {
    setRgbLed(255, 0, 0); // Red
  } else {
    setRgbLed(0, 150, 255); // Cyan
  }

  // Clear display canvas
  tft.fillScreen(COLOR_BG);

  // 1. Top Header Banner
  tft.fillRect(0, 0, 320, 28, status_color);
  tft.setTextColor(COLOR_BG, status_color);
  tft.setTextSize(2);
  tft.drawString(status_text, 8, 6);

  tft.setTextSize(1);
  tft.setTextColor(COLOR_WHITE, status_color);
  tft.drawString("rNotify v0.1", 240, 10);

  // 2. Job Title
  tft.setTextSize(2);
  tft.setTextColor(COLOR_WHITE, COLOR_BG);
  tft.drawString(title, 8, 35);

  // 3. Message / Status Line
  tft.setTextSize(1);
  tft.setTextColor(COLOR_YELLOW, COLOR_BG);
  tft.drawString(message, 8, 60);

  // 4. Outer Progress Bar
  tft.setTextColor(COLOR_WHITE, COLOR_BG);
  char outer_str[64];
  snprintf(outer_str, sizeof(outer_str), "Outer: %s  (%d%%)", step_info, progress_pct);
  tft.drawString(outer_str, 8, 80);
  drawProgressBar(8, 95, 304, 16, progress_pct, status_color);

  // 5. Nested Inner Loop Progress Bar (if active)
  if (strlen(inner_info) > 0 || inner_pct > 0) {
    char inner_str[64];
    snprintf(inner_str, sizeof(inner_str), "Inner Subtask: %s  (%d%%)", inner_info, inner_pct);
    tft.drawString(inner_str, 8, 120);
    drawProgressBar(8, 135, 304, 12, inner_pct, COLOR_CYAN);
  }

  // 6. Timing Information Box
  tft.fillRect(8, 165, 304, 45, COLOR_CARD_BG);
  tft.drawRect(8, 165, 304, 45, COLOR_WHITE);
  tft.setTextColor(COLOR_WHITE, COLOR_CARD_BG);
  tft.setTextSize(1);

  char elapsed_buf[48];
  snprintf(elapsed_buf, sizeof(elapsed_buf), "Elapsed: %s", elapsed);
  tft.drawString(elapsed_buf, 16, 175);

  char eta_buf[48];
  snprintf(eta_buf, sizeof(eta_buf), "ETA: %s", eta);
  tft.drawString(eta_buf, 170, 175);

  // 7. Footer Status
  tft.setTextColor(0x7BEF, COLOR_BG);
  tft.drawString("Bluetooth: rNotify-CYD", 8, 222);
}

void processLine(const String& line) {
  StaticJsonDocument<1024> doc;
  DeserializationError error = deserializeJson(doc, line);
  if (error) {
    Serial.printf("[rNotify] JSON Parse Error: %s\n", error.c_str());
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
  Serial.println("\n[rNotify] Starting CYD Bluetooth & Serial Monitor...");

  initRgbLed();

  tft.init();
  tft.setRotation(1); // Landscape 320x240
  tft.fillScreen(COLOR_BG);

  // Initialize Bluetooth Serial
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
}

void loop() {
  // 1. Check for incoming Bluetooth data
  if (SerialBT.available()) {
    String line = SerialBT.readStringUntil('\n');
    line.trim();
    if (line.length() > 0) {
      Serial.println("[rNotify: BT Rx] " + line);
      processLine(line);
      SerialBT.println("{\"status\":\"ok\"}");
    }
  }

  // 2. Check for incoming USB Serial data
  if (Serial.available()) {
    String line = Serial.readStringUntil('\n');
    line.trim();
    if (line.length() > 0 && line.startsWith("{")) {
      Serial.println("[rNotify: Serial Rx] " + line);
      processLine(line);
      Serial.println("{\"status\":\"ok\"}");
    }
  }

#if ENABLE_WIFI
  server.handleClient();
#endif
}
