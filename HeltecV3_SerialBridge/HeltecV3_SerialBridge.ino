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

// Audio transmission settings
#define AUDIO_REDUNDANCY    1          // Send each segment this many times (1-3) - 1x for max speed
#define AUDIO_SEGMENT_DELAY 600        // Delay between segments in ms (increase if packets are lost)

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
bool currentAudioForwarded = false; // Track if we've already forwarded this audio
const int MAX_AUDIO_SEGMENTS = 64;
String audioChunks[MAX_AUDIO_SEGMENTS];
bool audioChunkPresent[MAX_AUDIO_SEGMENTS];

// Beacon broadcasting for radar discovery
unsigned long lastBeaconTime = 0;
const unsigned long BEACON_INTERVAL = 5000; // Broadcast every 5 seconds
String myUsername = "User"; // Default username, will be updated from app

// Declare RadioEvents
RadioEvents_t RadioEvents;

// LoRa state
volatile bool hasLoRaPacket = false;
volatile bool txDone = false;
uint8_t loraRxBuffer[256];
uint16_t loraRxSize = 0;
int16_t lastRssi = -999; // Store last received packet RSSI

// Callback prototypes
void OnRxDone(uint8_t *payload, uint16_t size, int16_t rssi, int8_t snr);
void OnTxDone(void);
void OnTxTimeout(void);
void OnRxTimeout(void);
void OnRxError(void);

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
    RadioEvents.TxDone = OnTxDone;
    RadioEvents.TxTimeout = OnTxTimeout;
    RadioEvents.RxTimeout = OnRxTimeout;
    RadioEvents.RxError = OnRxError;
    
    // Configure reception with continuous RX mode
    // Parameters: modem, bandwidth, datarate, coderate, bandwidthAfc, preambleLen, 
    //             symbTimeout, fixLen, payloadLen, crcOn, freqHopOn, hopPeriod, iqInverted, rxContinuous
    Radio.SetRxConfig(MODEM_LORA, BANDWIDTH, SPREADING_FACTOR,
                      CODING_RATE, 0, 8, 10, false, 0, true, 0, 0, false, true);
    
    Serial.println("LoRa RX Config:");
    Serial.print("  Bandwidth: ");
    Serial.println(BANDWIDTH);
    Serial.print("  SF: ");
    Serial.println(SPREADING_FACTOR);
    Serial.print("  CR: ");
    Serial.println(CODING_RATE);
    
    // Start in RX mode immediately
    Radio.Rx(0);
    Serial.println("LoRa: RX mode started");
    
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
        // IMPORTANT: Clear the flag FIRST to avoid missing new packets during processing
        hasLoRaPacket = false;
        
        unsigned long processStart = millis();
        Serial.println("LoRa: Processing received packet...");
        
        uint16_t copyLen = loraRxSize < sizeof(loraRxBuffer) ? loraRxSize : sizeof(loraRxBuffer);
        
        // Copy received data to string buffer
        String loraMessage = "";
        for (int i = 0; i < copyLen; i++) {
            loraMessage += (char)loraRxBuffer[i];
        }
        
        Serial.print("LoRa: Message received (len=");
        Serial.print(loraMessage.length());
        Serial.print("): ");
        // Only print first 50 chars for audio segments to reduce processing time
        if (loraMessage.startsWith("AUDIO_SEG:") && loraMessage.length() > 50) {
            Serial.println(loraMessage.substring(0, 50) + "...");
        } else {
            Serial.println(loraMessage);
        }
        
        // Handle beacon messages: LORA_BEACON:<username>:<deviceId>
        if (loraMessage.startsWith("LORA_BEACON:")) {
            int p1 = loraMessage.indexOf(':', 12);
            if (p1 > 0) {
                String username = loraMessage.substring(12, p1);
                String deviceId = loraMessage.substring(p1 + 1);
                
                // Get RSSI from last received packet (stored in OnRxDone)
                // We'll need to pass this from the callback
                extern int16_t lastRssi;
                
                // Forward to Flutter app with RSSI
                String beaconForward = "LORA_BEACON:" + username + ":" + deviceId + ":" + String(lastRssi);
                Serial.println(beaconForward);
                
#if ENABLE_BLUETOOTH
                if (deviceConnected && pTxCharacteristic != NULL) {
                    String bleMsg = beaconForward + "\n";
                    pTxCharacteristic->setValue((uint8_t*)bleMsg.c_str(), bleMsg.length());
                    pTxCharacteristic->notify();
                    delay(50);
                }
#endif
                // Return to RX mode
                Radio.Rx(0);
                return;
            }
        }
        
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
                        String startMsg = String("LoRa Audio: Starting new audio assembly - ID=") + String(id) + String(", total=") + String(total) + String(", username=") + username;
                        Serial.println(startMsg);
                        
                        // Send to BLE so Flutter app knows audio is starting (with username)
