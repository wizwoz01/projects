#include <M5StickCPlus2.h>
#include <WiFi.h>

// ---------- config ----------
const char* SSID = "sp1-test";
const char* PASS = "sp1-pass";
const uint16_t PORT = 3333;
// ----------------------------

WiFiServer server(PORT);
WiFiClient client;

// Display and menu variables
int currentMenu = 0;
int messageScroll = 0;
int totalMessages = 0;
bool clientWasConnected = false;

// Message buffer
#define MAX_MESSAGES 50
#define MAX_MESSAGE_LEN 20
struct Message {
  char content[MAX_MESSAGE_LEN];
  int length;
  bool isText;
  unsigned long timestamp;
};
Message messageBuffer[MAX_MESSAGES];
int messageIndex = 0;

// Input buffer for accumulating incoming data
#define INPUT_BUFFER_SIZE 256
char inputBuffer[INPUT_BUFFER_SIZE];
int inputBufferLen = 0;

// Menu items
enum MenuItems {
  MENU_STATUS = 0,
  MENU_MESSAGES = 1,
  MENU_STATS = 2,
  MENU_COUNT = 3
};

const char* menuNames[] = {"Status", "Messages", "Stats"};

void setup() {
  Serial.begin(115200);
  delay(200);
  
  // Initialize M5StickCPlus2
  M5.begin();
  M5.Lcd.setRotation(1);
  M5.Lcd.fillScreen(BLACK);
  M5.Lcd.setTextColor(WHITE, BLACK);
  M5.Lcd.setTextSize(1);
  
  // Welcome screen
  M5.Lcd.setCursor(0, 0);
  M5.Lcd.println("M5 WiFi Echo Server");
  M5.Lcd.println("Starting...");
  delay(1000);

  // Start SoftAP
  if (!WiFi.softAP(SSID, PASS)) {
    Serial.println("SoftAP start failed");
    while (1) delay(1000);
  }
  IPAddress ip = WiFi.softAPIP();
  Serial.print("SoftAP up. SSID="); Serial.print(SSID);
  Serial.print(" PASS="); Serial.print(PASS);
  Serial.print(" IP="); Serial.println(ip);   // 192.168.4.1

  // Start TCP server
  server.begin();
  Serial.printf("TCP echo server listening on %u\n", PORT);
  
  // Update display
  M5.Lcd.fillScreen(BLACK);
  updateDisplay();
}

void addCompleteMessage(const char* data, int len, bool isText) {
  Message& msg = messageBuffer[messageIndex];
  msg.length = min(len, MAX_MESSAGE_LEN - 1);
  memcpy(msg.content, data, msg.length);
  msg.content[msg.length] = '\0';
  msg.isText = isText;
  msg.timestamp = millis();
  
  messageIndex = (messageIndex + 1) % MAX_MESSAGES;
  if (totalMessages < MAX_MESSAGES) totalMessages++;
  
  // Auto-scroll to latest message when viewing messages
  if (currentMenu == MENU_MESSAGES) {
    messageScroll = max(0, totalMessages - 6);
  }
}

void processIncomingData(const uint8_t* data, int len) {
  for (int i = 0; i < len; i++) {
    char c = (char)data[i];
    
    // Add character to input buffer
    if (inputBufferLen < INPUT_BUFFER_SIZE - 1) {
      inputBuffer[inputBufferLen++] = c;
    }
    
    // Check for message delimiters (newline, carriage return, or buffer full)
    if (c == '\n' || c == '\r' || inputBufferLen >= INPUT_BUFFER_SIZE - 1) {
      if (inputBufferLen > 0) {
        // Remove trailing newline/carriage return for display
        while (inputBufferLen > 0 && (inputBuffer[inputBufferLen - 1] == '\n' || inputBuffer[inputBufferLen - 1] == '\r')) {
          inputBufferLen--;
        }
        
        if (inputBufferLen > 0) {
          inputBuffer[inputBufferLen] = '\0';
          bool isText = isTextData((uint8_t*)inputBuffer, inputBufferLen);
          addCompleteMessage(inputBuffer, inputBufferLen, isText);
          
          // Log complete message to serial
          if (isText) {
            Serial.printf("Received message #%d: %s\n", totalMessages, inputBuffer);
          } else {
            Serial.printf("Received binary message #%d (%d bytes): ", totalMessages, inputBufferLen);
            for (int j = 0; j < min(inputBufferLen, 16); j++) {
              Serial.printf("%02X ", (uint8_t)inputBuffer[j]);
            }
            if (inputBufferLen > 16) Serial.print("...");
            Serial.println();
          }
        }
        
        // Reset buffer for next message
        inputBufferLen = 0;
      }
    }
  }
}

