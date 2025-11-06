import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat_message.dart';

class ChatStorageService {
  static final ChatStorageService instance = ChatStorageService._internal();
  ChatStorageService._internal();

  static const String _conversationsPrefix = 'conversation_';
  static const int _maxMessagesPerConversation = 500; // Limit to prevent storage overflow

  /// Save a message to a specific conversation
  Future<void> saveMessage(String userId, ChatMessage message) async {
    final messages = await getConversation(userId);
    messages.add(message);
    
    // Keep only the latest messages to prevent storage bloat
    if (messages.length > _maxMessagesPerConversation) {
      messages.removeRange(0, messages.length - _maxMessagesPerConversation);
    }
    
    await _saveConversation(userId, messages);
  }

  /// Get all messages for a specific user
  Future<List<ChatMessage>> getConversation(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _conversationsPrefix + userId;
    final jsonString = prefs.getString(key);
    
    if (jsonString == null || jsonString.isEmpty) {
      return [];
    }
    
    try {
      final List<dynamic> jsonList = json.decode(jsonString);
      return jsonList.map((json) => _chatMessageFromJson(json)).toList();
    } catch (e) {
      print('ChatStorage: Error loading conversation for $userId: $e');
      return [];
    }
  }

  /// Save entire conversation for a user
  Future<void> _saveConversation(String userId, List<ChatMessage> messages) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _conversationsPrefix + userId;
    final jsonList = messages.map((msg) => _chatMessageToJson(msg)).toList();
    final jsonString = json.encode(jsonList);
    await prefs.setString(key, jsonString);
  }

  /// Delete conversation for a specific user
  Future<void> deleteConversation(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _conversationsPrefix + userId;
    await prefs.remove(key);
  }

  /// Get all users with saved conversations
  Future<List<String>> getAllConversationUserIds() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    return keys
        .where((key) => key.startsWith(_conversationsPrefix))
        .map((key) => key.substring(_conversationsPrefix.length))
        .toList();
  }

  /// Get last message for a user (for conversation list preview)
  Future<ChatMessage?> getLastMessage(String userId) async {
    final messages = await getConversation(userId);
    if (messages.isEmpty) return null;
    return messages.last;
  }

  /// Clear all conversations
  Future<void> clearAllConversations() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = await getAllConversationUserIds();
    for (final userId in keys) {
      await prefs.remove(_conversationsPrefix + userId);
    }
  }

  /// Convert ChatMessage to JSON
  Map<String, dynamic> _chatMessageToJson(ChatMessage message) {
    return {
      'content': message.content,
      'timestamp': message.timestamp.toIso8601String(),
      'type': message.type.toString(),
      'senderId': message.senderId,
      'username': message.username,
      'audioFilePath': message.audioFilePath,
      'audioDurationMs': message.audioDurationMs,
      'audioSegmentsCurrent': message.audioSegmentsCurrent,
      'audioSegmentsTotal': message.audioSegmentsTotal,
      'audioCompleted': message.audioCompleted,
    };
  }

  /// Convert JSON to ChatMessage
  ChatMessage _chatMessageFromJson(Map<String, dynamic> json) {
    return ChatMessage(
      content: json['content'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      type: _messageTypeFromString(json['type'] as String),
      senderId: json['senderId'] as String?,
      username: json['username'] as String?,
      audioFilePath: json['audioFilePath'] as String?,
      audioDurationMs: json['audioDurationMs'] as int?,
      audioSegmentsCurrent: json['audioSegmentsCurrent'] as int?,
      audioSegmentsTotal: json['audioSegmentsTotal'] as int?,
      audioCompleted: json['audioCompleted'] as bool? ?? true,
    );
  }

  MessageType _messageTypeFromString(String typeString) {
    switch (typeString) {
      case 'MessageType.sent':
        return MessageType.sent;
      case 'MessageType.received':
        return MessageType.received;
      case 'MessageType.audioSent':
        return MessageType.audioSent;
      case 'MessageType.audioReceived':
        return MessageType.audioReceived;
      case 'MessageType.audioReceiving':
        return MessageType.audioReceiving;
      default:
        return MessageType.received;
    }
  }
}

