/*
 * Bidirectional USB Serial & Bluetooth Communication for Heltec Wireless Stick Lite V3
 * Compatible with Flutter Serial Communication App
 * 
 * This code enables full bidirectional communication via USB Serial and Bluetooth BLE:
 * - Receives commands/messages from the app (USB or Bluetooth)
 * - Sends responses/data back to the app
 * - Can send and receive simultaneously
 * - Supports both USB and BLE connections
 * 
 * For Bluetooth BLE support, this uses ESP32 BLE Serial Port Profile (SPP)
 */

#include "LoRaWan_APP.h"
#include "Arduino.h"
#include "BLEDevice.h"
#include "BLEServer.h"
#include "BLEUtils.h"
#include "BLE2902.h"
#include "esp_system.h"

// Enable/disable Bluetooth (set to false to disable BLE and save resources)
#define ENABLE_BLUETOOTH true

#if ENABLE_BLUETOOTH
// Nordic UART Service (NUS) UUIDs
// Service: 6E400001-B5A3-F393-E0A9-E50E24DCCA9E
// TX Char (notify): 6E400003-B5A3-F393-E0A9-E50E24DCCA9E
// RX Char (write):  6E400002-B5A3-F393-E0A9-E50E24DCCA9E
#define SERVICE_UUID            "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_UUID_TX  "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_UUID_RX  "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"

BLEServer *pServer = NULL;
BLECharacteristic *pTxCharacteristic = NULL;
BLECharacteristic *pRxCharacteristic = NULL;
bool deviceConnected = false;
bool oldDeviceConnected = false;
String bleRxBuffer = ""; // Buffer for chunked BLE data
#endif

// Forward declarations
void processIncomingMessage(String incoming);

// Configuration
#define RF_FREQUENCY        433000000  // 433 MHz (band) - adjust for your region
#define TX_POWER            14         // Max power for V3
#define SPREADING_FACTOR    7          // SF7
#define BANDWIDTH           0          // 125 kHz
#define CODING_RATE         1          // 4/5

// Message buffers
String rxBuffer = "";
String inputBuffer = "";
bool newData = false;
// Audio reassembly (single concurrent audio)
String currentAudioId = "";
int currentAudioTotal = 0;
int currentAudioDurationMs = 0;
int currentAudioReceived = 0;
String currentAudioUsername = "";
const int MAX_AUDIO_SEGMENTS = 64;
String audioChunks[MAX_AUDIO_SEGMENTS];
bool audioChunkPresent[MAX_AUDIO_SEGMENTS];

// Declare RadioEvents
RadioEvents_t RadioEvents;

// LoRa state
volatile bool hasLoRaPacket = false;
uint8_t loraRxBuffer[256];
uint16_t loraRxSize = 0;

// Callback prototype
void OnRxDone(uint8_t *payload, uint16_t size, int16_t rssi, int8_t snr);

#if ENABLE_BLUETOOTH
class MyServerCallbacks: public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) {
        deviceConnected = true;
        Serial.println("BLE: Device connected");
    }

    void onDisconnect(BLEServer* pServer) {
        deviceConnected = false;
        bleRxBuffer = ""; // Clear buffer on disconnect
        Serial.println("BLE: Device disconnected");
    }
};

class MyCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pCharacteristic) {
        String incoming = pCharacteristic->getValue();
        Serial.print("BLE: Received chunk (length=");
        Serial.print(incoming.length());
        Serial.print("): ");
        Serial.println(incoming.substring(0, incoming.length() > 60 ? 60 : incoming.length()));
        
        if (incoming.length() > 0) {
            // Buffer the data
            bleRxBuffer += incoming;
            
            // Check if we have a complete message (ends with newline)
            if (bleRxBuffer.indexOf('\n') >= 0) {
                // Process complete messages
                while (bleRxBuffer.indexOf('\n') >= 0) {
                    int nlIdx = bleRxBuffer.indexOf('\n');
                    String completeMessage = bleRxBuffer.substring(0, nlIdx);
                    bleRxBuffer = bleRxBuffer.substring(nlIdx + 1);
                    
                    completeMessage.trim();
                    if (completeMessage.length() > 0) {
                        Serial.print("BLE: Complete message assembled (length=");
                        Serial.print(completeMessage.length());
                        Serial.println(")");
                        processIncomingMessage(completeMessage);
                    }
                }
            } else {
                Serial.print("BLE: Buffering... (buffer length=");
                Serial.print(bleRxBuffer.length());
                Serial.println(")");
            }
        }
    }
};
#endif

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
    