bool isTextData(const uint8_t* data, int len) {
  // Simple heuristic: check if all bytes are printable ASCII or common whitespace
  for (int i = 0; i < len; i++) {
    uint8_t c = data[i];
    if (c < 32 && c != '\n' && c != '\r' && c != '\t') {
      return false;
    }
    if (c > 126) return false;
  }
  return true;
}

void updateDisplay() {
  M5.Lcd.fillScreen(BLACK);
  M5.Lcd.setCursor(0, 0);
  M5.Lcd.setTextSize(1);
  
  // Menu header
  M5.Lcd.setTextColor(YELLOW, BLACK);
  M5.Lcd.printf("< %s >\n", menuNames[currentMenu]);
  M5.Lcd.setTextColor(WHITE, BLACK);
  
  switch (currentMenu) {
    case MENU_STATUS:
      displayStatus();
      break;
    case MENU_MESSAGES:
      displayMessages();
      break;
    case MENU_STATS:
      displayStats();
      break;
  }
  
  // Button help
  M5.Lcd.setCursor(0, 125);
  M5.Lcd.setTextColor(CYAN, BLACK);
  M5.Lcd.setTextSize(1);
  M5.Lcd.print("A:Menu B:Scroll Hold-B:Clear");
}

void displayStatus() {
  M5.Lcd.printf("SSID: %s\n", SSID);
  M5.Lcd.printf("Pass: %s\n", PASS);
  M5.Lcd.printf("IP: %s\n", WiFi.softAPIP().toString().c_str());
  M5.Lcd.printf("Port: %d\n\n", PORT);
  
  M5.Lcd.printf("Connected: %d\n", WiFi.softAPgetStationNum());
  
  if (client && client.connected()) {
    M5.Lcd.setTextColor(GREEN, BLACK);
    M5.Lcd.println("Client: ACTIVE");
    M5.Lcd.setTextColor(WHITE, BLACK);
  } else {
    M5.Lcd.setTextColor(RED, BLACK);
    M5.Lcd.println("Client: NONE");
    M5.Lcd.setTextColor(WHITE, BLACK);
  }
  
  M5.Lcd.printf("\nUptime: %lu s", millis() / 1000);
}

void displayMessages() {
  if (totalMessages == 0) {
    M5.Lcd.println("No messages yet...");
    return;
  }
  
  M5.Lcd.printf("Messages (%d/%d)\n", totalMessages, MAX_MESSAGES);
  M5.Lcd.printf("Scroll: %d\n\n", messageScroll);
  
  // Display up to 6 messages
  for (int i = 0; i < 6 && (messageScroll + i) < totalMessages; i++) {
    int msgIdx = (messageIndex - totalMessages + messageScroll + i + MAX_MESSAGES) % MAX_MESSAGES;
    const Message& msg = messageBuffer[msgIdx];
    
    M5.Lcd.setTextColor(msg.isText ? WHITE : YELLOW, BLACK);
    M5.Lcd.printf("%d:", messageScroll + i + 1);
    
    if (msg.isText) {
      // Display text (max 20 chars fits perfectly on screen)
      M5.Lcd.printf("%.20s", msg.content);
      if (msg.length > 20) M5.Lcd.print("...");
    } else {
      // Display hex bytes
      M5.Lcd.print("HEX:");
      for (int j = 0; j < min(msg.length, 8); j++) {
        M5.Lcd.printf("%02X ", (uint8_t)msg.content[j]);
      }
      if (msg.length > 8) M5.Lcd.print("...");
    }
    M5.Lcd.println();
  }
}

