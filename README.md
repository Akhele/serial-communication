# Serial Communication Flutter App

A Flutter application for communicating with USB serial devices. This app allows you to connect to USB serial devices, send and receive data, and manage connection settings.

## Features

- **Device Discovery**: Automatically detect available USB serial devices
- **Connection Management**: Connect/disconnect to/from devices with configurable baud rates
- **Data Communication**: Send and receive text data in real-time
- **Modern UI**: Clean, Material Design 3 interface with real-time status updates
- **Cross-Platform**: Works on both Android and iOS

## Getting Started

### Prerequisites

- Flutter SDK (3.0.0 or higher)
- Android Studio / Xcode for platform-specific development
- USB serial device for testing

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
- The app requires USB permissions which are already configured in `AndroidManifest.xml`
- Connect your USB device via USB OTG adapter
- Grant USB permissions when prompted

#### iOS
- iOS has limited USB serial support
- Consider using Bluetooth or WiFi-based communication for iOS devices
- The app structure supports iOS but may need additional configuration for specific use cases

## Usage

1. **Connect Device**: Connect your USB serial device to your mobile device
2. **Select Device**: Choose your device from the dropdown list
3. **Configure Settings**: Adjust baud rate if needed (default: 9600)
4. **Connect**: Tap the "Connect" button to establish communication
5. **Send Data**: Type messages in the input field and tap "Send"
6. **View Messages**: All sent and received messages appear in the messages area

## Project Structure

```
lib/
├── main.dart                           # App entry point
├── screens/
│   └── serial_communication_screen.dart # Main UI screen
└── services/
    └── serial_communication_service.dart # Serial communication logic
```

## Dependencies

- `usb_serial`: For USB serial communication
- `permission_handler`: For handling USB permissions
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
