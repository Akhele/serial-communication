import 'dart:async';
import 'dart:typed_data';
import 'package:usb_serial/usb_serial.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

enum ConnectionType {
  usb,
  bluetooth,
}

class BluetoothDeviceInfo {
  final BluetoothDevice device;
  final String name;
  
  BluetoothDeviceInfo(this.device, this.name);
}

class SerialCommunicationService {
  // USB Serial
  UsbPort? _port;
  StreamSubscription<Uint8List>? _subscription;
  
  // Bluetooth
  BluetoothDevice? _bluetoothDevice;
  BluetoothCharacteristic? _writeCharacteristic;
  BluetoothCharacteristic? _readCharacteristic;
  StreamSubscription<List<int>>? _bluetoothSubscription;
  ConnectionType? _currentConnectionType;
  
  final StreamController<String> _dataController = StreamController<String>.broadcast();
  final StreamController<bool> _connectionController = StreamController<bool>.broadcast();

  Stream<String> get dataStream => _dataController.stream;
  Stream<bool> get connectionStream => _connectionController.stream;
  bool get isConnected => _currentConnectionType != null;
  ConnectionType? get currentConnectionType => _currentConnectionType;
  
  // Buffer for incoming data
  String _buffer = '';
  Timer? _bufferTimer;

  // USB Serial Methods
  Future<List<UsbDevice>> getAvailableUsbDevices() async {
    try {
      List<UsbDevice> devices = await UsbSerial.listDevices();
      return devices;
    } catch (e) {
      print('Error getting USB devices: $e');
      return [];
    }
  }

  Future<bool> connectToUsbDevice(UsbDevice device, {int baudRate = 115200}) async {
    try {
      // Disconnect any existing connection
      await disconnect();
      
      _port = await device.create();
      
      if (_port == null) {
        return false;
      }

      bool openResult = await _port!.open();
      if (!openResult) {
        return false;
      }

      await _port!.setDTR(true);
      await _port!.setRTS(true);
      await _port!.setPortParameters(
        baudRate,
        UsbPort.DATABITS_8,
        UsbPort.STOPBITS_1,
        UsbPort.PARITY_NONE,
      );

      _subscription = _port!.inputStream?.listen((Uint8List data) {
        _processIncomingData(data);
      });

      _currentConnectionType = ConnectionType.usb;
      _connectionController.add(true);
      return true;
    } catch (e) {
      print('Error connecting to USB device: $e');
      return false;
    }
  }

  // Bluetooth Methods
  Future<bool> isBluetoothAvailable() async {
    try {
      return await FlutterBluePlus.isSupported;
    } catch (e) {
      return false;
    }
  }

