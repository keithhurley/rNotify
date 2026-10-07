/*
 * rNotify CYD (Cheap Yellow Display) ESP32 Firmware
 * Hardware: ESP32-2432S028R (2.8" 320x240 TFT LCD with ILI9341)
 *
 * Listens for JSON HTTP POST requests from rNotify at http://<CYD_IP>/api/notify
 * Renders job title, dual progress bars (outer & nested inner loop), status colors,
 * elapsed runtimes, and projected ETAs.
 *
 * Includes an interactive Wi-Fi Captive Portal (WiFiManager) for zero-hardcoding
 * setup. If Wi-Fi is unconfigured or unavailable, an "rNotify-CYD" AP is broadcast
 * with on-screen step-by-step connection instructions.
 *
 * Dependencies (install via Arduino Library Manager or arduino-cli):
 * - TFT_eSPI (configured for ESP32-2432S028R)
 * - ArduinoJson (v6 or v7)
 * - WiFiManager
 */

#include <WiFi.h>
#include <WebServer.h>
#include <WiFiManager.h>
#include <TFT_eSPI.h>
#include <ArduinoJson.h>

// --- Optional Hardcoded Wi-Fi Fallback ---
// If left as "YOUR_WIFI_SSID" or empty, WiFiManager will automatically connect
// using stored credentials or start an on-screen config portal "rNotify-CYD".
const char* WIFI_SSID     = "YOUR_WIFI_SSID";
const char* WIFI_PASSWORD = "YOUR_WIFI_PASSWORD";

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

WebServer server(80);
TFT_eSPI tft = TFT_eSPI();

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

void showConnectedScreen() {
  tft.fillScreen(COLOR_BG);

  // 1. Header Banner
  tft.fillRect(0, 0, 320, 28, COLOR_GREEN);
  tft.setTextColor(COLOR_BG, COLOR_GREEN);
  tft.setTextSize(2);
  tft.drawString("ONLINE / READY", 8, 6);

  tft.setTextSize(1);
  tft.setTextColor(COLOR_WHITE, COLOR_GREEN);
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
  tft.drawString("CYD IP ADDRESS (FOR R):", 18, 80);

  tft.setTextColor(COLOR_GREEN, COLOR_CARD_BG);
  tft.setTextSize(2);
  tft.drawString(WiFi.localIP().toString().c_str(), 18, 98);

  tft.setTextColor(0x7BEF, COLOR_CARD_BG);
  tft.setTextSize(1);
  tft.drawString(WiFi.SSID().c_str(), 18, 126);

  // 4. Instructions
  tft.setTextColor(COLOR_WHITE, COLOR_BG);
  tft.setTextSize(1);
  tft.drawString("Configure in R:", 8, 158);
  tft.setTextColor(COLOR_YELLOW, COLOR_BG);
  String r_cmd = "Sys.setenv(CYD_HOST = \"" + WiFi.localIP().toString() + "\")";
  tft.drawString(r_cmd.c_str(), 8, 174);

  tft.setTextColor(0x7BEF, COLOR_BG);
  tft.drawString("Awaiting notifications from R jobs...", 8, 208);

  setRgbLed(0, 150, 255); // Cyan LED
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
  tft.drawString(WiFi.localIP().toString().c_str(), 8, 222);

  server.send(200, "application/json", "{\"status\":\"ok\"}");
}

void handleRoot() {
  String html = "<!DOCTYPE html><html><head><title>rNotify CYD Monitor</title>";
  html += "<meta name='viewport' content='width=device-width, initial-scale=1'>";
  html += "<style>body{font-family:sans-serif;background:#121820;color:#fff;margin:2em;line-height:1.6}";
  html += ".card{background:#1e2632;border:1px solid #334155;border-radius:8px;padding:20px;max-width:500px}";
  html += "code{background:#0f172a;padding:3px 6px;border-radius:4px;color:#38bdf8}</style></head><body>";
  html += "<div class='card'>";
  html += "<h2>rNotify CYD Desk Monitor</h2>";
  html += "<p>Status: <b style='color:#4ade80'>ONLINE</b></p>";
  html += "<p>Device IP: <code>" + WiFi.localIP().toString() + "</code></p>";
  html += "<p>Connected SSID: <code>" + WiFi.SSID() + "</code></p>";
  html += "<h3>Using with R:</h3>";
  html += "<pre><code>library(rNotify)\n";
  html += "cyd &lt;- channel_cyd(host = \"" + WiFi.localIP().toString() + "\")\n";
  html += "job &lt;- notify_job(\"My Analysis\", channels = cyd)</code></pre>";
  html += "</div></body></html>";
  server.send(200, "text/html", html);
}

