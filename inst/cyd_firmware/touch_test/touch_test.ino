/*
 * CYD Touchscreen Diagnostic & Hardware Identification Tool
 * Features interactive corner calibration to get 100% pixel-perfect coordinates.
 * Designed for ESP32-3248S035 (3.5" ST7796 with XPT2046 Resistive Touch)
 */

#include <TFT_eSPI.h>

#define TOUCH_IRQ 36

TFT_eSPI tft = TFT_eSPI();

int touch_count = 0;
uint16_t screen_w = 480;
uint16_t screen_h = 320;
uint16_t calData[5];

void draw_main_ui() {
  tft.fillScreen(TFT_BLACK);

  // Draw UI Header
  tft.fillRect(0, 0, screen_w, 32, TFT_NAVY);
  tft.setTextColor(TFT_WHITE, TFT_NAVY);
  tft.setTextSize(2);
  tft.drawString("CYD TOUCH DIAGNOSTIC", 10, 8);

  // Reset Button Target in Top-Right Corner
  tft.fillRoundRect(screen_w - 95, 4, 90, 24, 4, TFT_DARKGREY);
  tft.drawRoundRect(screen_w - 95, 4, 90, 24, 4, TFT_RED);
  tft.setTextColor(TFT_WHITE, TFT_DARKGREY);
  tft.setTextSize(1);
  tft.drawString("RST TEST", screen_w - 78, 10);

  // Subheader with calibration values
  tft.setTextSize(1);
  tft.setTextColor(TFT_CYAN, TFT_BLACK);
  char sub[100];
  snprintf(sub, sizeof(sub), "Cal: {%d, %d, %d, %d, %d} | Tap screen to draw",
           calData[0], calData[1], calData[2], calData[3], calData[4]);
  tft.drawString(sub, 10, 38);

  // Draw Corner Reference Targets
  tft.drawCircle(30, 80, 16, TFT_YELLOW);
  tft.drawString("TL", 24, 75);

  tft.drawCircle(screen_w - 30, 80, 16, TFT_RED);
  tft.drawString("TR", screen_w - 36, 75);

  tft.drawCircle(30, screen_h - 40, 16, TFT_GREEN);
  tft.drawString("BL", 24, screen_h - 45);

  tft.drawCircle(screen_w - 30, screen_h - 40, 16, TFT_BLUE);
  tft.drawString("BR", screen_w - 36, screen_h - 45);

  // Drawing Canvas Border
  tft.drawRect(5, 52, screen_w - 10, screen_h - 75, TFT_DARKGREY);
}

void setup() {
  Serial.begin(115200);
  delay(300);
  Serial.println("\n===========================================");
  Serial.println("  CYD Touch Diagnostic & Calibration");
  Serial.println("===========================================");

  // Backlight ON (GPIO 27 on 3.5" board, GPIO 21 on 2.8" board)
  pinMode(27, OUTPUT); digitalWrite(27, HIGH);
  pinMode(21, OUTPUT); digitalWrite(21, HIGH);

  // Deselect SD Card CS (GPIO 5)
  pinMode(5, OUTPUT); digitalWrite(5, HIGH);

  // IRQ Pin (GPIO 36)
  pinMode(TOUCH_IRQ, INPUT);

  // Initialize TFT Display & Touch
  tft.init();
  tft.setRotation(1); // Landscape
  screen_w = tft.width();
  screen_h = tft.height();
  tft.fillScreen(TFT_BLACK);

  // --- Run Interactive Calibration ---
  tft.setTextColor(TFT_WHITE, TFT_BLACK);
  tft.setTextSize(2);
  tft.drawCentreString("TOUCH SCREEN CALIBRATION", screen_w / 2, screen_h / 2 - 30, 1);
  tft.setTextSize(1);
  tft.setTextColor(TFT_YELLOW, TFT_BLACK);
  tft.drawCentreString("Touch each corner target as it appears...", screen_w / 2, screen_h / 2 + 10, 1);
  delay(1200);

  // calibrateTouch will cycle through 4 corners
  tft.calibrateTouch(calData, TFT_MAGENTA, TFT_BLACK, 18);

  Serial.println("\n--- CALIBRATION RESULTS ---");
  Serial.printf("uint16_t calData[5] = { %d, %d, %d, %d, %d };\n",
                calData[0], calData[1], calData[2], calData[3], calData[4]);
  Serial.println("---------------------------\n");

  tft.setTouch(calData);

  // Draw Main Test Screen
  draw_main_ui();
}

void loop() {
  int irq_val = digitalRead(TOUCH_IRQ);
  bool hw_pressed = (irq_val == LOW);

  uint16_t tx = 0, ty = 0;
  bool is_touched = tft.getTouch(&tx, &ty, 400);

  // Periodic Telemetry Update (every 60ms)
  static unsigned long last_ui = 0;
  if (millis() - last_ui > 60) {
    last_ui = millis();

    tft.fillRect(6, screen_h - 18, screen_w - 12, 16, TFT_BLACK);
    tft.setTextSize(1);
    tft.setTextColor(hw_pressed ? TFT_GREEN : TFT_YELLOW, TFT_BLACK);

    char buf[100];
    snprintf(buf, sizeof(buf), "Hits:%d | IRQ36:%d | Pos:(%d, %d) | Screen: %dx%d",
             touch_count, irq_val, tx, ty, screen_w, screen_h);
    tft.drawString(buf, 8, screen_h - 16);
  }

  if (is_touched) {
    touch_count++;

    // Draw touch dot on canvas (magenta dot with cyan border)
    tft.fillCircle(tx, ty, 3, TFT_CYAN);
    tft.drawPixel(tx, ty, TFT_WHITE);

    // Check if hitting top-right reset button
    if (tx >= (screen_w - 105) && ty <= 45) {
      tft.fillRoundRect(screen_w - 95, 4, 90, 24, 4, TFT_GREEN);
      tft.setTextColor(TFT_BLACK, TFT_GREEN);
      tft.setTextSize(1);
      tft.drawString("HIT RST!", screen_w - 78, 10);
    } else {
      tft.fillRoundRect(screen_w - 95, 4, 90, 24, 4, TFT_DARKGREY);
      tft.drawRoundRect(screen_w - 95, 4, 90, 24, 4, TFT_RED);
      tft.setTextColor(TFT_WHITE, TFT_DARKGREY);
      tft.setTextSize(1);
      tft.drawString("RST TEST", screen_w - 78, 10);
    }

    Serial.printf("[TOUCH HIT #%d] Screen:(%d, %d)\n", touch_count, tx, ty);
    delay(15);
  }
}
