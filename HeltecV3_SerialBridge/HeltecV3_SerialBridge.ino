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

// Enable/disable Bluetooth (set to false to disable BLE and save resources)
#define ENABLE_BLUETOOTH true

#if ENABLE_BLUETOOTH
// BLE Serial Service UUID (Standard BLE Serial UUID)
#define SERVICE_UUID        "0000ffe0-0000-1000-8000-00805f9b34fb"
#define CHARACTERISTIC_UUID_TX "0000ffe1-0000-1000-8000-00805f9b34fb"
#define CHARACTERISTIC_UUID_RX "0000ffe1-0000-1000-8000-00805f9b34fb"

BLEServer *pServer = NULL;
BLECharacteristic *pTxCharacteristic = NULL;
BLECharacteristic *pRxCharacteristic = NULL;
bool deviceConnected = false;
bool oldDeviceConnected = false;
#endif

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

#if ENABLE_BLUETOOTH
class MyServerCallbacks: public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) {
        deviceConnected = true;
        Serial.println("BLE: Device connected");
    }

    void onDisconnect(BLEServer* pServer) {
        deviceConnected = false;
        Serial.println("BLE: Device disconnected");
    }
};

class MyCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pCharacteristic) {
        std::string rxValue = pCharacteristic->getValue();
        if (rxValue.length() > 0) {
            String incoming = String(rxValue.c_str());
            incoming.trim();
            if (incoming.length() > 0) {
                processIncomingMessage(incoming);
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
    // Initialize BLE
    BLEDevice::init("Heltec V3 LoRa Bridge");
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
    Serial.println("BLE Device Name: Heltec V3 LoRa Bridge");
    Serial.println("Scan for this device in your app");
#endif
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
            processIncomingMessage(incoming);
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
        
        // Forward to USB Serial and/or Bluetooth (to Flutter app)
        // The app expects "username:message" format
        Serial.println(loraMessage);
        
#if ENABLE_BLUETOOTH
        // Also send via Bluetooth if connected
        if (deviceConnected && pTxCharacteristic != NULL) {
            pTxCharacteristic->setValue((uint8_t*)loraMessage.c_str(), loraMessage.length());
            pTxCharacteristic->notify();
        }
#endif
        
        hasLoRaPacket = false;
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
    
    // Small delay to prevent overwhelming the system
    delay(10);
}

// Process incoming messages from USB or Bluetooth
void processIncomingMessage(String incoming) {
    // Forward to LoRa if not an AT command
    if (!incoming.startsWith("AT")) {
        // Send via LoRa to other devices
        sendLoRaMessage(incoming);
    } else {
        // Process AT commands
        processATCommand(incoming);
    }
}

// Called by radio driver when a packet is received
void OnRxDone(uint8_t *payload, uint16_t size, int16_t rssi, int8_t snr) {
    uint16_t copyLen = size < sizeof(loraRxBuffer) ? size : sizeof(loraRxBuffer);
    memcpy(loraRxBuffer, payload, copyLen);67
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
    
    // Configure TX settings
    Radio.SetTxConfig(MODEM_LORA, TX_POWER, 0, BANDWIDTH,
                      SPREADING_FACTOR, CODING_RATE,
                      8, false, true, 0, 0, false, 3000);
    
    // Send the data
    Radio.Send(data, msgLen);
    
    // Wait for TX to complete
    delay(100);
}
