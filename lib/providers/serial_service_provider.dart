import 'package:flutter/material.dart';
import '../services/serial_communication_service.dart';

class SerialServiceProvider extends InheritedWidget {
  final SerialCommunicationService serialService;

  const SerialServiceProvider({
    super.key,
    required this.serialService,
    required super.child,
  });

  static SerialCommunicationService of(BuildContext context) {
    final provider = context.dependOnInheritedWidgetOfExactType<SerialServiceProvider>();
    if (provider == null) {
      throw Exception('SerialServiceProvider not found in widget tree');
    }
    return provider.serialService;
  }

  @override
  bool updateShouldNotify(SerialServiceProvider oldWidget) {
    return serialService != oldWidget.serialService;
  }
}
