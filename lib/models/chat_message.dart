class ChatMessage {
  final String content;
  final DateTime timestamp;
  final MessageType type;
  final String? senderId;

  ChatMessage({
    required this.content,
    required this.timestamp,
    required this.type,
    this.senderId,
  });

  factory ChatMessage.sent(String content) {
    return ChatMessage(
      content: content,
      timestamp: DateTime.now(),
      type: MessageType.sent,
    );
  }

  factory ChatMessage.received(String content, {String? senderId}) {
    return ChatMessage(
      content: content,
      timestamp: DateTime.now(),
      type: MessageType.received,
      senderId: senderId,
    );
  }

  String get formattedTime {
    return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
  }

  String get formattedDateTime {
    return '${timestamp.day}/${timestamp.month}/${timestamp.year} ${formattedTime}';
  }
}

enum MessageType {
  sent,
  received,
}
