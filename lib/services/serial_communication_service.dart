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
        _dataController.add(receivedData);
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
    _dataController.close();
    _connectionController.close();
  }
}
