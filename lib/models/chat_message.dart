class ChatMessage {
  final String content;
  final DateTime timestamp;
  final MessageType type;
  final String? senderId;
  final String? username;

  ChatMessage({
    required this.content,
    required this.timestamp,
    required this.type,
    this.senderId,
    this.username,
  });

  factory ChatMessage.sent(String content, {String? username}) {
    return ChatMessage(
      content: content,
      timestamp: DateTime.now(),
      type: MessageType.sent,
      username: username,
    );
  }

  factory ChatMessage.received(String content, {String? senderId, String? username}) {
    return ChatMessage(
      content: content,
      timestamp: DateTime.now(),
      type: MessageType.received,
      senderId: senderId,
      username: username,
    );
  }

  String get formattedTime {
    return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
  }

  String get formattedDateTime {
    return '${timestamp.day}/${timestamp.month}/${timestamp.year} ${formattedTime}';
  }

  String get displayName {
    if (username != null && username!.isNotEmpty) {
      return username!;
    }
    return type == MessageType.sent ? 'You' : 'Unknown';
  }
}

enum MessageType {
  sent,
  received,
}