  Future<void> startBluetoothScan() async {
    if (await isBluetoothAvailable()) {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 4));
    }
  }

  Future<void> stopBluetoothScan() async {
    if (await isBluetoothAvailable()) {
      await FlutterBluePlus.stopScan();
    }
  }

  Stream<List<ScanResult>> get bluetoothScanResults {
    return FlutterBluePlus.scanResults;
  }

  Stream<bool> get bluetoothState => FlutterBluePlus.adapterState.map((state) => state == BluetoothAdapterState.on);

  Future<List<BluetoothDeviceInfo>> getAvailableBluetoothDevices() async {
    try {
      if (!(await isBluetoothAvailable())) {
        return [];
      }

      // Get previously connected devices
      List<BluetoothDevice> bondedDevices = await FlutterBluePlus.bondedDevices;
      return bondedDevices.map((device) => BluetoothDeviceInfo(device, device.platformName.isNotEmpty ? device.platformName : device.remoteId.str)).toList();
    } catch (e) {
      print('Error getting Bluetooth devices: $e');
      return [];
    }
  }

  Future<bool> connectToBluetoothDevice(BluetoothDevice device) async {
    try {
      // Disconnect any existing connection
      await disconnect();
      
      _bluetoothDevice = device;
      
      // Connect to device
      await device.connect(timeout: const Duration(seconds: 15), autoConnect: false);
      
      // Discover services
      List<BluetoothService> services = await device.discoverServices();
      
      // Find the Serial Port Profile (SPP) service
      // Standard BLE Serial service UUID: 0000ffe0-0000-1000-8000-00805f9b34fb
      // Characteristic for write: 0000ffe1-0000-1000-8000-00805f9b34fb
      BluetoothService? serialService;
      
      // Try common BLE Serial UUIDs
      final serialServiceUuids = [
        Guid("0000ffe0-0000-1000-8000-00805f9b34fb"), // Common BLE Serial
        Guid("6e400001-b5a3-f393-e0a9-e50e24dcca9e"), // Nordic UART
      ];
      
      for (BluetoothService service in services) {
        if (serialServiceUuids.contains(service.uuid)) {
          serialService = service;
          break;
        }
      }
      
      // If not found, try to use the first available service with write characteristic
      if (serialService == null) {
        for (BluetoothService service in services) {
          for (BluetoothCharacteristic char in service.characteristics) {
            if (char.properties.write || char.properties.writeWithoutResponse) {
              serialService = service;
              break;
            }
          }
          if (serialService != null) break;
        }
      }
      
      if (serialService == null) {
        await device.disconnect();
        return false;
      }
      
      // Find read and write characteristics
      for (BluetoothCharacteristic char in serialService.characteristics) {
        if (char.properties.read || char.properties.notify) {
          _readCharacteristic = char;
          if (char.properties.notify) {
            await char.setNotifyValue(true);
          }
        }
        if (char.properties.write || char.properties.writeWithoutResponse) {
          _writeCharacteristic = char;
        }
      }
      
      if (_writeCharacteristic == null) {
        await device.disconnect();
        return false;
      }
      
      // Subscribe to notifications/reads
      if (_readCharacteristic != null) {
        _bluetoothSubscription = _readCharacteristic!.lastValueStream.listen((List<int> data) {
          _processIncomingData(Uint8List.fromList(data));
        });
      }
      
      _currentConnectionType = ConnectionType.bluetooth;
      _connectionController.add(true);
      return true;
    } catch (e) {
      print('Error connecting to Bluetooth device: $e');
      await device.disconnect();
      return false;
    }
  }

  void _processIncomingData(Uint8List data) {
    String receivedData = String.fromCharCodes(data);
    _buffer += receivedData;
    
    // Process complete lines (messages ending with \n or \r\n)
    if (_buffer.contains('\n')) {
      List<String> lines = _buffer.split('\n');
      // Keep the last incomplete line in the buffer
      _buffer = lines.removeLast();
      
      for (String line in lines) {
        // Remove carriage return if present
        line = line.replaceAll('\r', '').trim();
        if (line.isNotEmpty) {
          _dataController.add(line);
        }
      }
    }
    
    // If we've received data and nothing more comes for a short time,
    // flush the buffer (in case message doesn't end with newline)
    _bufferTimer?.cancel();
    _bufferTimer = Timer(const Duration(milliseconds: 50), () {
      if (_buffer.isNotEmpty) {
        String line = _buffer.replaceAll('\r', '').trim();
        if (line.isNotEmpty) {
          _dataController.add(line);
        }
        _buffer = '';
      }
    });
  }

  Future<bool> disconnect() async {
    try {
      if (_currentConnectionType == ConnectionType.usb) {
        await _subscription?.cancel();
        await _port?.close();
        _port = null;
      } else if (_currentConnectionType == ConnectionType.bluetooth) {
        await _bluetoothSubscription?.cancel();
        _readCharacteristic = null;
        _writeCharacteristic = null;
        if (_bluetoothDevice != null) {
          await _bluetoothDevice!.disconnect();
          _bluetoothDevice = null;
        }
      }
      
      _currentConnectionType = null;
      _buffer = '';
      _bufferTimer?.cancel();
      _bufferTimer = null;
      _connectionController.add(false);
      return true;
    } catch (e) {
      print('Error disconnecting: $e');
      return false;
    }
  }

  Future<bool> sendData(String data) async {
    try {
      if (_currentConnectionType == ConnectionType.usb) {
        if (_port == null) return false;
        Uint8List bytes = Uint8List.fromList(data.codeUnits);
        await _port!.write(bytes);
        return true;
      } else if (_currentConnectionType == ConnectionType.bluetooth) {
        if (_writeCharacteristic == null) return false;
        Uint8List bytes = Uint8List.fromList(data.codeUnits);
        
        // Use write without response if available (faster), otherwise use write
        if (_writeCharacteristic!.properties.writeWithoutResponse) {
          await _writeCharacteristic!.write(bytes, withoutResponse: true);
        } else {
          await _writeCharacteristic!.write(bytes, withoutResponse: false);
        }
        return true;
      }
      return false;
    } catch (e) {
      print('Error sending data: $e');
      return false;
    }
  }

  // Legacy method for backward compatibility
  Future<List<UsbDevice>> getAvailableDevices() async {
    return getAvailableUsbDevices();
  }

  Future<bool> connectToDevice(UsbDevice device, {int baudRate = 115200}) async {
    return connectToUsbDevice(device, baudRate: baudRate);
  }

  void dispose() {
    disconnect();
    _dataController.close();
    _connectionController.close();
  }
}
