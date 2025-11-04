class ChatMessage {
  final String content; // For text or audio metadata label
  final DateTime timestamp;
  final MessageType type;
  final String? senderId;
  final String? username;
  final String? audioFilePath; // if audio message
  final int? audioDurationMs; // duration in ms
  int? audioSegmentsCurrent; // current segments sent/received
  int? audioSegmentsTotal; // total segments to send/receive
  bool audioCompleted; // true when audio is fully sent/received

  ChatMessage({
    required this.content,
    required this.timestamp,
    required this.type,
    this.senderId,
    this.username,
    this.audioFilePath,
    this.audioDurationMs,
    this.audioSegmentsCurrent,
    this.audioSegmentsTotal,
    this.audioCompleted = true, // default to true for non-audio messages
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

  factory ChatMessage.audioSent(String filePath, int durationMs, {String? username, int? totalSegments}) {
    return ChatMessage(
      content: '[Voice message] ${(durationMs / 1000).toStringAsFixed(1)}s',
      timestamp: DateTime.now(),
      type: MessageType.audioSent,
      username: username,
      audioFilePath: filePath,
      audioDurationMs: durationMs,
      audioSegmentsCurrent: 0,
      audioSegmentsTotal: totalSegments,
      audioCompleted: false, // Will be updated as segments are sent
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
      audioCompleted: true, // Received audio is already complete
    );
  }
  
  // Factory for creating an audio message that's being received (with progress)
  factory ChatMessage.audioReceiving({String? senderId, String? username, int? totalSegments}) {
    final displayText = username != null && username.isNotEmpty 
        ? '[Receiving voice message from $username...]'
        : '[Receiving voice message...]';
    return ChatMessage(
      content: displayText,
      timestamp: DateTime.now(),
      type: MessageType.audioReceiving,
      senderId: senderId,
      username: username,
      audioSegmentsCurrent: 0,
      audioSegmentsTotal: totalSegments,
      audioCompleted: false,
    );
  }
  
  double? get audioProgress {
    if (audioSegmentsTotal == null || audioSegmentsTotal == 0 || audioSegmentsCurrent == null) {
      return null;
    }
    return audioSegmentsCurrent! / audioSegmentsTotal!;
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
  audioReceiving, // Audio being received with progress
}