#if ENABLE_BLUETOOTH
    // Initialize BLE with randomized suffix in device name
    uint32_t seed = (uint32_t)millis() ^ (esp_random());
    randomSeed(seed);
    int suffix = random(1000, 9999);
    String deviceName = String("Heltec V3 LoRa Bridge ") + String(suffix);
    BLEDevice::init(deviceName.c_str());
    pServer = BLEDevice::createServer();
    pServer->setCallbacks(new MyServerCallbacks());
    
    BLEService *pService = pServer->createService(SERVICE_UUID);
    
    // RX Characteristic (for receiving data from app)
    pRxCharacteristic = pService->createCharacteristic(
        CHARACTERISTIC_UUID_RX,
        BLECharacteristic::PROPERTY_WRITE |
        BLECharacteristic::PROPERTY_WRITE_NR
    );
    pRxCharacteristic->setCallbacks(new MyCallbacks());
    
    // TX Characteristic (for sending data to app)
    pTxCharacteristic = pService->createCharacteristic(
        CHARACTERISTIC_UUID_TX,
        BLECharacteristic::PROPERTY_READ |
        BLECharacteristic::PROPERTY_NOTIFY
    );
    pTxCharacteristic->addDescriptor(new BLE2902());
    
    pService->start();
    pServer->getAdvertising()->start();
    
    Serial.println("Bluetooth BLE: Active");
    Serial.print("BLE Device Name: ");
    Serial.println(deviceName);
    Serial.println("Scan for this device in your app");
#endif
    Serial.println();
}

