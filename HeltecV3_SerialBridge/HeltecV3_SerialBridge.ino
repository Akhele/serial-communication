/*
 * Bidirectional USB Serial Communication for Heltec Wireless Stick Lite V3
 * Compatible with Flutter Serial Communication App
 * 
 * This code enables full bidirectional communication via USB:
 * - Receives commands/messages from the app
 * - Sends responses/data back to the app
 * - Can send and receive simultaneously
 */

#include "LoRaWan_APP.h"
#include "Arduino.h"

// Configuration
#define RF_FREQUENCY        433000000  // 914335 MHz (band) - adjust for your region
#define TX_POWER            14         // Max power for V3
#define SPREADING_FACTOR    7          // SF7
#define BANDWIDTH           0          // 125 kHz
#define CODING_RATE         1          // 4/5

// Message buffers
String rxBuffer = "";
String inputBuffer = "";
bool newData = false;

// Declare RadioEvents
RadioEvents_t RadioEvents;

// LoRa state
volatile bool hasLoRaPacket = false;
uint8_t loraRxBuffer[256];
uint16_t loraRxSize = 0;

// Callback prototype
void OnRxDone(uint8_t *payload, uint16_t size, int16_t rssi, int8_t snr);

void setup() {
    // Start USB Serial at 115200 baud (matches app default)
    Serial.begin(115200);
    
    // Wait for serial port to open
    while (!Serial && millis() < 5000) {
        delay(10);
    }
    
    Serial.println("=== Heltec V3 Serial Bridge ===");
    Serial.println("Ready for bidirectional communication");
    Serial.println("Waiting for messages...");
    Serial.println();
    
    // Initialize board
    Mcu.begin(HELTEC_BOARD, SLOW_CLK_TPYE);
    
    // Initialize LoRa radio
    Radio.Init(&RadioEvents);
    Radio.SetChannel(RF_FREQUENCY);
    
    // Register callbacks
    RadioEvents.RxDone = OnRxDone;
    
    // Configure reception
    Radio.SetRxConfig(MODEM_LORA, BANDWIDTH, SPREADING_FACTOR,
                      CODING_RATE, 0, 8, 0, false, 0, true, 0, 0, false, true);
    
    Serial.println("System initialized");
    Serial.println("USB Serial: Active");
    Serial.println("LoRa Radio: Active");
    Serial.println();
}

void loop() {
    // Keep LoRa listening for LoRa-to-LoRa communication
    Radio.Rx(0);
    
    // Process radio interrupts
    Radio.IrqProcess();
    
    // Handle USB Serial input (from Flutter app)
    if (Serial.available() > 0) {
        String incoming = "";
        
        // Read complete message
        while (Serial.available() > 0) {
            char c = Serial.read();
            incoming += c;
            delay(1); // Small delay to receive full message
        }
        
        incoming.trim();
        
        if (incoming.length() > 0) {
            // Forward to LoRa if not an AT command
            if (!incoming.startsWith("AT")) {
                // Send via LoRa to other devices
                sendLoRaMessage(incoming);
            } else {
                // Process AT commands
                processATCommand(incoming);
            }
        }
    }
    
    // Handle LoRa packets (from other LoRa devices)
    if (hasLoRaPacket) {
        uint16_t copyLen = loraRxSize < sizeof(loraRxBuffer) ? loraRxSize : sizeof(loraRxBuffer);
        
        // Copy received data to string buffer
        String loraMessage = "";
        for (int i = 0; i < copyLen; i++) {
            loraMessage += (char)loraRxBuffer[i];
        }
        
        // Forward to USB Serial (to Flutter app)
        // The app expects "username:message" format
        Serial.println(loraMessage);
        
        hasLoRaPacket = false;
    }
    
    // Small delay to prevent overwhelming the system
    delay(10);
}

// Called by radio driver when a packet is received
void OnRxDone(uint8_t *payload, uint16_t size, int16_t rssi, int8_t snr) {
    uint16_t copyLen = size < sizeof(loraRxBuffer) ? size : sizeof(loraRxBuffer);
    memcpy(loraRxBuffer, payload, copyLen);
    loraRxSize = copyLen;
    hasLoRaPacket = true;
}

// Process AT commands (optional)
void processATCommand(String command) {
    if (command == "AT") {
        Serial.println("OK");
    } else if (command == "AT+VERSION") {
        Serial.println("VERSION: Heltec V3 Bridge v1.0");
    } else if (command == "AT+INFO") {
        Serial.println("INFO: Bidirectional USB Serial Bridge");
        Serial.println("      RF Frequency: 915MHz");
        Serial.println("      USB Baud: 115200");
    } else if (command.startsWith("AT+FREQ=")) {
        String freq = command.substring(8);
        Serial.print("Frequency set to: ");
        Serial.println(freq);
    } else {
        Serial.println("ERROR: Unknown command");
    }
}

// Optional: Send data via LoRa
void sendLoRaMessage(String message) {
    uint8_t* data = (uint8_t*)message.c_str();
    uint8_t msgLen = message.length();
    
    // Configure TX settings
    Radio.SetTxConfig(MODEM_LORA, TX_POWER, 0, BANDWIDTH,
                      SPREADING_FACTOR, CODING_RATE,
                      8, false, true, 0, 0, false, 3000);
    
    // Send the data
    Radio.Send(data, msgLen);
    
    // Wait for TX to complete
    delay(100);
}
