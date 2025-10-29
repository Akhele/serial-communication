# Serial Communication Flutter App

A Flutter application for communicating with USB serial devices. This app allows you to connect to USB serial devices, send and receive data, and manage connection settings.

## 🌐 Offline LoRa Communication

**This app + LoRa board = Complete offline messaging solution!**

![System Architecture](images/system-diagram.png)
*Figure 1: LoRa communication setup - App connects to LoRa board via USB, enabling offline messaging*

When combined with a LoRa-enabled board (like the Heltec Wireless Stick Lite V3), this app creates a complete standalone communication system that works **without any cellular network, WiFi, Bluetooth, or internet connection**. The system uses **Long Range (LoRa) radio technology** to enable device-to-device communication over distances of several kilometers, completely independent of traditional network infrastructure.

### Why use this system?
- ✅ **No network required**: Works in remote areas with no cellular or WiFi coverage
- ✅ **No external apps needed**: Direct device-to-device communication
- ✅ **Long range**: LoRa can reach several kilometers depending on terrain
- ✅ **Low power**: Ideal for battery-powered deployments
- ✅ **Privacy**: All communication stays on your local LoRa network
- ✅ **Emergency communication**: Perfect for situations where other networks fail

The Arduino code included (`HeltecV3_SerialBridge.ino`) enables your LoRa board to bridge USB serial communication from your mobile device to the LoRa network, allowing you to chat with other users on the same LoRa network.

## Features

- **Bluetooth (BLE) Connectivity**: Pair and chat over BLE on Android and iOS
- **USB Serial Connectivity**: Connect/disconnect with configurable baud rates
- **Data Communication**: Send and receive text data in real-time
- **LoRa Bridge Integration**: Offline long-range messaging via LoRa boards
- **WhatsApp-like UI**: Simple chat bubbles, timestamps, avatars, read ticks
- **User Profiles**: Customizable username, display name, and theme color
- **Message History**: View and export conversation logs
- **Cross-Platform**: Android and iOS support

## Getting Started

### Prerequisites

- Flutter SDK (3.0.0 or higher)
- Android Studio / Xcode for platform-specific development
- USB serial device (optional, for USB mode)
- BLE-capable phone (required for Bluetooth mode)
- **For LoRa communication**: Heltec Wireless Stick Lite V3 (or compatible LoRa board) and Arduino IDE

### Installation

1. Clone or download this project
2. Navigate to the project directory:
   ```bash
   cd serial-communication
   ```

3. Install dependencies:
   ```bash
   flutter pub get
   ```

4. Run the app:
   ```bash
   flutter run
   ```

### Platform Setup

#### Android
- USB and Bluetooth permissions are configured in `AndroidManifest.xml`
- For Android 12+, the app requests `BLUETOOTH_SCAN` and `BLUETOOTH_CONNECT`
- Connect USB devices via OTG; grant permissions when prompted

#### iOS
- iOS has limited USB serial support (prefer Bluetooth on iOS)
- Bluetooth usage descriptions are included in `Info.plist`
- Background mode `bluetooth-central` is enabled for stable BLE sessions

## Usage

### Bluetooth (BLE) Connection — Default
When the app launches, it opens the Configuration screen with the Bluetooth tab selected by default.

1. Ensure Bluetooth is enabled on your phone
2. Open the app (Bluetooth tab appears first)
3. Tap refresh to scan and select the LoRa Bridge device (e.g., "Heltec V3 LoRa Bridge")
4. Connect and switch to the Messaging tab to chat
5. Messages are exchanged over BLE and, via the board, over LoRa

### Basic Serial Communication (USB)
1. **Connect Device**: Connect your USB serial device to your mobile device
2. **Select Device**: Choose your device from the dropdown list
3. **Configure Settings**: Adjust baud rate if needed (default: 9600)
4. **Connect**: Tap the "Connect" button to establish communication
5. **Send Data**: Type messages in the input field and tap "Send"
6. **View Messages**: All sent and received messages appear in the messages area

### LoRa Communication Setup

![App Screenshot](images/app-screenshot.png)
*Figure 2: App interface showing connection status, chat messages, and profile settings*

1. **Setup LoRa Board**: Flash the included `HeltecV3_SerialBridge.ino` to your LoRa board (Heltec V3)
2. **Connect Board**: Connect your LoRa board to your mobile device via USB

![Hardware Setup](images/hardware-connection.png)
*Figure 3: Heltec V3 board connected to Android device via USB OTG cable*

3. **Open App**: Launch the Serial Communication app
4. **Connect to Board**: Select your LoRa board from the device list
5. **Configure Profile**: Set your username and preferences in the Profile tab
6. **Start Chatting**: Messages you send will be transmitted via LoRa to other connected devices on the same frequency

**Note**: Multiple users on the same LoRa network (same frequency, spreading factor, and bandwidth) can communicate with each other without any additional infrastructure.

## Project Structure

```
lib/
├── main.dart                                  # App entry point
├── screens/
│   ├── configuration_screen.dart             # Device connection & settings
│   ├── messaging_screen.dart                 # Chat interface
│   └── profile_screen.dart                   # User profile management
├── services/
│   ├── serial_communication_service.dart      # Serial communication logic
│   └── profile_service.dart                  # User profile storage
├── providers/
│   └── serial_service_provider.dart           # State management
└── models/
    ├── chat_message.dart                     # Message model
    └── user_profile.dart                     # User profile model

HeltecV3_SerialBridge/
└── HeltecV3_SerialBridge.ino                # Arduino LoRa + BLE bridge for Heltec V3
```

### Arduino LoRa + BLE Bridge

![Arduino IDE Setup](images/arduino-setup.png)
*Figure 4: Arduino IDE showing the LoRa bridge sketch and board configuration*

The `HeltecV3_SerialBridge.ino` sketch provides a bidirectional USB/BLE-to-LoRa bridge:
- Receives messages from the Flutter app via USB Serial or Bluetooth (BLE)
- Transmits messages to other LoRa devices on the same network
- Listens for LoRa packets and forwards them to the app over USB and/or BLE
- BLE service UUIDs: FFE0 (service), FFE1 (RX/TX characteristic)
- Uses Heltec LoRaWAN drivers and ESP32 BLE (no external libs required)

## Dependencies

- `flutter_blue_plus`: Bluetooth Low Energy (Android/iOS)
- `usb_serial`: USB serial communication
- `permission_handler`: USB permissions handling
- `shared_preferences`: Profile persistence
- `flutter`: Flutter SDK

## Troubleshooting

### Device Not Detected
- Ensure USB OTG adapter is properly connected
- Check if device drivers are installed
- Try refreshing the device list

### Connection Failed
- Verify the device is not in use by another application
- Check if the correct baud rate is selected
- Ensure USB permissions are granted

### No Data Received
- Verify the device is sending data
- Check baud rate configuration
- Ensure proper cable connection

## Contributing

Feel free to submit issues and enhancement requests!

## License

This project is open source and available under the MIT License.
