import 'dart:async';
import 'dart:typed_data';
import 'package:usb_serial/usb_serial.dart';

class SerialCommunicationService {
  UsbPort? _port;
  StreamSubscription<Uint8List>? _subscription;
  final StreamController<String> _dataController = StreamController<String>.broadcast();
  final StreamController<bool> _connectionController = StreamController<bool>.broadcast();

  Stream<String> get dataStream => _dataController.stream;
  Stream<bool> get connectionStream => _connectionController.stream;
  bool get isConnected => _port != null;
  
  // Buffer for incoming data
  String _buffer = '';
  Timer? _bufferTimer;

  Future<List<UsbDevice>> getAvailableDevices() async {
    try {
      List<UsbDevice> devices = await UsbSerial.listDevices();
      return devices;
    } catch (e) {
      print('Error getting devices: $e');
      return [];
    }
  }

  Future<bool> connectToDevice(UsbDevice device, {int baudRate = 9600}) async {
    try {
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
      });

      _connectionController.add(true);
      return true;
    } catch (e) {
      print('Error connecting to device: $e');
      return false;
    }
  }

  Future<bool> disconnect() async {
    try {
      await _subscription?.cancel();
      await _port?.close();
      _port = null;
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
      if (_port == null) return false;
      
      Uint8List bytes = Uint8List.fromList(data.codeUnits);
      await _port!.write(bytes);
      return true;
    } catch (e) {
      print('Error sending data: $e');
      return false;
    }
  }

  void dispose() {
    _subscription?.cancel();
    _port?.close();
    _buffer = '';
    _bufferTimer?.cancel();
    _bufferTimer = null;
    _dataController.close();
    _connectionController.close();
  }
}