#if ENABLE_BLUETOOTH
                        if (deviceConnected && pTxCharacteristic != NULL) {
                            String bleMsg = startMsg + String("\n");
                            pTxCharacteristic->setValue((uint8_t*)bleMsg.c_str(), bleMsg.length());
                            pTxCharacteristic->notify();
                        }
#endif
                        
                        currentAudioId = id;
                        currentAudioTotal = total;
                        currentAudioDurationMs = duration;
                        currentAudioUsername = username;
                        currentAudioReceived = 0;
                        currentAudioForwarded = false; // Reset forwarded flag for new audio
                        for (int i = 0; i < MAX_AUDIO_SEGMENTS; i++) {
                            audioChunks[i] = "";
                            audioChunkPresent[i] = false;
                        }
                    }
                    if (!audioChunkPresent[index]) {
                        audioChunks[index] = b64chunk;
                        audioChunkPresent[index] = true;
                        currentAudioReceived++;
                        // Reduced verbosity for faster processing
                        String progressMsg = String("Audio RX: seg ") + String(index + 1) + String("/") + String(total) + String(" (") + String(currentAudioReceived) + String("/") + String(currentAudioTotal) + String(")");
                        Serial.println(progressMsg);
                        
                        // Send progress to BLE so Flutter app can track it
#if ENABLE_BLUETOOTH
                        if (deviceConnected && pTxCharacteristic != NULL) {
                            String bleMsg = progressMsg + String("\n");
                            pTxCharacteristic->setValue((uint8_t*)bleMsg.c_str(), bleMsg.length());
                            pTxCharacteristic->notify();
                        }
#endif
                    } else {
                        Serial.print("Audio RX: dup seg ");
                        Serial.println(index);
                    }
                    
                    // Check if we have all segments
                    if (currentAudioReceived >= currentAudioTotal) {
                        // Check if we've already forwarded this complete audio
                        if (currentAudioForwarded) {
                            Serial.println("Audio RX: Complete audio already forwarded, ignoring duplicate segments");
                        } else {
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
                                // Don't reset - keep waiting for missing segments from retries
                            } else {
                                // Assemble base64
                                String fullB64 = "";
                                for (int i = 0; i < currentAudioTotal; i++) {
                                    fullB64 += audioChunks[i];
                                }
                                Serial.print("LoRa Audio: Assembled base64 length=");
                                Serial.println(fullB64.length());
                                // Include username from first segment
                                String forward = currentAudioUsername + String(":AUDIO_B64_GZIP:") + String(currentAudioDurationMs) + String(":") + fullB64 + String("\n");
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
                                // Mark as forwarded to prevent duplicate forwarding
                                currentAudioForwarded = true;
                                Serial.println("Audio RX: Marked as forwarded, will ignore future duplicate segments");
                            }
                        }
                    }
                }
            }
            // hasLoRaPacket already cleared at start of processing
            loraRxSize = 0;
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
        
            // hasLoRaPacket already cleared at start of processing
            loraRxSize = 0;
        }
        
        // Log processing time to identify bottlenecks
        unsigned long processTime = millis() - processStart;
        Serial.print("LoRa: Packet processed in ");
        Serial.print(processTime);
        Serial.println("ms");
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
    static unsigned long lastLoRaRx = 0;
    if (hasLoRaPacket) {
        lastLoRaRx = millis();
    }
    if (millis() - lastStatus > 10000) {
        Serial.print("Status: LoRa listening, BLE=");
        Serial.print(deviceConnected ? "connected" : "disconnected");
        Serial.print(", lastLoRaRx=");
        Serial.print(millis() - lastLoRaRx);
        Serial.print("ms ago, hasLoRaPacket=");
        Serial.print(hasLoRaPacket);
        Serial.print(", rxSize=");
        Serial.println(loraRxSize);
        lastStatus = millis();
    }
    
    // Periodic beacon broadcast for radar discovery
    if (millis() - lastBeaconTime >= BEACON_INTERVAL) {
        lastBeaconTime = millis();
        broadcastBeacon();
    }
    
    // Small delay - Radio.IrqProcess() needs to run frequently
    // to catch incoming LoRa packets, but not too fast
    delay(1);
}

