import 'package:flutter/material.dart';
import 'screens/configuration_screen.dart';
import 'screens/radar_screen.dart';
import 'screens/profile_setup_screen.dart';
import 'screens/editable_profile_screen.dart';
import 'services/serial_communication_service.dart';
import 'providers/serial_service_provider.dart';
import 'services/profile_manager.dart';
import 'services/notification_service.dart';

// User profile screen
class UserProfileScreen extends StatelessWidget {
  const UserProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final serialService = SerialServiceProvider.of(context);
    
    return EditableProfileScreen(serialService: serialService);
  }
}


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
  final SerialCommunicationService _serialService = SerialCommunicationService(); // Create ONCE!

  @override
  Widget build(BuildContext context) {
    return SerialServiceProvider(
      serialService: _serialService, // REUSE the same instance!
      child: MaterialApp(
        title: 'Serial Communication',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF128C7E)),
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
  bool _profileChecked = false;
  bool _showingProfileSetup = false;
  
  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      ConfigurationScreen(onConnectionSuccess: () async {
        // Check profile after successful connection
        await _checkProfileAfterConnection();
      }),
      const RadarScreen(),
      const UserProfileScreen(),
    ];
  }

  Future<void> _checkProfileAfterConnection() async {
    if (_profileChecked || _showingProfileSetup) {
      print('Profile check skipped: already checked or showing setup');
      return;
    }
    
    final serialService = SerialServiceProvider.of(context);
    
    print('Waiting for connection to stabilize...');
    // Wait a bit for connection to stabilize
    await Future.delayed(const Duration(milliseconds: 1500));
    
    print('Checking profile on Arduino board...');
    // Check if profile exists
    final profile = await ProfileManager.instance.checkProfile(serialService);
    
    print('Profile check result: ${profile != null ? "Found profile: $profile" : "No profile found"}');
    
    setState(() {
      _profileChecked = true;
    });
    
    if (profile == null && mounted && !_showingProfileSetup) {
      // No profile exists, show setup screen
      print('Showing profile setup screen...');
      setState(() {
        _showingProfileSetup = true;
      });
      
      if (mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ProfileSetupScreen(
              serialService: serialService,
              onProfileSaved: () {
                // This will be called from the setup screen
                print('Profile saved callback triggered');
              },
            ),
          ),
        );
        
        print('Profile setup screen closed');
        setState(() {
          _showingProfileSetup = false;
          _currentIndex = 1; // Navigate to Radar screen after setup
        });
      }
    } else if (profile != null) {
      // Profile exists, just navigate to Radar
      print('Navigating to Radar screen...');
      setState(() {
        _currentIndex = 1;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFF128C7E),
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Config',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.radar),
            label: 'Radar',
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
