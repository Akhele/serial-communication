import 'package:flutter/material.dart';
import '../models/avatar.dart';
import '../models/user_profile.dart';
import '../services/serial_communication_service.dart';
import '../services/profile_manager.dart';

class ProfileSetupScreen extends StatefulWidget {
  final SerialCommunicationService serialService;
  final VoidCallback onProfileSaved;

  const ProfileSetupScreen({
    Key? key,
    required this.serialService,
    required this.onProfileSaved,
  }) : super(key: key);

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final TextEditingController _usernameController = TextEditingController();
  int _selectedAvatarId = 0;
  bool _isSaving = false;

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    final username = _usernameController.text.trim();
    
    if (username.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a username')),
      );
      return;
    }

    if (username.length > 15) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Username must be 15 characters or less')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final profile = UserProfile(
        username: username,
        avatarId: _selectedAvatarId,
      );
      
      print('Saving profile: $username with avatar $_selectedAvatarId');
      
      // Save to ProfileManager (which saves to Arduino)
      final success = await ProfileManager.instance.saveProfile(
        profile,
        widget.serialService,
      );
      
      if (success) {
        print('Profile saved successfully!');
        
        // Notify parent callback
        widget.onProfileSaved();
        
        // Show success message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Profile saved successfully!'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 1),
            ),
          );
          
          // Wait a bit for the snackbar to show, then close this screen
          await Future.delayed(const Duration(milliseconds: 500));
          
          if (mounted) {
            Navigator.pop(context);
          }
        }
      } else {
        throw Exception('Failed to save profile to board');
      }
    } catch (e) {
      print('Error saving profile: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save profile: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Your Profile'),
        automaticallyImplyLeading: false, // No back button on first setup
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            Center(
              child: Column(
                children: [
                  Text(
                    Avatars.getById(_selectedAvatarId).emoji,
                    style: const TextStyle(fontSize: 80),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Choose Your Avatar',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            
            // Avatar Grid
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 5,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: Avatars.all.length,
              itemBuilder: (context, index) {
                final avatar = Avatars.all[index];
                final isSelected = _selectedAvatarId == avatar.id;
                
                return GestureDetector(
                  onTap: () {
                    setState(() => _selectedAvatarId = avatar.id);
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: isSelected 
                          ? Colors.blue.withOpacity(0.2)
                          : Colors.grey.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? Colors.blue : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        avatar.emoji,
                        style: const TextStyle(fontSize: 32),
                      ),
                    ),
                  ),
                );
              },
            ),
            
            const SizedBox(height: 32),
            
            // Username Input
            Text(
              'Username',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _usernameController,
              maxLength: 15,
              decoration: InputDecoration(
                hintText: 'Enter your username',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.grey.withOpacity(0.1),
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Save Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _saveProfile,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isSaving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text(
                        'Save Profile',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

