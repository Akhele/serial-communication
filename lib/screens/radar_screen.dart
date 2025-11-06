import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:async';
import '../services/serial_communication_service.dart';
import '../providers/serial_service_provider.dart';
import '../services/profile_service.dart';
import '../models/avatar.dart';
import 'messaging_screen.dart';

class LoRaDevice {
  final String username;
  final String deviceId;
  final int rssi;
  final int avatarId;
  final DateTime lastSeen;
  final double? latitude;
  final double? longitude;

  LoRaDevice({
    required this.username,
    required this.deviceId,
    required this.rssi,
    required this.avatarId,
    required this.lastSeen,
    this.latitude,
    this.longitude,
  });

  // Calculate distance based on RSSI (rough estimate)
  double get estimatedDistance {
    // RSSI to distance conversion (simplified)
    // Typical LoRa RSSI: -30 (very close) to -120 (far)
    final normalizedRssi = (rssi + 120).clamp(0, 90);
    return (90 - normalizedRssi) / 90.0; // 0.0 to 1.0 (0 = close, 1 = far)
  }

  // Calculate approximate distance in meters based on RSSI
  String get estimatedDistanceMeters {
    // LoRa RSSI to distance estimation
    // This is a rough approximation and can vary based on environment
    // Formula: d = 10 ^ ((TxPower - RSSI) / (10 * n))
    // Where n = path loss exponent (2.7-4.0, typically ~3.0 for outdoor)
    
    if (rssi >= -40) {
      return '< 5m';
    } else if (rssi >= -55) {
      return '5-15m';
    } else if (rssi >= -70) {
      return '15-50m';
    } else if (rssi >= -85) {
      return '50-150m';
    } else if (rssi >= -100) {
      return '150-500m';
    } else if (rssi >= -110) {
      return '0.5-1km';
    } else {
      return '> 1km';
    }
  }

  bool get isOnline {
    return DateTime.now().difference(lastSeen).inSeconds < 30;
  }
}

class RadarScreen extends StatefulWidget {
  const RadarScreen({Key? key}) : super(key: key);

  @override
  State<RadarScreen> createState() => _RadarScreenState();
}

class _RadarScreenState extends State<RadarScreen> with SingleTickerProviderStateMixin {
  late AnimationController _radarController;
  SerialCommunicationService? _serialService;
  final ProfileService _profileService = ProfileService();
  final Map<String, LoRaDevice> _discoveredDevices = {};
  Timer? _cleanupTimer;
  StreamSubscription? _dataSubscription;

