#include <LittleFS.h>
#include <HardwareSerial.h>
#include <WiFi.h>
#include <AsyncTCP.h>
#include <ZipArchive.h>
#include <M5StickCPlus2.h>

// GPIO26 (TX), GPIO36 (RX) - Note: GPIO36 is input-only!
HardwareSerial SerialFPGA(1); 
const char* ssid = "test00";
const char* password = "PASSWORD";

void setup() {
  Serial.begin(115200);
  while(!Serial);  // Wait for serial
  SerialFPGA.begin(115200, SERIAL_8N1, 36, 26);  // RX=36, TX=26
  // Wait for FPGA to initialize
  delay(1000); 
  M5.begin();
  M5.Lcd.setRotation(3); // Landscape orientation
  
  Serial.begin(115200);
  SerialFPGA.begin(115200, SERIAL_8N1, 36, 26);

  if (!LittleFS.begin()) {
    M5.Lcd.setTextColor(RED);
    M5.Lcd.println("FS Mount Fail!");
    while(1);
  }

  // Show initial screen
  M5.Lcd.fillScreen(BLACK);
  M5.Lcd.setTextSize(2);
  M5.Lcd.setCursor(10, 10);
  M5.Lcd.println("Ultima Loader");
  delay(1000);
  // Initialize filesystem
  if (!LittleFS.begin(true)) {  // Format if needed
    Serial.println("LittleFS Mount Failed");
    return;
  }
  LittleFS.format();  // WARNING: Erases everything!
  // Connect to WiFi
  WiFi.begin(ssid, password);
  Serial.print("Connecting to WIFI");
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println("\nConnected! IP: " + WiFi.localIP().toString());
  Serial.println("READY"); // Tell FPGA we're ready
}

void loop() {
  // SerialFPGA.println("HELLO");  // Send test pattern
  // delay(1000);  // Repeat every second
  if (Serial.available()) {
    String cmd = Serial.readStringUntil('\n');
    cmd.trim();
    
    if (cmd == "FETCH_ROM") {
      downloadROM();
      verifyDownload();
    }
    else if (cmd == "LIST_FILES") {
      listFiles();
    }
    else if (cmd == "SEND") {
      sendROMtoFPGA();
    }
  }

  // Forward USB commands to FPGA
  if (Serial.available()) {
    SerialFPGA.write(Serial.read());
  }
  
  // Forward FPGA responses to USB
  if (SerialFPGA.available()) {
    Serial.write(SerialFPGA.read());
  }
}

// Download ROM and save to LittleFS
void downloadROM() {
  WiFiClient client;
  const char* host = "mirrors.apple2.org.za";
  const char* path = "/ftp.apple.asimov.net/images/games/rpg/ultima/ultima_I/ultima_1.dsk";
  
  Serial.print("Connecting to ");
  Serial.println(host);

  if (!client.connect(host, 80)) {
    Serial.println("Connection failed!");
    return;
  }

  // Send HTTP request
  client.print(String("GET ") + path + " HTTP/1.1\r\n");
  client.print(String("Host: ") + host + "\r\n");
  client.print("Connection: close\r\n\r\n");

  // Wait for response (timeout after 10 seconds)
  unsigned long startTime = millis();
  while (!client.available() && millis() - startTime < 10000) {
    delay(10);
  }

  // Check HTTP response
  String response = client.readStringUntil('\n');
  if (response.indexOf("200 OK") == -1) {
    Serial.print("HTTP Error: ");
    Serial.println(response);
    client.stop();
    return;
  }

  // Skip HTTP headers (until empty line)
  while (client.connected()) {
    String line = client.readStringUntil('\n');
    if (line == "\r") break; // Headers end
  }

  // Save to LittleFS
  File file = LittleFS.open("/ultima1.dsk", "w");
  if (!file) {
    Serial.println("Failed to create file!");
    client.stop();
    return;
  }

  // Download with progress
  size_t totalBytes = 0;
  uint8_t buffer[512]; // 512-byte chunks (common disk sector size)
  
  Serial.println("Downloading...");
  while (client.connected() || client.available()) {
    size_t bytesRead = client.read(buffer, sizeof(buffer));
    if (bytesRead > 0) {
      file.write(buffer, bytesRead);
      totalBytes += bytesRead;
      
      // Print progress every 16KB
      if (totalBytes % 16384 == 0) {
        Serial.printf("Downloaded: %d bytes\n", totalBytes);
      }
    }
    delay(1); // Prevent watchdog triggers
  }
  
  file.close();
  client.stop();
  Serial.printf("Download complete! Saved %d bytes to /ultima1.dsk\n", totalBytes);
}

