import 'package:flutter/material.dart';

class UserProfile {
  final String username;
  final String? displayName;
  final String? email;
  final int primaryColorValue;
  final DateTime createdAt;
  DateTime updatedAt;

  UserProfile({
    required this.username,
    this.displayName,
    this.email,
    required this.primaryColorValue,
    required this.createdAt,
    required this.updatedAt,
  });

  factory UserProfile.defaultProfile() {
    final now = DateTime.now();
    return UserProfile(
      username: 'User${now.millisecondsSinceEpoch % 10000}',
      displayName: 'Serial User',
      primaryColorValue: 0xFF673AB7, // Deep Purple
      createdAt: now,
      updatedAt: now,
    );
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      username: json['username'] ?? 'Unknown',
      displayName: json['displayName'],
      email: json['email'],
      primaryColorValue: json['primaryColorValue'] ?? 0xFF673AB7,
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: DateTime.parse(json['updatedAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'username': username,
      'displayName': displayName,
      'email': email,
      'primaryColorValue': primaryColorValue,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  UserProfile copyWith({
    String? username,
    String? displayName,
    String? email,
    int? primaryColorValue,
  }) {
    return UserProfile(
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      primaryColorValue: primaryColorValue ?? this.primaryColorValue,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }

  Color get primaryColor => Color(primaryColorValue);
}
