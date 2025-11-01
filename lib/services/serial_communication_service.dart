import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';
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
      
      // Increase MTU for better throughput if possible
      try {
        await device.requestMtu(247);
      } catch (_) {}
      
      // Discover services
      print('Bluetooth: Discovering services...');
      List<BluetoothService> services = await device.discoverServices();
      print('Bluetooth: Found ${services.length} services');
      
      // Print all services and characteristics for debugging
      for (var service in services) {
        print('Bluetooth: Service UUID: ${service.uuid}');
        print('Bluetooth: Service has ${service.characteristics.length} characteristics');
        for (var char in service.characteristics) {
          print('Bluetooth:   Char UUID: ${char.uuid}, Properties: notify=${char.properties.notify}, write=${char.properties.write}, writeNoResponse=${char.properties.writeWithoutResponse}');
        }
      }
      
      // Find the Serial Port Profile (SPP) service
      // Nordic UART Service: 6E400001-B5A3-F393-E0A9-E50E24DCCA9E
      // TX Char (notify): 6E400003-B5A3-F393-E0A9-E50E24DCCA9E
      // RX Char (write):  6E400002-B5A3-F393-E0A9-E50E24DCCA9E
      BluetoothService? serialService;
      
      // Try common BLE Serial UUIDs
      final nordicServiceUuid = Guid("6E400001-B5A3-F393-E0A9-E50E24DCCA9E");
      final commonSerialUuid = Guid("0000ffe0-0000-1000-8000-00805f9b34fb");
      
      for (BluetoothService service in services) {
        print('Bluetooth: Checking service ${service.uuid}');
        if (service.uuid == nordicServiceUuid || service.uuid == commonSerialUuid) {
          serialService = service;
          print('Bluetooth: Found matching service: ${service.uuid}');
          break;
        }
      }
      
      // If not found, try to use the first available service with write characteristic
      if (serialService == null) {
        print('Bluetooth: Service not found by UUID, searching by characteristics...');
        for (BluetoothService service in services) {
          for (BluetoothCharacteristic char in service.characteristics) {
            if (char.properties.write || char.properties.writeWithoutResponse) {
              serialService = service;
              print('Bluetooth: Found service with write characteristic: ${service.uuid}');
              break;
            }
          }
          if (serialService != null) break;
        }
      }
      
      if (serialService == null) {
        print('Bluetooth: ERROR - No suitable service found!');
        await device.disconnect();
        return false;
      }
      
      print('Bluetooth: Using service: ${serialService.uuid}');
      
      // Find read and write characteristics
      // Nordic UART: TX (notify) = 6E400003-B5A3-F393-E0A9-E50E24DCCA9E
      //              RX (write)  = 6E400002-B5A3-F393-E0A9-E50E24DCCA9E
      final txCharUuid = Guid("6E400003-B5A3-F393-E0A9-E50E24DCCA9E");
      final rxCharUuid = Guid("6E400002-B5A3-F393-E0A9-E50E24DCCA9E");
      
      for (BluetoothCharacteristic char in serialService.characteristics) {
        print('Bluetooth: Checking char ${char.uuid}, notify=${char.properties.notify}, write=${char.properties.write}, writeNoResponse=${char.properties.writeWithoutResponse}');
        
        // Match by UUID first (exact match)
        String charUuidStr = char.uuid.toString().toUpperCase();
        String txUuidStr = txCharUuid.toString().toUpperCase();
        String rxUuidStr = rxCharUuid.toString().toUpperCase();
        
        if (charUuidStr == txUuidStr || char.uuid == txCharUuid) {
          _readCharacteristic = char;
          print('Bluetooth: Found TX/Read characteristic by UUID: ${char.uuid}');
        } else if (charUuidStr == rxUuidStr || char.uuid == rxCharUuid) {
          _writeCharacteristic = char;
          print('Bluetooth: Found RX/Write characteristic by UUID: ${char.uuid}');
        }
      }
      
      // If UUIDs didn't match, try by properties (fallback)
      if (_readCharacteristic == null) {
        for (BluetoothCharacteristic char in serialService.characteristics) {
          if (char.properties.notify && char.uuid != _writeCharacteristic?.uuid) {
            _readCharacteristic = char;
            print('Bluetooth: Found TX/Read characteristic by properties: ${char.uuid}');
            break;
          }
        }
      }
      
      if (_writeCharacteristic == null) {
        for (BluetoothCharacteristic char in serialService.characteristics) {
          if ((char.properties.write || char.properties.writeWithoutResponse) && 
              char.uuid != _readCharacteristic?.uuid) {
            _writeCharacteristic = char;
            print('Bluetooth: Found RX/Write characteristic by properties: ${char.uuid}');
            break;
          }
        }
      }
      
      if (_writeCharacteristic == null) {
        print('Bluetooth: ERROR - Write characteristic not found!');
        await device.disconnect();
        return false;
      }
      
      if (_readCharacteristic == null) {
        print('Bluetooth: WARNING - Read/Notify characteristic not found, receive may not work!');
      }
      
      // Enable notifications then subscribe to onValueReceived
      if (_readCharacteristic != null) {
        print('Bluetooth: Enabling notifications on ${_readCharacteristic!.uuid}...');
        try {
          await _readCharacteristic!.setNotifyValue(true);
          print('Bluetooth: Notifications enabled successfully');
          
          // Subscribe to value changes
          _bluetoothSubscription = _readCharacteristic!.onValueReceived.listen(
            (List<int> data) {
              print('Bluetooth: Received ${data.length} bytes: ${String.fromCharCodes(data)}');
              _processIncomingData(Uint8List.fromList(data));
            },
            onError: (error) {
              print('Bluetooth: Error in notification stream: $error');
            },
            cancelOnError: false,
          );
          print('Bluetooth: Subscribed to notifications');
        } catch (e) {
          print('Bluetooth: Error enabling notifications: $e');
          print('Bluetooth: Stack trace: ${StackTrace.current}');
        }
      } else {
        print('Bluetooth: ERROR - Read characteristic is null, cannot receive messages!');
      }
      
      print('Bluetooth: Connection setup complete');
      print('Bluetooth: Write char: ${_writeCharacteristic?.uuid}, Read char: ${_readCharacteristic?.uuid}');
      
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
    String receivedData;
    try {
      receivedData = utf8.decode(data, allowMalformed: true);
    } catch (_) {
      // Fallback in case of partial UTF-8 sequences
      receivedData = String.fromCharCodes(data);
    }
    print('Processing incoming data: "$receivedData" (buffer length: ${_buffer.length})');
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
        Uint8List bytes = Uint8List.fromList(utf8.encode(data));
        await _port!.write(bytes);
        return true;
      } else if (_currentConnectionType == ConnectionType.bluetooth) {
        if (_writeCharacteristic == null) {
          print('Bluetooth: Write characteristic is null!');
          return false;
        }
        final bytes = Uint8List.fromList(utf8.encode(data));
        print('Bluetooth: Sending ${bytes.length} bytes');
        // Chunk only if payload exceeds safe MTU window
        try {
          const int chunkSize = 180; // conservative under typical MTU ~ 185-247
          if (bytes.length <= chunkSize) {
            if (_writeCharacteristic!.properties.writeWithoutResponse) {
              await _writeCharacteristic!.write(bytes, withoutResponse: true);
            } else {
              await _writeCharacteristic!.write(bytes, withoutResponse: false);
            }
          } else {
            int offset = 0;
            while (offset < bytes.length) {
              final end = (offset + chunkSize > bytes.length) ? bytes.length : offset + chunkSize;
              final chunk = bytes.sublist(offset, end);
              if (_writeCharacteristic!.properties.writeWithoutResponse) {
                await _writeCharacteristic!.write(chunk, withoutResponse: true);
              } else {
                await _writeCharacteristic!.write(chunk, withoutResponse: false);
              }
              offset = end;
              // Small pacing only for large transfers
              await Future.delayed(const Duration(milliseconds: 2));
            }
          }
          print('Bluetooth: Message sent successfully (chunked)');
          return true;
        } catch (e) {
          print('Bluetooth: Error sending message: $e');
          return false;
        }
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
