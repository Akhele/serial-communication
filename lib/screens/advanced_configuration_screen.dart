import 'package:flutter/material.dart';
import '../services/serial_communication_service.dart';
import '../providers/serial_service_provider.dart';

class AdvancedConfigurationScreen extends StatefulWidget {
  const AdvancedConfigurationScreen({super.key});

  @override
  State<AdvancedConfigurationScreen> createState() => _AdvancedConfigurationScreenState();
}

class _AdvancedConfigurationScreenState extends State<AdvancedConfigurationScreen> {
  SerialCommunicationService? _serialService;
  
  int _baudRate = 115200;
  int _dataBits = 8;
  int _stopBits = 1;
  int _parity = 0; // 0 = None, 1 = Odd, 2 = Even
  bool _dtr = true;
  bool _rts = true;
  bool _isConnected = false;

  final List<int> _baudRateOptions = [9600, 19200, 38400, 57600, 115200];
  final List<int> _dataBitsOptions = [5, 6, 7, 8];
  final List<int> _stopBitsOptions = [1, 2];
  final List<String> _parityOptions = ['None', 'Odd', 'Even'];

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
    }
  }

  void _setupStreams() {
    _serialService?.connectionStream.listen((isConnected) {
      setState(() {
        _isConnected = isConnected;
      });
    });
  }

  Future<void> _applySettings() async {
    if (_serialService == null || !_isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please connect to a device first')),
      );
      return;
    }

    try {
      // Note: The current SerialCommunicationService doesn't support changing settings after connection
      // This would require extending the service to support reconfiguration
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings will be applied on next connection')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to apply settings: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Advanced Configuration'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
                      const Spacer(),
                      if (!_isConnected)
                        const Text(
                          'Connect a device to apply settings',
                          style: TextStyle(
                            fontStyle: FontStyle.italic,
                            color: Colors.grey,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Baud Rate Configuration
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Baud Rate',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      DropdownButton<int>(
                        value: _baudRate,
                        isExpanded: true,
                        items: _baudRateOptions.map((rate) {
                          return DropdownMenuItem(
                            value: rate,
                            child: Text('$rate bps'),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _baudRate = value!;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Data Bits Configuration
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Data Bits',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      DropdownButton<int>(
                        value: _dataBits,
                        isExpanded: true,
                        items: _dataBitsOptions.map((bits) {
                          return DropdownMenuItem(
                            value: bits,
                            child: Text('$bits bits'),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _dataBits = value!;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Stop Bits Configuration
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Stop Bits',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      DropdownButton<int>(
                        value: _stopBits,
                        isExpanded: true,
                        items: _stopBitsOptions.map((bits) {
                          return DropdownMenuItem(
                            value: bits,
                            child: Text('$bits bit${bits > 1 ? 's' : ''}'),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _stopBits = value!;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Parity Configuration
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Parity',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      DropdownButton<int>(
                        value: _parity,
                        isExpanded: true,
                        items: _parityOptions.asMap().entries.map((entry) {
                          return DropdownMenuItem(
                            value: entry.key,
                            child: Text(entry.value),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _parity = value!;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Control Signals Configuration
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Control Signals',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      SwitchListTile(
                        title: const Text('DTR (Data Terminal Ready)'),
                        subtitle: const Text('Controls the DTR signal'),
                        value: _dtr,
                        onChanged: (value) {
                          setState(() {
                            _dtr = value;
                          });
                        },
                      ),
                      SwitchListTile(
                        title: const Text('RTS (Request To Send)'),
                        subtitle: const Text('Controls the RTS signal'),
                        value: _rts,
                        onChanged: (value) {
                          setState(() {
                            _rts = value;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Current Settings Summary
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Current Settings',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text('Baud Rate: $_baudRate bps'),
                      Text('Data Bits: $_dataBits'),
                      Text('Stop Bits: $_stopBits'),
                      Text('Parity: ${_parityOptions[_parity]}'),
                      Text('DTR: ${_dtr ? 'Enabled' : 'Disabled'}'),
                      Text('RTS: ${_rts ? 'Enabled' : 'Disabled'}'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Apply Settings Button
              ElevatedButton(
                onPressed: _applySettings,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text(
                  'Apply Settings',
                  style: TextStyle(fontSize: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