// Process incoming messages from USB or Bluetooth
void broadcastBeacon() {
    String beaconMsg = "LORA_BEACON:" + myUsername;
    
    // Get device ID from ESP32 MAC address
    uint8_t mac[6];
    esp_read_mac(mac, ESP_MAC_WIFI_STA);
    char deviceId[13];
    sprintf(deviceId, "%02X%02X%02X%02X%02X%02X", mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
    beaconMsg += ":" + String(deviceId);
    
    // Transmit beacon over LoRa
    Radio.Standby();
    Radio.SetTxConfig(MODEM_LORA, TX_POWER, 0, BANDWIDTH, SPREADING_FACTOR,
                      CODING_RATE, 8, false, true, 0, 0, false, 3000);
    Radio.Send((uint8_t*)beaconMsg.c_str(), beaconMsg.length());
    
    Serial.print("Beacon broadcasted: ");
    Serial.println(beaconMsg);
}

void processIncomingMessage(String incoming) {
    // Trim only whitespace, keep the actual message content
    incoming.trim();
    
    if (incoming.length() == 0) {
        return;
    }
    
    // Check for username update command
    if (incoming.startsWith("SET_USERNAME:")) {
        myUsername = incoming.substring(13);
        myUsername.trim();
        Serial.print("Username updated to: ");
        Serial.println(myUsername);
        return;
    }
    
    // Check for scan request
    if (incoming == "LORA_SCAN") {
        Serial.println("Scanning for nearby LoRa devices...");
        broadcastBeacon(); // Broadcast immediately when requested
        return;
    }
    
    Serial.print("Processing message: ");
    Serial.println(incoming);
    
    // Forward to LoRa if not an AT command
    if (!incoming.startsWith("AT")) {
        // Check if message contains audio (may have username prefix like "username:AUDIO_B64_GZIP:...")
        int audioIdx = incoming.indexOf("AUDIO_B64_GZIP:");
        if (audioIdx >= 0) {
            // Segment and send over LoRa
            Serial.println("Segmenting audio for LoRa...");
            // Extract username if present
            String username = "";
            if (audioIdx > 0 && incoming.charAt(audioIdx - 1) == ':') {
                username = incoming.substring(0, audioIdx - 1);
            }
            // incoming format after username: AUDIO_B64_GZIP:<durationMs>:<base64-gzipped>
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
                
                // Notify phone that transmission is starting
#if ENABLE_BLUETOOTH
                if (deviceConnected && pTxCharacteristic != NULL) {
                    String startMsg = String("Audio: segmenting into ") + String(total) + String(" chunks\n");
                    pTxCharacteristic->setValue((uint8_t*)startMsg.c_str(), startMsg.length());
                    pTxCharacteristic->notify();
                    delay(100); // Increased delay to ensure BLE transmission completes
                }
#endif
                
                // Wait before starting to give receiver time to settle into RX mode
                // Also gives Flutter app time to process init message and update UI
                delay(600); // Increased from 300ms to give Flutter time to render before segments arrive
                
                // Send each segment multiple times for reliability (configurable)
                // Optimized delays for faster transmission while maintaining reliability
                for (int retry = 0; retry < AUDIO_REDUNDANCY; retry++) {
                    for (int i = 0; i < total; i++) {
                        int start = i * CHUNK;
                        int end = start + CHUNK;
                        if (end > b64.length()) end = b64.length();
                        String part = b64.substring(start, end);
                        // Include username in the segment for receiver to know sender
                        String frame = String("AUDIO_SEG:") + String(id) + String(":") + String(i) + String(":") + String(total) + String(":") + String(duration) + String(":") + username + String(":") + part;
                        
                        // Build progress message
                        String progressMsg = String("TX seg ") + String(i + 1) + String("/") + String(total);
                        if (retry > 0) {
                            progressMsg += String(" [R") + String(retry) + String("]");
                        }
                        progressMsg += String(" len=") + String(frame.length());
                        Serial.println(progressMsg);
                        
                        // Send progress to BLE BEFORE LoRa transmission (only on first pass)
#if ENABLE_BLUETOOTH
                        if (retry == 0 && deviceConnected && pTxCharacteristic != NULL) {
                            String bleProgress = String("TX seg ") + String(i + 1) + String("/") + String(total) + String(" len=") + String(frame.length()) + String("\n");
                            pTxCharacteristic->setValue((uint8_t*)bleProgress.c_str(), bleProgress.length());
                            pTxCharacteristic->notify();
                            Serial.print("BLE: Sent progress - ");
                            Serial.println(bleProgress);
                            delay(300); // Increased delay to 300ms to give Flutter time to render each percentage update
                        }
#endif
                        
                        sendLoRaMessage(frame);
                        
                        // Optimized delay between segments for faster transmission
                        // Large packets need processing time on receiver side
                        delay(AUDIO_SEGMENT_DELAY);
                    }
                    // Shorter delay between retry passes for faster overall transmission
                    if (retry < (AUDIO_REDUNDANCY - 1)) {
                        Serial.print("Retry pass ");
                        Serial.print(retry + 1);
                        Serial.println(" complete, waiting before next pass...");
                        delay(1500);
                    }
                }
                Serial.print("Audio: all segments sent (");
                Serial.print(AUDIO_REDUNDANCY);
                Serial.println("x redundancy)");
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
    lastRssi = rssi; // Store RSSI for beacon forwarding
    hasLoRaPacket = true;
    
    // Log signal quality (brief)
    Serial.print("LoRa RX: size=");
    Serial.print(size);
    Serial.print(", RSSI=");
    Serial.print(rssi);
    Serial.print(", SNR=");
    Serial.println(snr);
    
    // Detailed logging happens in loop() when processing the packet
}

// Called when TX is complete
void OnTxDone(void) {
    txDone = true;
    Serial.println("LoRa: TX Done callback");
}

// Called when TX times out
void OnTxTimeout(void) {
    Serial.println("LoRa: TX Timeout!");
}

// Called when RX times out (no packet received in expected time)
void OnRxTimeout(void) {
    // This is normal in continuous RX mode - don't spam the console
    // Serial.println("LoRa: RX Timeout");
}

// Called when RX has an error
void OnRxError(void) {
    Serial.println("LoRa: RX Error!");
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
    } else if (command == "AT+LORA") {
        Serial.println("LoRa Configuration:");
        Serial.print("  Frequency: ");
        Serial.print(RF_FREQUENCY);
        Serial.println(" Hz");
        Serial.print("  TX Power: ");
        Serial.println(TX_POWER);
        Serial.print("  Spreading Factor: ");
        Serial.println(SPREADING_FACTOR);
        Serial.print("  Bandwidth: ");
        Serial.print(BANDWIDTH);
        Serial.println(" (0=125kHz, 1=250kHz, 2=500kHz)");
        Serial.print("  Coding Rate: ");
        Serial.print(CODING_RATE);
        Serial.println(" (1=4/5, 2=4/6, 3=4/7, 4=4/8)");
    } else if (command.startsWith("AT+FREQ=")) {
        String freq = command.substring(8);
        Serial.print("Frequency set to: ");
        Serial.println(freq);
    } else if (command == "AT+TEST") {
        Serial.println("Sending test LoRa beacon...");
        sendLoRaMessage("TEST:BEACON:" + String(millis()));
    } else if (command == "AT+RXMODE") {
        Serial.println("Forcing RX mode...");
        Radio.Rx(0);
        Serial.println("RX mode activated");
    } else if (command == "AT+DIAG") {
        Serial.println("=== Diagnostics ===");
        Serial.print("hasLoRaPacket: ");
        Serial.println(hasLoRaPacket);
        Serial.print("loraRxSize: ");
        Serial.println(loraRxSize);
        Serial.print("txDone: ");
        Serial.println(txDone);
        Serial.println("Callbacks registered:");
        Serial.print("  RxDone: ");
        Serial.println((RadioEvents.RxDone != NULL) ? "YES" : "NO");
        Serial.print("  TxDone: ");
        Serial.println((RadioEvents.TxDone != NULL) ? "YES" : "NO");
        Serial.print("  RxTimeout: ");
        Serial.println((RadioEvents.RxTimeout != NULL) ? "YES" : "NO");
        Serial.print("  RxError: ");
        Serial.println((RadioEvents.RxError != NULL) ? "YES" : "NO");
    } else {
        Serial.println("ERROR: Unknown command");
        Serial.println("Available commands:");
        Serial.println("  AT - Test connection");
        Serial.println("  AT+VERSION - Show version");
        Serial.println("  AT+INFO - Show system info");
        Serial.println("  AT+LORA - Show LoRa config");
        Serial.println("  AT+TEST - Send test beacon");
        Serial.println("  AT+RXMODE - Force RX mode");
        Serial.println("  AT+DIAG - Show diagnostics");
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
    
    // Configure TX settings (preamble=8, timeout=3000ms)
    Radio.SetTxConfig(MODEM_LORA, TX_POWER, 0, BANDWIDTH,
                      SPREADING_FACTOR, CODING_RATE,
                      8, false, true, 0, 0, false, 3000);
    
    // Reset TX done flag
    txDone = false;
    
    // Send the data
    Radio.Send(data, msgLen);
    Serial.println("LoRa TX: Send command issued");
    
    // Wait for TX to complete using callback flag
    unsigned long txStart = millis();
    while (!txDone && (millis() - txStart < 5000)) {
        Radio.IrqProcess();
        delay(1);
    }
    
    if (txDone) {
        Serial.println("LoRa TX: Transmission complete (confirmed by callback)");
    } else {
        Serial.println("LoRa TX: WARNING - No TX Done callback received!");
    }
    
    // CRITICAL: Re-enable RX mode immediately after transmission
    Radio.Rx(0);
    Serial.println("LoRa: RX mode re-enabled after TX");
}
