import 'package:flutter/material.dart';
import 'package:usb_serial/usb_serial.dart';
import '../services/serial_communication_service.dart';
import '../providers/serial_service_provider.dart';
import 'advanced_configuration_screen.dart';

class ConfigurationScreen extends StatefulWidget {
  const ConfigurationScreen({super.key});

  @override
  State<ConfigurationScreen> createState() => _ConfigurationScreenState();
}

class _ConfigurationScreenState extends State<ConfigurationScreen> {
  SerialCommunicationService? _serialService;
  
  List<UsbDevice> _devices = [];
  UsbDevice? _selectedDevice;
  bool _isConnected = false;
  int _baudRate = 115200;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_serialService == null) {
      _serialService = SerialServiceProvider.of(context);
      _setupStreams();
      _loadDevices();
    }
  }

  void _setupStreams() {
    _serialService?.connectionStream.listen((isConnected) {
      setState(() {
        _isConnected = isConnected;
      });
    });
  }

  Future<void> _loadDevices() async {
    if (_serialService == null) return;
    final devices = await _serialService!.getAvailableDevices();
    setState(() {
      _devices = devices;
    });
  }

  Future<void> _connectToDevice() async {
    if (_selectedDevice == null || _serialService == null) return;

    final success = await _serialService!.connectToDevice(
      _selectedDevice!,
      baudRate: _baudRate,
    );

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connected successfully!')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to connect')),
      );
    }
  }

  Future<void> _disconnect() async {
    if (_serialService == null) return;
    await _serialService!.disconnect();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Disconnected')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Board Configuration'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDevices,
          ),
        ],
      ),
      body: Padding(
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
                    const Text(
                      'Device Selection',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    DropdownButton<UsbDevice>(
                      value: _selectedDevice,
                      hint: const Text('Select a device'),
                      isExpanded: true,
                      items: _devices.map((device) {
                        return DropdownMenuItem(
                          value: device,
                          child: Text('${device.productName} (${device.deviceId})'),
                        );
                      }).toList(),
                      onChanged: (device) {
                        setState(() {
                          _selectedDevice = device;
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
                      _isConnected ? 'Connected' : 'Disconnected',
                      style: TextStyle(
                        color: _isConnected ? Colors.green : Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            // Additional Configuration Options
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Additional Settings',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    const Text('Data Bits: 8'),
                    const SizedBox(height: 8),
                    const Text('Stop Bits: 1'),
                    const SizedBox(height: 8),
                    const Text('Parity: None'),
                    const SizedBox(height: 8),
                    const Text('Flow Control: None'),
                  ],
                ),
              ),
            ),
            
            const Spacer(),
            
            // Device Information
            if (_selectedDevice != null)
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
                      Text('Product Name: ${_selectedDevice!.productName}'),
                      Text('Device ID: ${_selectedDevice!.deviceId}'),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}
