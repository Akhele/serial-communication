import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_profile.dart';

class ProfileService {
  static const String _profileKey = 'user_profile';
  UserProfile? _currentProfile;

  UserProfile get currentProfile {
    _currentProfile ??= UserProfile.defaultProfile();
    return _currentProfile!;
  }

  Future<void> loadProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final profileJson = prefs.getString(_profileKey);
      
      if (profileJson != null) {
        final profileData = jsonDecode(profileJson) as Map<String, dynamic>;
        _currentProfile = UserProfile.fromJson(profileData);
      } else {
        _currentProfile = UserProfile.defaultProfile();
        await saveProfile();
      }
    } catch (e) {
      print('Error loading profile: $e');
      _currentProfile = UserProfile.defaultProfile();
    }
  }

  Future<void> saveProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final profileJson = jsonEncode(_currentProfile!.toJson());
      await prefs.setString(_profileKey, profileJson);
    } catch (e) {
      print('Error saving profile: $e');
    }
  }

  Future<void> updateProfile(UserProfile newProfile) async {
    _currentProfile = newProfile;
    await saveProfile();
  }

  Future<void> resetProfile() async {
    _currentProfile = UserProfile.defaultProfile();
    await saveProfile();
  }
}
