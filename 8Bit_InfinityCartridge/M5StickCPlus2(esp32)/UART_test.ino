#include <LittleFS.h>
#include <HardwareSerial.h>
#include <WiFi.h>
#include <AsyncTCP.h>
#include <ZipArchive.h>
#include <M5StickCPlus2.h>

HardwareSerial SerialFPGA(1); 

void setup() {
  Serial.begin(115200);
  while(!Serial);  // Wait for serial
  SerialFPGA.begin(115200, SERIAL_8N1, 36, 26);  // RX=36, TX=26
  
  M5.begin();
  M5.Lcd.setRotation(3); // Landscape orientation
  M5.Lcd.fillScreen(BLACK);
  M5.Lcd.setTextSize(2);
  M5.Lcd.setCursor(10, 10);
  M5.Lcd.println("FPGA UART Test");
  M5.Lcd.setTextSize(1);
  M5.Lcd.setCursor(10, 40);
  M5.Lcd.println("Press FPGA button to transmit");
}

void loop() {
  // Listen for FPGA transmission (triggered by FPGA button)
  if (SerialFPGA.available()) {
    String receivedData = "";
    
    // Read all available bytes
    while (SerialFPGA.available()) {
      char c = SerialFPGA.read();
      receivedData += c;
      delay(2); // Small delay between bytes (adjust based on baud rate)
    }

    // Display on Serial Monitor
    Serial.print("FPGA Sent: ");
    Serial.println(receivedData);

    // Display on M5Stack screen
    M5.Lcd.fillRect(0, 60, 240, 100, BLACK);
    M5.Lcd.setCursor(10, 60);
    M5.Lcd.printf("Received %d bytes:", receivedData.length());
    M5.Lcd.setCursor(10, 80);
    M5.Lcd.println(receivedData);
  }

  // Small delay to prevent CPU overload
  delay(10);
}
