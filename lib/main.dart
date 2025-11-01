import 'package:flutter/material.dart';
import 'screens/configuration_screen.dart';
import 'screens/messaging_screen.dart';
import 'screens/profile_screen.dart';
import 'services/serial_communication_service.dart';
import 'providers/serial_service_provider.dart';
import 'services/profile_service.dart';
import 'services/notification_service.dart';


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.instance.initialize();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final ProfileService _profileService = ProfileService();
  Color _primaryColor = Colors.deepPurple;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    await _profileService.loadProfile();
    setState(() {
      _primaryColor = _profileService.currentProfile.primaryColor;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SerialServiceProvider(
      serialService: SerialCommunicationService(),
      child: MaterialApp(
        title: 'Serial Communication',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: _primaryColor),
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
    const ProfileScreen(),
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
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Profile',
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
