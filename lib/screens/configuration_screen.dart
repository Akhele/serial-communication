import 'package:flutter/material.dart';
import 'package:usb_serial/usb_serial.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../services/serial_communication_service.dart';
import '../providers/serial_service_provider.dart';
import 'advanced_configuration_screen.dart';

class ConfigurationScreen extends StatefulWidget {
  final Future<void> Function()? onConnectionSuccess;
  
  const ConfigurationScreen({super.key, this.onConnectionSuccess});

  @override
  State<ConfigurationScreen> createState() => _ConfigurationScreenState();
}

class _ConfigurationScreenState extends State<ConfigurationScreen> with SingleTickerProviderStateMixin {
  SerialCommunicationService? _serialService;
  
  // Connection Type
  late TabController _tabController;
  ConnectionType _selectedConnectionType = ConnectionType.usb;
  
  // USB
  List<UsbDevice> _usbDevices = [];
  UsbDevice? _selectedUsbDevice;
  
  // Bluetooth
  List<BluetoothDeviceInfo> _bluetoothDevices = [];
  BluetoothDeviceInfo? _selectedBluetoothDevice;
  bool _isScanning = false;
  List<ScanResult> _scanResults = [];
  bool _bluetoothAvailable = false;
  
  // General
  bool _isConnected = false;
  int _baudRate = 115200;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this, initialIndex: 1); // Start with Bluetooth tab
    _tabController.addListener(() {
      setState(() {
        _selectedConnectionType = _tabController.index == 0 ? ConnectionType.usb : ConnectionType.bluetooth;
      });
    });
    // Set initial connection type to Bluetooth
    _selectedConnectionType = ConnectionType.bluetooth;
  }

  void _showTopNotification(String message, Color backgroundColor, IconData icon) {
    final overlay = Overlay.of(context);
    late OverlayEntry overlayEntry;
    
    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 10,
        left: 16,
        right: 16,
        child: Material(
          color: Colors.transparent,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 300),
            builder: (context, value, child) {
              return Transform.translate(
                offset: Offset(0, -50 * (1 - value)),
                child: Opacity(
                  opacity: value,
                  child: child,
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(icon, color: Colors.white, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      message,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    
    overlay.insert(overlayEntry);
    
    Future.delayed(const Duration(seconds: 3), () {
      overlayEntry.remove();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_serialService == null) {
      _serialService = SerialServiceProvider.of(context);
      _setupStreams();
      _checkBluetoothAvailability();
      _loadUsbDevices();
      _loadBluetoothDevices();
    }
  }

  void _setupStreams() {
    _serialService?.connectionStream.listen((isConnected) {
      setState(() {
        _isConnected = isConnected;
      });
    });
    
    _serialService?.bluetoothScanResults.listen((results) {
      setState(() {
        _scanResults = results;
      });
    });
  }

  Future<void> _checkBluetoothAvailability() async {
    if (_serialService != null) {
      final available = await _serialService!.isBluetoothAvailable();
      setState(() {
        _bluetoothAvailable = available;
      });
    }
  }

  Future<void> _loadUsbDevices() async {
    if (_serialService == null) return;
    final devices = await _serialService!.getAvailableUsbDevices();
    setState(() {
      _usbDevices = devices;
    });
  }

  Future<void> _loadBluetoothDevices() async {
    if (_serialService == null || !_bluetoothAvailable) return;
    final devices = await _serialService!.getAvailableBluetoothDevices();
    setState(() {
      _bluetoothDevices = devices;
    });
  }

  Future<void> _startBluetoothScan() async {
    if (_serialService == null || !_bluetoothAvailable || _isScanning) return;
    
    setState(() {
      _isScanning = true;
      _scanResults = [];
    });
    
    await _serialService!.startBluetoothScan();
    
    Future.delayed(const Duration(seconds: 4), () {
      _serialService!.stopBluetoothScan();
      setState(() {
        _isScanning = false;
      });
    });
  }

  Future<void> _connectToDevice() async {
    if (_serialService == null) return;

    bool success = false;
    
    if (_selectedConnectionType == ConnectionType.usb) {
      if (_selectedUsbDevice == null) return;
      success = await _serialService!.connectToUsbDevice(
        _selectedUsbDevice!,
        baudRate: _baudRate,
      );
    } else if (_selectedConnectionType == ConnectionType.bluetooth) {
      if (_selectedBluetoothDevice == null) return;
      success = await _serialService!.connectToBluetoothDevice(_selectedBluetoothDevice!.device);
    }

    if (success) {
      _showTopNotification(
        'Board connected successfully!',
        const Color(0xFF4CAF50),
        Icons.check_circle,
      );
      
      // Navigate to Radar screen after successful connection
      Future.delayed(const Duration(milliseconds: 500), () async {
        await widget.onConnectionSuccess?.call();
      });
    } else {
      _showTopNotification(
        'Failed to connect',
        const Color(0xFFF44336),
        Icons.error,
      );
    }
  }

  Future<void> _disconnect() async {
    if (_serialService == null) return;
    await _serialService!.disconnect();
    _showTopNotification(
      'Disconnected',
      const Color(0xFF757575),
      Icons.bluetooth_disabled,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Board Configuration'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.usb), text: 'USB'),
            Tab(icon: Icon(Icons.bluetooth), text: 'Bluetooth'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // USB Tab
          _buildUsbTab(),
          // Bluetooth Tab
          _buildBluetoothTab(),
        ],
      ),
    );
  }

  Widget _buildUsbTab() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Device Selection
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'USB Device Selection',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        onPressed: _loadUsbDevices,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  DropdownButton<UsbDevice>(
                    value: _selectedUsbDevice,
                    hint: const Text('Select a USB device'),
                    isExpanded: true,
                    items: _usbDevices.map((device) {
                      return DropdownMenuItem(
                        value: device,
                        child: Text('${device.productName} (${device.deviceId})'),
                      );
                    }).toList(),
                    onChanged: _isConnected ? null : (device) {
                      setState(() {
                        _selectedUsbDevice = device;
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text('Baud Rate: $_baudRate'),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => const AdvancedConfigurationScreen(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.settings),
                        label: const Text('Advanced'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _isConnected ? null : _connectToDevice,
                          child: const Text('Connect'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _isConnected ? _disconnect : null,
                          child: const Text('Disconnect'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          
          // Connection Status
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Icon(
                    _isConnected ? Icons.check_circle : Icons.cancel,
                    color: _isConnected ? Colors.green : Colors.red,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _isConnected ? 'USB Connected' : 'Disconnected',
                    style: TextStyle(
                      color: _isConnected ? Colors.green : Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          
          // Device Information
          if (_selectedUsbDevice != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Device Information',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text('Product Name: ${_selectedUsbDevice!.productName}'),
                    Text('Device ID: ${_selectedUsbDevice!.deviceId}'),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBluetoothTab() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Bluetooth Availability Check
          if (!_bluetoothAvailable)
            Card(
              color: Colors.orange.withOpacity(0.1),
              child: const Padding(
                padding: EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Icon(Icons.warning, color: Colors.orange),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Bluetooth is not available on this device',
                        style: TextStyle(color: Colors.orange),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          
          if (_bluetoothAvailable) ...[
            // Device Selection
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Bluetooth Device Selection',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ),
                        IconButton(
                          icon: Icon(_isScanning ? Icons.stop : Icons.refresh),
                          onPressed: _isScanning ? _serialService?.stopBluetoothScan : _startBluetoothScan,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Scan Results
                    if (_scanResults.isNotEmpty) ...[
                      const Text(
                        'Available Devices (Tap to select):',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 150,
                        child: ListView.builder(
                          itemCount: _scanResults.length,
                          itemBuilder: (context, index) {
                            final result = _scanResults[index];
                            final deviceName = result.device.platformName.isNotEmpty 
                                ? result.device.platformName 
                                : result.device.remoteId.str;
                            final isSelected = _selectedBluetoothDevice?.device.remoteId == result.device.remoteId;
                            
                            return ListTile(
                              leading: const Icon(Icons.bluetooth_connected),
                              title: Text(deviceName),
                              subtitle: Text('RSSI: ${result.rssi} dBm'),
                              selected: isSelected,
                              onTap: _isConnected ? null : () {
                                setState(() {
                                  _selectedBluetoothDevice = BluetoothDeviceInfo(result.device, deviceName);
                                });
                              },
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    // Bonded Devices
                    DropdownButton<BluetoothDeviceInfo>(
                      value: _selectedBluetoothDevice,
                      hint: const Text('Select a Bluetooth device'),
                      isExpanded: true,
                      items: _bluetoothDevices.map((deviceInfo) {
                        return DropdownMenuItem(
                          value: deviceInfo,
                          child: Text(deviceInfo.name),
                        );
                      }).toList(),
                      onChanged: _isConnected ? null : (device) {
                        setState(() {
                          _selectedBluetoothDevice = device;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    if (_isScanning)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.0),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 8),
                            Text('Scanning for devices...'),
                          ],
                        ),
                      ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _isConnected ? null : _connectToDevice,
                            child: const Text('Connect'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _isConnected ? _disconnect : null,
                            child: const Text('Disconnect'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            // Connection Status
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Icon(
                      _isConnected ? Icons.check_circle : Icons.cancel,
                      color: _isConnected ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isConnected ? 'Bluetooth Connected' : 'Disconnected',
                      style: TextStyle(
                        color: _isConnected ? Colors.green : Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            
            // Device Information
            if (_selectedBluetoothDevice != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Device Information',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text('Device Name: ${_selectedBluetoothDevice!.name}'),
                      Text('Device ID: ${_selectedBluetoothDevice!.device.remoteId.str}'),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _serialService?.stopBluetoothScan();
    super.dispose();
  }
}
