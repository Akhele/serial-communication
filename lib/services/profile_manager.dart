import 'dart:async';
import '../models/user_profile.dart';
import 'serial_communication_service.dart';

class ProfileManager {
  static final ProfileManager instance = ProfileManager._();
  ProfileManager._();

  UserProfile? _currentProfile;
  UserProfile? get currentProfile => _currentProfile;

  bool _profileChecked = false;
  bool get profileChecked => _profileChecked;

  final _profileController = StreamController<UserProfile?>.broadcast();
  Stream<UserProfile?> get profileStream => _profileController.stream;

  /// Check if a profile exists on the Arduino board
  Future<UserProfile?> checkProfile(SerialCommunicationService serialService) async {
    print('ProfileManager: Requesting profile from Arduino...');
    
    // Set up a completer to wait for response
    final completer = Completer<UserProfile?>();
    StreamSubscription? subscription;
    
    // Listen for profile response
    subscription = serialService.dataStream.listen((data) {
      final message = data.trim();
      print('ProfileManager: Received message: $message');
      
      if (message.startsWith('PROFILE:')) {
        if (message == 'PROFILE:NONE') {
          print('ProfileManager: No profile found on board');
          if (!completer.isCompleted) {
            completer.complete(null);
          }
        } else {
          // Parse: PROFILE:username:avatarId
          final profileData = message.substring(8); // Skip "PROFILE:"
          final profile = UserProfile.fromString(profileData);
          print('ProfileManager: Profile found - $profile');
          _currentProfile = profile;
          _profileController.add(profile);
          if (!completer.isCompleted) {
            completer.complete(profile);
          }
        }
        subscription?.cancel();
      }
    });
    
    // Send GET_PROFILE command
    try {
      await serialService.sendData('GET_PROFILE\n');
      
      // Wait for response with timeout
      final profile = await completer.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          print('ProfileManager: Timeout waiting for profile response');
          return null;
        },
      );
      
      _profileChecked = true;
      return profile;
    } catch (e) {
      print('ProfileManager: Error checking profile - $e');
      subscription.cancel();
      _profileChecked = true;
      return null;
    }
  }

  /// Save a new profile to the Arduino board
  Future<bool> saveProfile(UserProfile profile, SerialCommunicationService serialService) async {
    print('ProfileManager: Saving profile - $profile');
    
    try {
      final command = '${profile.toCommand()}\n';
      await serialService.sendData(command);
      
      // Wait a bit for Arduino to save
      await Future.delayed(const Duration(milliseconds: 500));
      
      _currentProfile = profile;
      _profileController.add(profile);
      
      print('ProfileManager: Profile saved successfully');
      return true;
    } catch (e) {
      print('ProfileManager: Error saving profile - $e');
      return false;
    }
  }

  void dispose() {
    _profileController.close();
  }
}

