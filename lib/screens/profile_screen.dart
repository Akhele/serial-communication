import 'package:flutter/material.dart';
import '../services/serial_communication_service.dart';
import '../providers/serial_service_provider.dart';
import 'dart:async';

class ProfileScreen extends StatefulWidget {
  final String username;

  const ProfileScreen({Key? key, required this.username}) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  SerialCommunicationService? _serialService;
  String? _status;
  String? _location;
  int? _rssi;
  StreamSubscription? _dataSubscription;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_serialService == null) {
      _serialService = SerialServiceProvider.of(context);
      _requestProfile();
      _setupProfileStream();
    }
  }

  void _setupProfileStream() {
    _dataSubscription = _serialService?.dataStream.listen((message) {
      _parseProfileMessage(message.trim());
    });
  }

  void _parseProfileMessage(String message) {
    // Expected format: "PROFILE:username:status:location:rssi"
    if (message.startsWith('PROFILE:')) {
      final parts = message.substring(8).split(':');
      if (parts.length >= 4 && parts[0] == widget.username) {
        setState(() {
          _status = parts[1].isNotEmpty ? parts[1] : null;
          _location = parts[2].isNotEmpty ? parts[2] : null;
          _rssi = int.tryParse(parts[3]);
        });
      }
    }
  }

  void _requestProfile() {
    _serialService?.sendData('GET_PROFILE:${widget.username}\n');
  }

  @override
  void dispose() {
    _dataSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF128C7E),
        elevation: 0,
        title: const Text('Profile', style: TextStyle(color: Colors.white)),
      ),
      body: Column(
        children: [
          // Header with avatar
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              color: Color(0xFF128C7E),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(32),
                bottomRight: Radius.circular(32),
              ),
            ),
            padding: const EdgeInsets.only(bottom: 40),
            child: Column(
              children: [
                const SizedBox(height: 20),
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      widget.username.isNotEmpty ? widget.username[0].toUpperCase() : '?',
                      style: const TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF128C7E),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  widget.username,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Profile Information
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildInfoCard(
                  'Status',
                  _status ?? 'No status set',
                  Icons.info_outline,
                ),
                const SizedBox(height: 12),
                _buildInfoCard(
                  'Location',
                  _location ?? 'Unknown',
                  Icons.location_on_outlined,
                ),
                const SizedBox(height: 12),
                _buildInfoCard(
                  'Signal Strength',
                  _rssi != null ? '$_rssi dBm' : 'Unknown',
                  Icons.signal_cellular_alt,
                  color: _getRssiColor(_rssi),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(String label, String value, IconData icon, {Color? color}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: (color ?? const Color(0xFF128C7E)).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color ?? const Color(0xFF128C7E)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF111B21),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getRssiColor(int? rssi) {
    if (rssi == null) return Colors.grey;
    if (rssi > -60) return const Color(0xFF00FF88);
    if (rssi > -80) return const Color(0xFF00D9FF);
    if (rssi > -100) return const Color(0xFFFFAA00);
    return const Color(0xFFFF4444);
  }
}
