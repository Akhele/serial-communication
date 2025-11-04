import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/serial_communication_service.dart';
import '../providers/serial_service_provider.dart';
import '../models/chat_message.dart';
import '../services/profile_service.dart';
import '../services/notification_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'dart:io';
import 'dart:convert';
import 'package:just_audio/just_audio.dart';

class MessagingScreen extends StatefulWidget {
  const MessagingScreen({super.key});

  @override
  State<MessagingScreen> createState() => _MessagingScreenState();
}

class _MessagingScreenState extends State<MessagingScreen> {
  SerialCommunicationService? _serialService;
  final ProfileService _profileService = ProfileService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  
  final List<ChatMessage> _messages = [];
  bool _isConnected = false;
  bool _autoScroll = true;
  String _filterText = '';
  bool _isRecording = false;
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _currentRecordingPath;
  Stopwatch _recordStopwatch = Stopwatch();

  // WhatsApp colors
  static const Color whatsappGreen = Color(0xFF25D366);
  static const Color whatsappDarkGreen = Color(0xFF128C7E);
  static const Color whatsappLightGray = Color(0xFFECE5DD);
  static const Color receivedBubbleColor = Color(0xFFFFFFFF);
  static const Color sentBubbleColor = Color(0xFFDCF8C6);

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _recorder.openRecorder();
  }

  Future<String> _saveIncomingAudio(List<int> bytes) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_serialService == null) {
      _serialService = SerialServiceProvider.of(context);
      _setupStreams();
    }
  }

  Future<void> _loadProfile() async {
    await _profileService.loadProfile();
  }

  void _setupStreams() {
    _serialService?.dataStream.listen((data) {
      // Parse received data to extract username if present
      final messageData = data.trim();
      print('App: Received raw data (length=${messageData.length}): "${messageData.substring(0, messageData.length > 100 ? 100 : messageData.length)}..."');
      String? parsedUsername;
      String parsedContent = messageData;

      // Check if message contains username format: "username:message"
      if (messageData.contains(':') && messageData.indexOf(':') < messageData.length - 1) {
        final parts = messageData.split(':');
        if (parts.length >= 2) {
          parsedUsername = parts[0].trim();
          parsedContent = parts.sublist(1).join(':').trim();
        }
      }

      print('App: Parsed - username="$parsedUsername", content length=${parsedContent.length}');

      // Detect audio payload: AUDIO_B64:<durationMs>:<base64>
      if (parsedContent.startsWith('AUDIO_B64:')) {
        print('App: Detected AUDIO_B64 payload');
        try {
          final rest = parsedContent.substring('AUDIO_B64:'.length);
          final idx = rest.indexOf(':');
          if (idx < 0) {
            print('App: ERROR - Missing second colon in AUDIO_B64');
            throw Exception('Invalid AUDIO_B64 format');
          }
          final durationMs = int.tryParse(rest.substring(0, idx)) ?? 0;
          final b64 = rest.substring(idx + 1);
          print('App: Decoding audio - duration=$durationMs ms, base64 length=${b64.length}');
          final bytes = base64Decode(b64);
          print('App: Decoded ${bytes.length} bytes, saving to file...');
          _saveIncomingAudio(bytes).then((path) {
            print('App: Audio saved to $path, adding to messages');
            setState(() {
              _messages.add(ChatMessage.audioReceived(path, durationMs, username: parsedUsername));
            });
            if (_autoScroll) _scrollToBottom();
          });
        } catch (e) {
          print('App: ERROR decoding audio: $e');
          setState(() {
            _messages.add(ChatMessage.received('[Error: Invalid audio] $parsedContent', username: parsedUsername));
          });
        }
      } else {
        print('App: Regular text message');
        setState(() {
          _messages.add(ChatMessage.received(parsedContent, username: parsedUsername));
        });
      }

      // Push local notification for the received message
      final title = 'New message' + (parsedUsername != null && parsedUsername.isNotEmpty ? ' from $parsedUsername' : '');
      // For audio, show generic body
      final notifBody = parsedContent.startsWith('AUDIO_B64:') ? 'Voice message' : parsedContent;
      NotificationService.instance.showMessageNotification(title: title, body: notifBody);
      if (_autoScroll) _scrollToBottom();
    });

    _serialService?.connectionStream.listen((isConnected) {
      setState(() {
        _isConnected = isConnected;
      });
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty || _serialService == null) return;

    final messageText = _messageController.text.trim();
    final username = _profileService.currentProfile.username;
    _messageController.clear();
    _focusNode.unfocus();

    // Add sent message immediately for better UX
    setState(() {
      _messages.add(ChatMessage.sent(messageText, username: username));
    });
    if (_autoScroll) _scrollToBottom();

    // Send message with username prefix
    final messageWithUsername = '$username:$messageText';
    final success = await _serialService!.sendData('$messageWithUsername\n');
    if (!success) {
      // Remove the message if sending failed
      setState(() {
        _messages.removeLast();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to send message')),
      );
    }
  }

  Future<void> _toggleRecord() async {
    if (_isRecording) {
      await _stopAndSendAudio();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    if (await Permission.microphone.request().isDenied) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Microphone permission denied')));
      return;
    }
    final dir = await getTemporaryDirectory();
    _currentRecordingPath = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    final canRecord = await Permission.microphone.isGranted || await Permission.microphone.request().isGranted;
    if (!canRecord) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Recording not permitted')));
      return;
    }
    await _recorder.startRecorder(
      toFile: _currentRecordingPath!,
      codec: Codec.aacMP4,
      bitRate: 16000,  // Very low bitrate for maximum compression (voice quality)
      sampleRate: 16000,  // Lower sample rate (good enough for voice)
    );
    setState(() { _isRecording = true; });
    _recordStopwatch..reset()..start();
  }

  Future<void> _stopAndSendAudio() async {
    try {
      final path = await _recorder.stopRecorder();
      _recordStopwatch.stop();
      setState(() { _isRecording = false; });
      if (path == null) return;
      final file = File(path);
      if (!(await file.exists())) return;
      final bytes = await file.readAsBytes();
      
      // Compress/limit audio size for LoRa transmission
      final sizeKB = bytes.length / 1024;
      print('Audio: recorded ${bytes.length} bytes (${sizeKB.toStringAsFixed(1)} KB)');
      
      // Warn if audio is too large
      if (bytes.length > 10000) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Audio is large (${sizeKB.toStringAsFixed(1)} KB). Transmission may take time.')),
        );
      }
      
      final b64 = base64Encode(bytes);
      final durationMs = _recordStopwatch.elapsedMilliseconds;
      final username = _profileService.currentProfile.username;
      
      print('Audio: base64 length=${b64.length}, estimated segments=${(b64.length / 200).ceil()}');

      // Add to UI immediately
      setState(() {
        _messages.add(ChatMessage.audioSent(path, durationMs, username: username));
      });
      if (_autoScroll) _scrollToBottom();

      // Send as AUDIO_B64
      final payload = '$username:AUDIO_B64:$durationMs:$b64\n';
      final success = await _serialService!.sendData(payload);
      if (!success) {
        // revert UI
        setState(() { _messages.removeLast(); });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to send audio')));
      } else {
        print('Audio: sent successfully');
      }
    } catch (e) {
      print('Audio: ERROR during send - $e');
      setState(() { _isRecording = false; });
    }
  }

  void _clearMessages() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Clear Messages'),
        content: const Text('Are you sure you want to clear all messages?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _messages.clear();
              });
              Navigator.of(context).pop();
            },
            child: Text('Clear', style: TextStyle(color: whatsappDarkGreen)),
          ),
        ],
      ),
    );
  }

  void _exportMessages() {
    if (_messages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No messages to export')),
      );
      return;
    }

    final buffer = StringBuffer();
    buffer.writeln('Serial Communication Log');
    buffer.writeln('Generated: ${DateTime.now()}');
    buffer.writeln('Total Messages: ${_messages.length}');
    buffer.writeln('=' * 50);
    
    for (final message in _messages) {
      buffer.writeln('[${message.formattedDateTime}] ${message.type.name.toUpperCase()}: ${message.content}');
    }

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Messages copied to clipboard')),
    );
  }

  List<ChatMessage> get _filteredMessages {
    if (_filterText.isEmpty) return _messages;
    return _messages.where((message) => 
      message.content.toLowerCase().contains(_filterText.toLowerCase())
    ).toList();
  }

  String _getInitials(String name) {
    if (name.isEmpty) return '?';
    final parts = name.split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.substring(0, 1).toUpperCase();
  }

  Color _getAvatarColor(String name) {
    final colors = [
      const Color(0xFF128C7E),
      const Color(0xFF25D366),
      const Color(0xFF34B7F1),
      const Color(0xFF075E54),
      const Color(0xFF128C7E),
    ];
    return colors[name.hashCode.abs() % colors.length];
  }

  bool _shouldShowAvatar(int index) {
    if (index == 0) return true;
    final current = _filteredMessages[index];
    final previous = _filteredMessages[index - 1];
    return current.type != previous.type || 
           current.username != previous.username ||
           current.timestamp.difference(previous.timestamp).inMinutes > 5;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: whatsappLightGray,
      appBar: AppBar(
        backgroundColor: whatsappDarkGreen,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'LoRa Chat',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              _isConnected ? 'Connected' : 'Disconnected',
              style: TextStyle(
                color: Colors.white.withOpacity(0.8),
                fontSize: 12,
              ),
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: _isConnected ? Colors.green : Colors.red,
              shape: BoxShape.circle,
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            color: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            onSelected: (value) {
              switch (value) {
                case 'export':
                  _exportMessages();
                  break;
                case 'clear':
                  _clearMessages();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'export',
                child: Row(
                  children: [
                    Icon(Icons.download, size: 20),
                    SizedBox(width: 12),
                    Text('Export Messages'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(Icons.clear_all, size: 20, color: Colors.red),
                    const SizedBox(width: 12),
                    const Text('Clear Messages', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Messages List
          Expanded(
            child: _filteredMessages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _messages.isEmpty ? Icons.chat_bubble_outline : Icons.search_off,
                          size: 64,
                          color: Colors.grey.withOpacity(0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _messages.isEmpty 
                              ? 'No messages yet.\nConnect a device and start chatting!'
                              : 'No messages match your filter.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.grey.withOpacity(0.7),
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: _filteredMessages.length,
                      itemBuilder: (context, index) {
                        final message = _filteredMessages[index];
                        final isReceived = message.type == MessageType.received;
                        final showAvatar = _shouldShowAvatar(index);
                        
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          child: Row(
                            mainAxisAlignment: isReceived 
                                ? MainAxisAlignment.start 
                                : MainAxisAlignment.end,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (isReceived && showAvatar) ...[
                                Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: _getAvatarColor(message.displayName),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: Text(
                                      _getInitials(message.displayName),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                              ] else if (isReceived) ...[
                                const SizedBox(width: 38),
                              ],
                              
                              Flexible(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isReceived ? receivedBubbleColor : sentBubbleColor,
                                    borderRadius: BorderRadius.only(
                                      topLeft: const Radius.circular(8),
                                      topRight: const Radius.circular(8),
                                      bottomLeft: Radius.circular(isReceived ? 2 : 8),
                                      bottomRight: Radius.circular(isReceived ? 8 : 2),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: isReceived 
                                        ? CrossAxisAlignment.start 
                                        : CrossAxisAlignment.end,
                                    children: [
                                      if (isReceived && showAvatar) ...[
                                        Text(
                                          message.displayName,
                                          style: TextStyle(
                                            color: whatsappDarkGreen,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                      ],
                                      if (message.type == MessageType.audioSent || message.type == MessageType.audioReceived) ...[
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon: const Icon(Icons.play_arrow),
                                              onPressed: () async {
                                                if (message.audioFilePath != null) {
                                                  try {
                                                    await _audioPlayer.setFilePath(message.audioFilePath!);
                                                    await _audioPlayer.play();
                                                  } catch (_) {}
                                                }
                                              },
                                            ),
                                            Text(message.content),
                                          ],
                                        ),
                                      ] else ...[
                                        Text(
                                          message.content,
                                          style: const TextStyle(
                                            fontSize: 15,
                                            color: Color(0xFF111B21),
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 2),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            message.formattedTime,
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey[600],
                                            ),
                                          ),
                                          if (!isReceived) ...[
                                            const SizedBox(width: 4),
                                            Icon(
                                              Icons.done_all,
                                              size: 14,
                                              color: Colors.grey[600],
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              
                              if (!isReceived) 
                                const SizedBox(width: 38),
                            ],
                          ),
                        );
                      },
                    ),
          ),
          
          // Input Field
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: SafeArea(
              child: Row(
                children: [
                  // Record button
                  Container(
                    decoration: BoxDecoration(
                      color: _isRecording ? Colors.red : Colors.grey.shade200,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: Icon(_isRecording ? Icons.stop : Icons.mic, color: _isRecording ? Colors.white : Colors.black87),
                      onPressed: _isConnected ? _toggleRecord : null,
                      tooltip: _isRecording ? 'Stop' : 'Record',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.grey.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _messageController,
                              focusNode: _focusNode,
                              decoration: const InputDecoration(
                                hintText: 'Type a message',
                                border: InputBorder.none,
                                hintStyle: TextStyle(color: Colors.grey),
                              ),
                              maxLines: null,
                              textCapitalization: TextCapitalization.sentences,
                              enabled: _isConnected,
                            ),
                          ),
                          // Emoji icon removed
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: _isConnected ? whatsappGreen : Colors.grey,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.send, color: Colors.white),
                      onPressed: _isConnected ? _sendMessage : null,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // No in-app emoji picker; use system keyboard emojis
        ],
      ),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _audioPlayer.dispose();
    _recorder.closeRecorder();
    super.dispose();
  }
}