void loop() {
    // CRITICAL: Process radio interrupts FIRST - must be called frequently
    // This triggers OnRxDone callback when LoRa packet arrives
    Radio.IrqProcess();
    
    // Keep LoRa listening for LoRa-to-LoRa communication
    // Radio.Rx(0) sets receiver to continuous listening mode
    // Only call if not already in RX mode or if we just finished TX
    static unsigned long lastRxMode = 0;
    if (millis() - lastRxMode > 1000) {  // Re-enter RX mode every second (handles any issues)
        Radio.Rx(0);
        lastRxMode = millis();
    }
    
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
            processIncomingMessage(incoming);
        }
    }
    
    // Handle LoRa packets (from other LoRa devices)
    if (hasLoRaPacket) {
        Serial.println("LoRa: Processing received packet...");
        
        uint16_t copyLen = loraRxSize < sizeof(loraRxBuffer) ? loraRxSize : sizeof(loraRxBuffer);
        
        // Copy received data to string buffer
        String loraMessage = "";
        for (int i = 0; i < copyLen; i++) {
            loraMessage += (char)loraRxBuffer[i];
        }
        
        Serial.print("LoRa: Message received: ");
        Serial.println(loraMessage);
        
        // Handle audio segmentation frames: AUDIO_SEG:<id>:<index>:<total>:<durationMs>:<username>:<base64>
        if (loraMessage.startsWith("AUDIO_SEG:")) {
            int p1 = loraMessage.indexOf(':', 10);
            int p2 = loraMessage.indexOf(':', p1 + 1);
            int p3 = loraMessage.indexOf(':', p2 + 1);
            int p4 = loraMessage.indexOf(':', p3 + 1);
            int p5 = loraMessage.indexOf(':', p4 + 1);
            if (p1 > 0 && p2 > p1 && p3 > p2 && p4 > p3 && p5 > p4) {
                String id = loraMessage.substring(10, p1);
                int index = loraMessage.substring(p1 + 1, p2).toInt();
                int total = loraMessage.substring(p2 + 1, p3).toInt();
                int duration = loraMessage.substring(p3 + 1, p4).toInt();
                String username = loraMessage.substring(p4 + 1, p5);
                String b64chunk = loraMessage.substring(p5 + 1);
                if (total > 0 && total <= MAX_AUDIO_SEGMENTS && index >= 0 && index < total) {
                    if (currentAudioId != id) {
                        Serial.print("LoRa Audio: Starting new audio assembly - ID=");
                        Serial.print(id);
                        Serial.print(", total=");
                        Serial.println(total);
                        currentAudioId = id;
                        currentAudioTotal = total;
                        currentAudioDurationMs = duration;
                        currentAudioUsername = username;
                        currentAudioReceived = 0;
                        for (int i = 0; i < MAX_AUDIO_SEGMENTS; i++) {
                            audioChunks[i] = "";
                            audioChunkPresent[i] = false;
                        }
                    }
                    if (!audioChunkPresent[index]) {
                        audioChunks[index] = b64chunk;
                        audioChunkPresent[index] = true;
                        currentAudioReceived++;
                        Serial.print("LoRa Audio: Stored segment ");
                        Serial.print(index);
                        Serial.print(" (");
                        Serial.print(index + 1);
                        Serial.print("/");
                        Serial.print(total);
                        Serial.print("), chunk length=");
                        Serial.print(b64chunk.length());
                        Serial.print(", received count=");
                        Serial.print(currentAudioReceived);
                        Serial.print("/");
                        Serial.println(currentAudioTotal);
                    } else {
                        Serial.print("LoRa Audio: Duplicate segment ");
                        Serial.print(index);
                        Serial.println(" ignored");
                    }
                    
                    // Check if we have all segments
                    Serial.print("LoRa Audio: Checking completeness - received=");
                    Serial.print(currentAudioReceived);
                    Serial.print(", total=");
                    Serial.println(currentAudioTotal);
                    
                    if (currentAudioReceived >= currentAudioTotal) {
                        Serial.println("LoRa Audio: All segments received! Assembling...");
                        // Check for missing segments
                        bool allPresent = true;
                        for (int i = 0; i < currentAudioTotal; i++) {
                            if (!audioChunkPresent[i]) {
                                Serial.print("LoRa Audio: WARNING - Missing segment ");
                                Serial.println(i);
                                allPresent = false;
                            }
                        }
                        if (!allPresent) {
                            Serial.println("LoRa Audio: ERROR - Assembly incomplete, missing segments!");
                            // Reset and hope for retransmission
                            currentAudioId = "";
                            currentAudioTotal = 0;
                            currentAudioReceived = 0;
                            return;
                        }
                        // Assemble base64
                        String fullB64 = "";
                        for (int i = 0; i < currentAudioTotal; i++) {
                            fullB64 += audioChunks[i];
                        }
                        Serial.print("LoRa Audio: Assembled base64 length=");
                        Serial.println(fullB64.length());
                        // Include username from first segment
                        String forward = currentAudioUsername + String(":AUDIO_B64:") + String(currentAudioDurationMs) + String(":") + fullB64 + String("\n");
                        Serial.println("LoRa Audio: assembly complete, forwarding to app via USB/BLE");
                        Serial.print("LoRa Audio: Forwarding message length=");
                        Serial.println(forward.length());
                        // Forward to USB
                        Serial.print(forward);
                        // Forward to BLE if connected (chunk for large payloads)
#if ENABLE_BLUETOOTH
                        if (deviceConnected && pTxCharacteristic != NULL) {
                            // BLE can't send very large payloads in one notify
                            // Send in chunks
                            const int BLE_CHUNK = 180;
                            int offset = 0;
                            while (offset < forward.length()) {
                                int end = offset + BLE_CHUNK;
                                if (end > forward.length()) end = forward.length();
                                String chunk = forward.substring(offset, end);
                                pTxCharacteristic->setValue((uint8_t*)chunk.c_str(), chunk.length());
                                pTxCharacteristic->notify();
                                offset = end;
                                delay(10); // small delay between BLE chunks
                            }
                            Serial.println("BLE: Audio forwarded in chunks");
                        }
#endif
                        // Reset assembly
                        currentAudioId = "";
                        currentAudioTotal = 0;
                        currentAudioDurationMs = 0;
                        currentAudioUsername = "";
                        currentAudioReceived = 0;
                        for (int i = 0; i < MAX_AUDIO_SEGMENTS; i++) {
                            audioChunks[i] = "";
                            audioChunkPresent[i] = false;
                        }
                    }
                }
            }
            hasLoRaPacket = false;
            loraRxSize = 0;
            Serial.println("LoRa: Audio segment processed");
        } else {
            // Handle regular text messages
            Serial.print("LoRa: Message length: ");
            Serial.println(loraMessage.length());
            
            // Forward to USB Serial and/or Bluetooth (to Flutter app)
        // The app expects "username:message" format
        Serial.print("USB Serial: ");
        Serial.println(loraMessage);
        
#if ENABLE_BLUETOOTH
        // Also send via Bluetooth if connected
        Serial.print("BLE: Checking connection - deviceConnected=");
        Serial.print(deviceConnected);
        Serial.print(", pTxCharacteristic=");
        Serial.println((pTxCharacteristic != NULL) ? "OK" : "NULL");
        
        if (deviceConnected && pTxCharacteristic != NULL) {
            // Add newline for app to recognize complete message
            String bleMessage = loraMessage + "\n";
            Serial.print("BLE: Preparing to send LoRa message: ");
            Serial.println(bleMessage);
            
            // Set the value
            pTxCharacteristic->setValue((uint8_t*)bleMessage.c_str(), bleMessage.length());
            
            // Notify (returns void)
            pTxCharacteristic->notify();
            Serial.println("BLE: LoRa message notification sent");
            Serial.print("BLE: Message sent via notify, length=");
            Serial.println(bleMessage.length());
        } else {
            if (!deviceConnected) {
                Serial.println("BLE: ERROR - Not connected to phone, cannot send LoRa message!");
            }
            if (pTxCharacteristic == NULL) {
                Serial.println("BLE: ERROR - TX characteristic is NULL, cannot send LoRa message!");
            }
        }
#else
        Serial.println("BLE: Disabled in build");
#endif
        
            // Clear the flag and buffer
            hasLoRaPacket = false;
            loraRxSize = 0;
            Serial.println("LoRa: Packet processing complete");
        }
    }
    