void verifyDownload() {
  File file = LittleFS.open("/ultima1.dsk", "r");
  if (!file) {
    Serial.println("ERROR: File not found!");
    return;
  }
  Serial.printf("File size: %d bytes\n", file.size());
  
  // Print first 16 bytes (header)
  uint8_t header[16];
  file.read(header, sizeof(header));
  for (int i = 0; i < sizeof(header); i++) {
    Serial.printf("%02X ", header[i]);
  }
  Serial.println("\nFile appears valid");
  file.close();
}

// List all saved files
void listFiles() {
  File root = LittleFS.open("/");
  while (File file = root.openNextFile()) {
    Serial.printf("File: %s Size: %d\n", file.name(), file.size());
  }
}

void sendROMtoFPGA() {
  // Setup screen
  M5.Lcd.fillScreen(BLACK);
  M5.Lcd.setTextSize(1);
  M5.Lcd.setTextColor(WHITE);
  
  // Header
  M5.Lcd.drawCentreString("FPGA TRANSFER", 115, 5, 2);
  M5.Lcd.drawFastHLine(0, 30, 240, BLUE);

  File file = LittleFS.open("/ultima1.dsk", "r");
  if (!file) {
    displayError("File not found!");
    return;
  }

  // File info
  uint32_t fileSize = file.size();
  M5.Lcd.setCursor(5, 35);
  M5.Lcd.printf("File: ultima1.dsk");
  M5.Lcd.setCursor(5, 50);
  M5.Lcd.printf("Size: %d KB", fileSize/1024);

  // Progress bar background
  M5.Lcd.drawRoundRect(50, 70, 140, 20, 5, WHITE);

  uint8_t buffer[256];
  uint32_t totalSent = 0;
  unsigned long startTime = millis();

  while (file.available()) {
    size_t bytesRead = file.read(buffer, sizeof(buffer));
    SerialFPGA.write(buffer, bytesRead);
    totalSent += bytesRead;

    // Update progress (every 1% or 512 bytes)
    static uint8_t lastPercent = 0;
    uint8_t currentPercent = (totalSent * 100) / fileSize;
    
    if (currentPercent != lastPercent || bytesRead == sizeof(buffer)) {
      lastPercent = currentPercent;
      
      // Progress bar
      M5.Lcd.fillRoundRect(50, 72, (currentPercent * 136)/100, 16, 3, GREEN);
      
      // Text info
      M5.Lcd.fillRect(5, 95, 150, 40, BLACK); // Clear previous text
      M5.Lcd.setCursor(5, 95);
      M5.Lcd.printf("Sent: %d/%d KB", totalSent/1024, fileSize/1024);
      M5.Lcd.setCursor(5, 110);
      M5.Lcd.printf("%d%% @ %d KB/s", 
                   currentPercent,
                   (totalSent/1024) / ((millis()-startTime)/1000 + 1)); // +1 to avoid div/0
    }
    
    delay(1); // Small delay for stability
  }

  // Completion
  M5.Lcd.fillRect(5, 130, 150, 20, BLACK);
  M5.Lcd.setTextColor(GREEN);
  M5.Lcd.drawCentreString("TRANSFER COMPLETE!", 105, 120, 2);

  delay(200);

  file.close();
}

void displayError(const char* msg) {
  M5.Lcd.fillScreen(BLACK);
  M5.Lcd.setTextColor(RED);
  M5.Lcd.setTextSize(1);
  M5.Lcd.drawCentreString("ERROR", 80, 40, 2);
  M5.Lcd.drawCentreString(msg, 80, 70, 1);

  delay(1000);
}