void handleStatus() {
  StaticJsonDocument<256> doc;
  doc["status"] = "online";
  doc["ip"] = WiFi.localIP().toString();
  doc["ssid"] = WiFi.SSID();
  doc["free_heap"] = ESP.getFreeHeap();
  doc["firmware"] = "rNotify-CYD v0.1";
  String resp;
  serializeJson(doc, resp);
  server.send(200, "application/json", resp);
}

void configModeCallback(WiFiManager *myWiFiManager) {
  tft.fillScreen(COLOR_BG);

  // Banner
  tft.fillRect(0, 0, 320, 28, COLOR_YELLOW);
  tft.setTextColor(COLOR_BG, COLOR_YELLOW);
  tft.setTextSize(2);
  tft.drawString("Wi-Fi Setup Required", 8, 6);

  tft.setTextColor(COLOR_WHITE, COLOR_BG);
  tft.setTextSize(1);
  tft.drawString("Connect to Wi-Fi AP to configure device:", 8, 38);

  tft.setTextColor(COLOR_CYAN, COLOR_BG);
  tft.setTextSize(2);
  tft.drawString("1. Connect to Wi-Fi:", 8, 60);

  tft.setTextColor(COLOR_WHITE, COLOR_BG);
  tft.setTextSize(2);
  tft.drawString(myWiFiManager->getConfigPortalSSID().c_str(), 20, 85);

  tft.setTextColor(COLOR_CYAN, COLOR_BG);
  tft.drawString("2. Open Browser At:", 8, 120);

  tft.setTextColor(COLOR_GREEN, COLOR_BG);
  tft.drawString("http://192.168.4.1", 20, 145);

  tft.setTextColor(COLOR_WHITE, COLOR_BG);
  tft.setTextSize(1);
  tft.drawString("3. Select your local Wi-Fi & enter password.", 8, 185);
  tft.drawString("Credentials will be saved to flash automatically.", 8, 205);

  setRgbLed(255, 180, 0); // Yellow/Amber LED
}

void setup() {
  Serial.begin(115200);
  delay(200);
  Serial.println("\n[rNotify] Starting CYD Monitor...");

  initRgbLed();

  tft.init();
  tft.setRotation(1); // Landscape 320x240
  tft.fillScreen(COLOR_BG);

  tft.setTextColor(COLOR_WHITE, COLOR_BG);
  tft.setTextSize(2);
  tft.drawString("rNotify Display", 20, 40);
  tft.setTextSize(1);
  tft.drawString("Connecting to Wi-Fi...", 20, 80);

  bool connected = false;

  // Try hardcoded credentials if provided
  if (strcmp(WIFI_SSID, "YOUR_WIFI_SSID") != 0 && strlen(WIFI_SSID) > 0) {
    Serial.printf("[rNotify] Attempting Wi-Fi connect to %s...\n", WIFI_SSID);
    WiFi.mode(WIFI_STA);
    WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
    int attempts = 0;
    while (WiFi.status() != WL_CONNECTED && attempts < 20) {
      delay(500);
      Serial.print(".");
      attempts++;
    }
    Serial.println();
    if (WiFi.status() == WL_CONNECTED) {
      connected = true;
    }
  }

  // Fallback to WiFiManager (auto-reconnect to saved NVS credentials or open captive portal)
  if (!connected) {
    WiFiManager wm;
    wm.setAPCallback(configModeCallback);
    wm.setConfigPortalTimeout(180); // 3 minutes timeout

    // Try auto-connecting to previously saved credentials, or launch AP portal
    if (!wm.autoConnect("rNotify-CYD")) {
      Serial.println("[rNotify] Failed to connect / config portal timed out.");
      tft.fillScreen(COLOR_BG);
      tft.setTextColor(COLOR_RED, COLOR_BG);
      tft.setTextSize(2);
      tft.drawString("Wi-Fi Connection Failed", 10, 40);
      tft.setTextSize(1);
      tft.setTextColor(COLOR_WHITE, COLOR_BG);
      tft.drawString("Rebooting in 5 seconds to retry...", 10, 80);
      delay(5000);
      ESP.restart();
    }
  }

  // Connected! Show status on screen
  Serial.println("[rNotify] Wi-Fi Connected!");
  Serial.print("[rNotify] IP Address: ");
  Serial.println(WiFi.localIP());

  showConnectedScreen();

  // Set up Web Server routes
  server.on("/", HTTP_GET, handleRoot);
  server.on("/api/notify", HTTP_GET, handleStatus);
  server.on("/api/notify", HTTP_POST, handleNotify);
  server.on("/api/status", HTTP_GET, handleStatus);

  server.begin();
  Serial.println("[rNotify] HTTP Server running on port 80.");
}

void loop() {
  server.handleClient();
}