  @override
  void initState() {
    super.initState();
    _radarController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat();

    // Cleanup old devices every 5 seconds
    _cleanupTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _cleanupOldDevices();
    });
    
    // Load profile and send username to Arduino
    _initializeProfile();
  }

  Future<void> _initializeProfile() async {
    await _profileService.loadProfile();
    // Send username to Arduino for beacon broadcasting
    if (_serialService != null) {
      final username = _profileService.currentProfile.username;
      print('Radar: Sending username to Arduino: $username');
      await _serialService!.sendData('SET_USERNAME:$username\n');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_serialService == null) {
      _serialService = SerialServiceProvider.of(context);
      _setupDiscoveryStream();
      // Re-send username in case it wasn't set before
      _initializeProfile();
      _requestDeviceList();
    }
  }

  void _setupDiscoveryStream() {
    _dataSubscription = _serialService?.dataStream.listen((message) {
      _parseDiscoveryMessage(message.trim());
    });
    print('Radar: Discovery stream setup complete');
  }

  void _parseDiscoveryMessage(String message) {
    // Expected format: "LORA_BEACON:username:deviceId:avatarId:rssi"
    if (message.startsWith('LORA_BEACON:')) {
      print('Radar: Received beacon - $message');
      final parts = message.substring(12).split(':');
      if (parts.length >= 4) {
        final username = parts[0];
        final deviceId = parts[1];
        final avatarId = int.tryParse(parts[2]) ?? 0;
        final rssi = int.tryParse(parts[3]) ?? -100;

        print('Radar: Parsed - Username: $username, DeviceID: $deviceId, AvatarID: $avatarId, RSSI: $rssi');

        setState(() {
          _discoveredDevices[deviceId] = LoRaDevice(
            username: username,
            deviceId: deviceId,
            rssi: rssi,
            avatarId: avatarId,
            lastSeen: DateTime.now(),
          );
        });
        
        print('Radar: Device added. Total devices: ${_discoveredDevices.length}');
      } else {
        print('Radar: Invalid beacon format - expected 4+ parts, got ${parts.length}');
      }
    }
  }

  void _requestDeviceList() {
    // Send command to request nearby devices
    print('Radar: Sending LORA_SCAN command');
    _serialService?.sendData('LORA_SCAN\n');
  }

  void _cleanupOldDevices() {
    setState(() {
      _discoveredDevices.removeWhere((key, device) {
        return DateTime.now().difference(device.lastSeen).inSeconds > 30;
      });
    });
  }

  void _openChat(LoRaDevice device) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MessagingScreen(
          targetUsername: device.username,
          targetDeviceId: device.deviceId,
          targetAvatarId: device.avatarId,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _radarController.dispose();
    _cleanupTimer?.cancel();
    _dataSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onlineDevices = _discoveredDevices.values.where((d) => d.isOnline).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B263B),
        elevation: 0,
        title: const Text(
          'LoRa Radar',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _requestDeviceList,
          ),
        ],
      ),
      body: Column(
        children: [
          // Stats Card
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1B263B),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00D9FF).withOpacity(0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem(
                  'Online',
                  onlineDevices.length.toString(),
                  const Color(0xFF00D9FF),
                  Icons.signal_cellular_alt,
                ),
                Container(width: 1, height: 40, color: Colors.white24),
                _buildStatItem(
                  'Total Found',
                  _discoveredDevices.length.toString(),
                  const Color(0xFF00FF88),
                  Icons.devices,
                ),
              ],
            ),
          ),

          // Radar Display
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Radar circles
                CustomPaint(
                  size: Size.infinite,
                  painter: RadarBackgroundPainter(),
                ),

                // Scanning line
                AnimatedBuilder(
                  animation: _radarController,
                  builder: (context, child) {
                    return CustomPaint(
                      size: Size.infinite,
                      painter: RadarScannerPainter(
                        angle: _radarController.value * 2 * math.pi,
                      ),
                    );
                  },
                ),

                // Devices
                ...onlineDevices.map((device) {
                  return _buildDeviceMarker(device);
                }).toList(),

                // Center dot
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: const Color(0xFF00FF88),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00FF88).withOpacity(0.6),
                        blurRadius: 16,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Device List
          if (onlineDevices.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              decoration: const BoxDecoration(
                color: Color(0xFF1B263B),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Nearby Devices',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: onlineDevices.length,
                      itemBuilder: (context, index) {
                        final device = onlineDevices[index];
                        final avatar = Avatars.getById(device.avatarId);
                        return ListTile(
                          leading: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: const Color(0xFF128C7E).withOpacity(0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                avatar.emoji,
                                style: const TextStyle(
                                  fontSize: 24,
                                ),
                              ),
                            ),
                          ),
                          title: Text(
                            device.username,
                            style: const TextStyle(color: Colors.white),
                          ),
                          subtitle: Text(
                            'RSSI: ${device.rssi} dBm  •  ~${device.estimatedDistanceMeters}',
                            style: const TextStyle(color: Colors.white70),
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: _getRssiColor(device.rssi).withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _getSignalStrength(device.rssi),
                              style: TextStyle(
                                color: _getRssiColor(device.rssi),
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          onTap: () => _openChat(device),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildDeviceMarker(LoRaDevice device) {
    final distance = device.estimatedDistance;
    final angle = (device.deviceId.hashCode % 360) * math.pi / 180;
    final radius = 120 * distance;

    final x = radius * math.cos(angle);
    final y = radius * math.sin(angle);
    final avatar = Avatars.getById(device.avatarId);

    return Transform.translate(
      offset: Offset(x, y),
      child: GestureDetector(
        onTap: () => _openChat(device),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _getRssiColor(device.rssi),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: _getRssiColor(device.rssi).withOpacity(0.6),
                blurRadius: 12,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Center(
            child: Text(
              avatar.emoji,
              style: const TextStyle(
                fontSize: 20,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _getRssiColor(int rssi) {
    if (rssi > -60) return const Color(0xFF00FF88); // Excellent
    if (rssi > -80) return const Color(0xFF00D9FF); // Good
    if (rssi > -100) return const Color(0xFFFFAA00); // Fair
    return const Color(0xFFFF4444); // Poor
  }

  String _getSignalStrength(int rssi) {
    if (rssi > -60) return 'Excellent';
    if (rssi > -80) return 'Good';
    if (rssi > -100) return 'Fair';
    return 'Poor';
  }
}

class RadarBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = math.min(size.width, size.height) / 2 - 20;
    final paint = Paint()
      ..color = const Color(0xFF00D9FF).withOpacity(0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    // Draw concentric circles
    for (int i = 1; i <= 4; i++) {
      canvas.drawCircle(center, maxRadius * i / 4, paint);
    }

    // Draw crosshairs
    final crosshairPaint = Paint()
      ..color = const Color(0xFF00D9FF).withOpacity(0.2)
      ..strokeWidth = 1;

    canvas.drawLine(
      Offset(center.dx - maxRadius, center.dy),
      Offset(center.dx + maxRadius, center.dy),
      crosshairPaint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - maxRadius),
      Offset(center.dx, center.dy + maxRadius),
      crosshairPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class RadarScannerPainter extends CustomPainter {
  final double angle;

  RadarScannerPainter({required this.angle});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = math.min(size.width, size.height) / 2 - 20;

    final gradient = SweepGradient(
      startAngle: angle,
      endAngle: angle + math.pi / 4,
      colors: [
        const Color(0xFF00FF88).withOpacity(0.0),
        const Color(0xFF00FF88).withOpacity(0.5),
      ],
    );

    final paint = Paint()
      ..shader = gradient.createShader(Rect.fromCircle(center: center, radius: maxRadius))
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, maxRadius, paint);
  }

  @override
  bool shouldRepaint(RadarScannerPainter oldDelegate) => angle != oldDelegate.angle;
}