#if ENABLE_BLUETOOTH
    // Handle Bluetooth disconnection
    if (!deviceConnected && oldDeviceConnected) {
        delay(500); // Give the bluetooth stack time to recover
        pServer->startAdvertising(); // Restart advertising
        Serial.println("BLE: Start advertising");
        oldDeviceConnected = deviceConnected;
    }
    
    // Handle Bluetooth connection
    if (deviceConnected && !oldDeviceConnected) {
        oldDeviceConnected = deviceConnected;
    }
#endif
    
    // Periodic status (every 10 seconds) to confirm system is alive
    static unsigned long lastStatus = 0;
    if (millis() - lastStatus > 10000) {
        Serial.print("Status: LoRa listening, BLE=");
        Serial.print(deviceConnected ? "connected" : "disconnected");
        Serial.print(", lastLoRaRx=");
        Serial.println(millis() - lastStatus);
        lastStatus = millis();
    }
    
    // Minimal delay - Radio.IrqProcess() needs to run very frequently
    // to catch incoming LoRa packets
    delayMicroseconds(100);
}

// Process incoming messages from USB or Bluetooth
void processIncomingMessage(String incoming) {
    // Trim only whitespace, keep the actual message content
    incoming.trim();
    
    if (incoming.length() == 0) {
        return;
    }
    
    Serial.print("Processing message: ");
    Serial.println(incoming);
    
    // Forward to LoRa if not an AT command
    if (!incoming.startsWith("AT")) {
        // Check if message contains audio (may have username prefix like "username:AUDIO_B64:...")
        int audioIdx = incoming.indexOf("AUDIO_B64:");
        if (audioIdx >= 0) {
            // Segment and send over LoRa
            Serial.println("Segmenting audio for LoRa...");
            // Extract username if present
            String username = "";
            if (audioIdx > 0 && incoming.charAt(audioIdx - 1) == ':') {
                username = incoming.substring(0, audioIdx - 1);
            }
            // incoming format after username: AUDIO_B64:<durationMs>:<base64>
            String audioPart = incoming.substring(audioIdx);
            int p1 = audioPart.indexOf(':');
            int p2 = audioPart.indexOf(':', p1 + 1);
            if (p1 > 0 && p2 > p1) {
                int duration = audioPart.substring(p1 + 1, p2).toInt();
                String b64 = audioPart.substring(p2 + 1);
                // Segment into frames
                int id = (int)(millis() & 0x7FFFFFFF);
                const int CHUNK = 200; // larger chunks = fewer segments = more reliable
                int total = (b64.length() + CHUNK - 1) / CHUNK;
                Serial.print("Audio: segmenting into ");
                Serial.print(total);
                Serial.print(" chunks (b64 length=");
                Serial.print(b64.length());
                Serial.println(")");
                
                // Wait before starting to give receiver time to settle into RX mode
                delay(500);
                
                // Send each segment 3 times for maximum reliability
                for (int retry = 0; retry < 3; retry++) {
                    for (int i = 0; i < total; i++) {
                        int start = i * CHUNK;
                        int end = start + CHUNK;
                        if (end > b64.length()) end = b64.length();
                        String part = b64.substring(start, end);
                        // Include username in the segment for receiver to know sender
                        String frame = String("AUDIO_SEG:") + String(id) + String(":") + String(i) + String(":") + String(total) + String(":") + String(duration) + String(":") + username + String(":") + part;
                        Serial.print("TX seg ");
                        Serial.print(i + 1);
                        Serial.print("/");
                        Serial.print(total);
                        if (retry > 0) {
                            Serial.print(" [R");
                            Serial.print(retry);
                            Serial.print("]");
                        }
                        Serial.print(" len=");
                        Serial.println(frame.length());
                        sendLoRaMessage(frame);
                        
                        // Longer delay for reliability
                        delay(600);
                    }
                }
                Serial.println("Audio: all segments sent (3x redundancy)");
            } else {
                Serial.println("Audio: ERROR - invalid AUDIO_B64 format");
            }
            return;
        }
        // Send text via LoRa to other devices
        Serial.print("Sending to LoRa: ");
        Serial.println(incoming);
        sendLoRaMessage(incoming);
    } else {
        // Process AT commands
        processATCommand(incoming);
    }
}

