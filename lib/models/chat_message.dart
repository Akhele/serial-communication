class ChatMessage {
  final String content; // For text or audio metadata label
  final DateTime timestamp;
  final MessageType type;
  final String? senderId;
  final String? username;
  final String? audioFilePath; // if audio message
  final int? audioDurationMs; // duration in ms

  ChatMessage({
    required this.content,
    required this.timestamp,
    required this.type,
    this.senderId,
    this.username,
    this.audioFilePath,
    this.audioDurationMs,
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

  factory ChatMessage.audioSent(String filePath, int durationMs, {String? username}) {
    return ChatMessage(
      content: '[Voice message] ${(durationMs / 1000).toStringAsFixed(1)}s',
      timestamp: DateTime.now(),
      type: MessageType.audioSent,
      username: username,
      audioFilePath: filePath,
      audioDurationMs: durationMs,
    );
  }

  factory ChatMessage.audioReceived(String filePath, int durationMs, {String? senderId, String? username}) {
    return ChatMessage(
      content: '[Voice message] ${(durationMs / 1000).toStringAsFixed(1)}s',
      timestamp: DateTime.now(),
      type: MessageType.audioReceived,
      senderId: senderId,
      username: username,
      audioFilePath: filePath,
      audioDurationMs: durationMs,
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
  audioSent,
  audioReceived,
}