void displayStats() {
  M5.Lcd.printf("Total Messages: %d\n", totalMessages);
  M5.Lcd.printf("Buffer Usage: %d%%\n", (totalMessages * 100) / MAX_MESSAGES);
  M5.Lcd.printf("Free RAM: %d bytes\n\n", ESP.getFreeHeap());
  
  M5.Lcd.printf("WiFi Stations: %d\n", WiFi.softAPgetStationNum());
  M5.Lcd.printf("TCP Port: %d\n\n", PORT);
  
  if (totalMessages > 0) {
    // Count text vs binary messages
    int textCount = 0;
    for (int i = 0; i < totalMessages; i++) {
      int msgIdx = (messageIndex - totalMessages + i + MAX_MESSAGES) % MAX_MESSAGES;
      if (messageBuffer[msgIdx].isText) textCount++;
    }
    M5.Lcd.printf("Text: %d, Binary: %d\n", textCount, totalMessages - textCount);
  }
}

void handleButtons() {
  M5.update();
  
  if (M5.BtnA.wasPressed()) {
    // Cycle through menus
    currentMenu = (currentMenu + 1) % MENU_COUNT;
    messageScroll = 0; // Reset scroll when changing menu
    updateDisplay();
  }
  
  if (M5.BtnB.wasPressed()) {
    // Scroll messages or other scrollable content
    if (currentMenu == MENU_MESSAGES && totalMessages > 6) {
      messageScroll++;
      if (messageScroll > totalMessages - 6) {
        messageScroll = 0;
      }
      updateDisplay();
    }
  }
  
  // Long press Button B for clearing messages
  if (M5.BtnB.pressedFor(1000)) {
    // Clear messages (works from any menu)
    if (totalMessages > 0) {
      totalMessages = 0;
      messageIndex = 0;
      messageScroll = 0;
      inputBufferLen = 0; // Also clear the input buffer
      
      // Show confirmation message
      M5.Lcd.fillScreen(BLACK);
      M5.Lcd.setCursor(0, 50);
      M5.Lcd.setTextColor(GREEN, BLACK);
      M5.Lcd.setTextSize(2);
      M5.Lcd.println("CLEARED!");
      M5.Lcd.setTextColor(WHITE, BLACK);
      M5.Lcd.setTextSize(1);
      delay(1000);
      
      updateDisplay();
    } else {
      // Show "no messages" feedback
      M5.Lcd.fillScreen(BLACK);
      M5.Lcd.setCursor(0, 50);
      M5.Lcd.setTextColor(YELLOW, BLACK);
      M5.Lcd.setTextSize(1);
      M5.Lcd.println("No messages to clear");
      delay(1000);
      updateDisplay();
    }
  }
}

void loop() {
  // Handle button presses
  handleButtons();
  
  // Accept a new client if needed
  if (!client || !client.connected()) {
    WiFiClient newClient = server.available();
    if (newClient) {
      client = newClient;
      Serial.println("Client connected");
      clientWasConnected = true;
      if (currentMenu == MENU_STATUS) updateDisplay();
    }
  }

  // Echo any received bytes and store messages
  if (client && client.connected() && client.available()) {
    uint8_t buf[256];
    int n = client.read(buf, sizeof(buf));
    if (n > 0) {
      // Echo back the data
      client.write(buf, n);
      
      // Process incoming data to form complete messages
      processIncomingData(buf, n);
      
      // Update display if showing messages
      if (currentMenu == MENU_MESSAGES) {
        updateDisplay();
      }
    }
  }

  // Clean up disconnected client
  if (client && !client.connected() && clientWasConnected) {
    Serial.println("Client disconnected");
    client.stop();
    clientWasConnected = false;
    if (currentMenu == MENU_STATUS) updateDisplay();
  }
  
  // Small delay to prevent excessive CPU usage
  delay(10);
}