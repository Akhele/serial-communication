import 'package:flutter/material.dart';
import 'screens/configuration_screen.dart';
import 'screens/messaging_screen.dart';
import 'services/serial_communication_service.dart';
import 'providers/serial_service_provider.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return SerialServiceProvider(
      serialService: SerialCommunicationService(),
      child: MaterialApp(
        title: 'Serial Communication',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
        ),
        home: const MainNavigationScreen(),
      ),
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  
  final List<Widget> _screens = [
    const ConfigurationScreen(),
    const MessagingScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Configuration',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.message),
            label: 'Messaging',
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    // Dispose the shared service when the main navigation is disposed
    SerialServiceProvider.of(context).dispose();
    super.dispose();
  }
}
