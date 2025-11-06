class UserProfile {
  final String username;
  final int avatarId;

  const UserProfile({
    required this.username,
    required this.avatarId,
  });

  // Factory constructor for default profile
  factory UserProfile.defaultProfile() {
    return const UserProfile(
      username: 'User',
      avatarId: 0,
    );
  }

  // Parse from Arduino response: "username:avatarId"
  factory UserProfile.fromString(String data) {
    final parts = data.split(':');
    if (parts.length >= 2) {
      return UserProfile(
        username: parts[0],
        avatarId: int.tryParse(parts[1]) ?? 0,
      );
    }
    return UserProfile(username: 'Unknown', avatarId: 0);
  }

  // Parse from JSON (for SharedPreferences)
  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      username: json['username'] as String? ?? 'User',
      avatarId: json['avatarId'] as int? ?? 0,
    );
  }

  // Convert to JSON (for SharedPreferences)
  Map<String, dynamic> toJson() {
    return {
      'username': username,
      'avatarId': avatarId,
    };
  }

  // Convert to Arduino command
  String toCommand() {
    return 'SAVE_PROFILE:$username:$avatarId';
  }

  @override
  String toString() => 'UserProfile(username: $username, avatarId: $avatarId)';
}