// Called by radio driver when a packet is received
// This is an interrupt callback - must be fast and avoid delays
void OnRxDone(uint8_t *payload, uint16_t size, int16_t rssi, int8_t snr) {
    // This runs in interrupt context - minimize Serial printing
    // Just copy the data quickly
    uint16_t copyLen = size < sizeof(loraRxBuffer) ? size : sizeof(loraRxBuffer);
    memcpy(loraRxBuffer, payload, copyLen);
    loraRxSize = copyLen;
    hasLoRaPacket = true;
    
    // Detailed logging happens in loop() when processing the packet
}

// Process AT commands (optional)
void processATCommand(String command) {
    if (command == "AT") {
        Serial.println("OK");
    } else if (command == "AT+VERSION") {
        Serial.println("VERSION: Heltec V3 Bridge v1.0");
    } else if (command == "AT+INFO") {
        Serial.println("INFO: Bidirectional Serial Bridge");
        Serial.println("      RF Frequency: 433MHz");
        Serial.println("      USB Baud: 115200");
#if ENABLE_BLUETOOTH
        Serial.println("      Bluetooth BLE: Enabled");
        Serial.print("      BLE Connected: ");
        Serial.println(deviceConnected ? "Yes" : "No");
#else
        Serial.println("      Bluetooth BLE: Disabled");
#endif
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
    
    Serial.print("LoRa TX: Sending message (length=");
    Serial.print(msgLen);
    Serial.print("): ");
    Serial.println(message);
    
    // Configure TX settings
    Radio.SetTxConfig(MODEM_LORA, TX_POWER, 0, BANDWIDTH,
                      SPREADING_FACTOR, CODING_RATE,
                      8, false, true, 0, 0, false, 3000);
    
    // Send the data
    Radio.Send(data, msgLen);
    Serial.println("LoRa TX: Send command issued");
    
    // Wait for TX to complete (give it time to transmit)
    delay(300);
    Serial.println("LoRa TX: Transmission complete");
    
    // Re-enable RX mode after transmission
    Radio.Rx(0);
    Serial.println("LoRa: RX mode re-enabled after TX");
    
    // Extra delay to ensure receiver is ready
    delay(100);
}
