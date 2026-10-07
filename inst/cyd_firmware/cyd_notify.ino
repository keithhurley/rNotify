/*
 * rNotify CYD (Cheap Yellow Display) ESP32 Firmware
 * Hardware: ESP32-2432S028R (2.8" 320x240 TFT LCD with ILI9341)
 *
 * Listens for JSON HTTP POST requests from rNotify at http://<CYD_IP>/api/notify
 * Renders job title, dual progress bars (outer & nested inner loop), status colors,
 * elapsed runtimes, and projected ETAs.
 *
 * Dependencies (install via Arduino Library Manager):
 * - TFT_eSPI (Configure User_Setup.h for ESP32-2432S028R)
 * - ArduinoJson (v6 or v7)
 */

#include <WiFi.h>
#include <WebServer.h>
#include <TFT_eSPI.h>
#include <ArduinoJson.h>

// --- WiFi Configuration ---
const char* WIFI_SSID     = "YOUR_WIFI_SSID";
const char* WIFI_PASSWORD = "YOUR_WIFI_PASSWORD";

WebServer server(80);
TFT_eSPI tft = TFT_eSPI();

// Status Colors (16-bit 565 RGB)
#define COLOR_BG        0x0000 // Black
#define COLOR_CARD_BG   0x18E3 // Dark Gray / Slate
#define COLOR_WHITE     0xFFFF
#define COLOR_CYAN      0x067F // Running / Start
#define COLOR_GREEN     0x07E0 // Success / Complete
#define COLOR_YELLOW    0xFDE0 // Warning
#define COLOR_RED       0xF800 // Failed / Crashed
#define COLOR_BAR_BG    0x39E7 // Gray bar track

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

void handleNotify() {
  if (server.method() != HTTP_POST) {
    server.send(405, "text/plain", "Method Not Allowed");
    return;
  }

  String body = server.arg("plain");
  StaticJsonDocument<1024> doc;
  DeserializationError error = deserializeJson(doc, body);

  if (error) {
    server.send(400, "text/plain", "Invalid JSON");
    return;
  }

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

  // Clear display canvas
  tft.fillScreen(COLOR_BG);

  // 1. Top Header Banner
  tft.fillRect(0, 0, 320, 28, status_color);
  tft.setTextColor(COLOR_BG, status_color);
  tft.setTextSize(2);
  tft.drawString(status_text, 8, 6);

  tft.setTextSize(1);
  tft.setTextColor(COLOR_WHITE, COLOR_BG);
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
  tft.drawString(WiFi.localIP().toString().c_str(), 8, 222);

  server.send(200, "application/json", "{\"status\":\"ok\"}");
}

void setup() {
  Serial.begin(115200);

  tft.init();
  tft.setRotation(1); // Landscape 320x240
  tft.fillScreen(COLOR_BG);

  tft.setTextColor(COLOR_WHITE, COLOR_BG);
  tft.setTextSize(2);
  tft.drawString("rNotify Display", 20, 40);
  tft.setTextSize(1);
  tft.drawString("Connecting to WiFi...", 20, 80);

  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }

  tft.fillScreen(COLOR_BG);
  tft.setTextColor(COLOR_GREEN, COLOR_BG);
  tft.setTextSize(2);
  tft.drawString("Connected!", 20, 30);
  tft.setTextSize(1);
  tft.drawString("IP Address:", 20, 70);
  tft.setTextColor(COLOR_CYAN, COLOR_BG);
  tft.setTextSize(2);
  tft.drawString(WiFi.localIP().toString().c_str(), 20, 95);

  server.on("/api/notify", handleNotify);
  server.begin();
  Serial.println("rNotify CYD Server Ready at: " + WiFi.localIP().toString());
}

void loop() {
  server.handleClient();
}
