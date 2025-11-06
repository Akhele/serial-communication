import 'package:flutter/material.dart';
import '../models/avatar.dart';
import '../models/user_profile.dart';
import '../services/serial_communication_service.dart';
import '../services/profile_manager.dart';

class EditableProfileScreen extends StatefulWidget {
  final SerialCommunicationService serialService;

  const EditableProfileScreen({
    Key? key,
    required this.serialService,
  }) : super(key: key);

  @override
  State<EditableProfileScreen> createState() => _EditableProfileScreenState();
}

class _EditableProfileScreenState extends State<EditableProfileScreen> {
  late TextEditingController _usernameController;
  int _selectedAvatarId = 0;
  bool _isEditing = false;
  bool _isSaving = false;
  UserProfile? _currentProfile;

  @override
  void initState() {
    super.initState();
    _currentProfile = ProfileManager.instance.currentProfile;
    _usernameController = TextEditingController(
      text: _currentProfile?.username ?? '',
    );
    _selectedAvatarId = _currentProfile?.avatarId ?? 0;
    
    // Listen for profile updates
    ProfileManager.instance.profileStream.listen((profile) {
      if (mounted && profile != null) {
        setState(() {
          _currentProfile = profile;
          if (!_isEditing) {
            _usernameController.text = profile.username;
            _selectedAvatarId = profile.avatarId;
          }
        });
      }
    });
  }

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
      
      final success = await ProfileManager.instance.saveProfile(
        profile,
        widget.serialService,
      );
      
      if (success && mounted) {
        setState(() {
          _isEditing = false;
          _currentProfile = profile;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile saved successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save profile')),
        );
      }
    } catch (e) {
      print('Error saving profile: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
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
    final avatar = Avatars.getById(_selectedAvatarId);
    
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF128C7E),
        title: const Text('My Profile', style: TextStyle(color: Colors.white)),
        actions: [
          if (!_isEditing && _currentProfile != null)
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.white),
              onPressed: () {
                setState(() => _isEditing = true);
              },
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const SizedBox(height: 20),
            
            // Avatar Display/Selection
            Center(
              child: Column(
                children: [
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: const Color(0xFF128C7E),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        avatar.emoji,
                        style: const TextStyle(fontSize: 64),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (!_isEditing)
                    Text(
                      _currentProfile?.username ?? 'No Profile',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                ],
              ),
            ),
            
            if (_isEditing) ...[
              const SizedBox(height: 32),
              
              // Avatar Grid
              const Text(
                'Choose Your Avatar',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
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
              const Text(
                'Username',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
              
              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSaving ? null : () {
                        setState(() {
                          _isEditing = false;
                          _usernameController.text = _currentProfile?.username ?? '';
                          _selectedAvatarId = _currentProfile?.avatarId ?? 0;
                        });
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _saveProfile,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF128C7E),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
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
                              'Save',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(height: 40),
              
              // Profile Info (View Mode)
              if (_currentProfile != null) ...[
                _buildInfoCard(
                  'Username',
                  _currentProfile!.username,
                  Icons.person,
                ),
                const SizedBox(height: 16),
                _buildInfoCard(
                  'Avatar',
                  Avatars.getById(_currentProfile!.avatarId).name,
                  Icons.emoji_emotions,
                ),
              ] else
                const Center(
                  child: Text(
                    'No profile found.\nPlease connect to your device first.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF128C7E)),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

