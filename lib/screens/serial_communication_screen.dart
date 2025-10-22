import 'package:flutter/material.dart';
import 'package:usb_serial/usb_serial.dart';
import '../services/serial_communication_service.dart';

class SerialCommunicationScreen extends StatefulWidget {
  const SerialCommunicationScreen({super.key});

  @override
  State<SerialCommunicationScreen> createState() => _SerialCommunicationScreenState();
}

class _SerialCommunicationScreenState extends State<SerialCommunicationScreen> {
  final SerialCommunicationService _serialService = SerialCommunicationService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  List<UsbDevice> _devices = [];
  UsbDevice? _selectedDevice;
  final List<String> _receivedMessages = [];
  bool _isConnected = false;
  int _baudRate = 9600;

  @override
  void initState() {
    super.initState();
    _setupStreams();
    _loadDevices();
  }

  void _setupStreams() {
    _serialService.dataStream.listen((data) {
      setState(() {
        _receivedMessages.add('Received: $data');
      });
      _scrollToBottom();
    });

    _serialService.connectionStream.listen((isConnected) {
      setState(() {
        _isConnected = isConnected;
      });
    });
  }

  Future<void> _loadDevices() async {
    final devices = await _serialService.getAvailableDevices();
    setState(() {
      _devices = devices;
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _connectToDevice() async {
    if (_selectedDevice == null) return;

    final success = await _serialService.connectToDevice(
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
    await _serialService.disconnect();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Disconnected')),
    );
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.isEmpty) return;

    final success = await _serialService.sendData(_messageController.text);
    if (success) {
      setState(() {
        _receivedMessages.add('Sent: ${_messageController.text}');
      });
      _messageController.clear();
      _scrollToBottom();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to send message')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Serial Communication'),
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
                        Slider(
                          value: _baudRate.toDouble(),
                          min: 9600,
                          max: 115200,
                          divisions: 4,
                          label: _baudRate.toString(),
                          onChanged: (value) {
                            setState(() {
                              _baudRate = value.round();
                            });
                          },
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
            
            // Message Input
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Send Message',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _messageController,
                            decoration: const InputDecoration(
                              hintText: 'Enter message to send',
                              border: OutlineInputBorder(),
                            ),
                            enabled: _isConnected,
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: _isConnected ? _sendMessage : null,
                          child: const Text('Send'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            // Received Messages
            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Messages',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: ListView.builder(
                          controller: _scrollController,
                          itemCount: _receivedMessages.length,
                          itemBuilder: (context, index) {
                            final message = _receivedMessages[index];
                            final isReceived = message.startsWith('Received:');
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2.0),
                              child: Text(
                                message,
                                style: TextStyle(
                                  color: isReceived ? Colors.blue : Colors.green,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
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
    _serialService.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}
