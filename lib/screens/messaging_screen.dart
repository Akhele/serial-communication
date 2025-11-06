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
import 'dart:async';
import 'package:just_audio/just_audio.dart';
import 'package:archive/archive.dart';

class MessagingScreen extends StatefulWidget {
  final String? targetUsername;
  
  const MessagingScreen({super.key, this.targetUsername});

  @override
  State<MessagingScreen> createState() => _MessagingScreenState();
}

class _MessagingScreenState extends State<MessagingScreen> with SingleTickerProviderStateMixin {
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
  Timer? _recordingTimer;
  String _recordingDuration = '0:00.0';
  double _recordingSwipeOffset = 0.0;
  bool _recordingCancelled = false;
  double _recordingStartX = 0.0;
  
  // Animation for smooth progress bar updates
  late AnimationController _progressAnimationController;
  Timer? _segmentProgressTimer;
  int _estimatedTotalSegments = 0;
  int _currentAnimatedSegment = 0;

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
    
    // Initialize animation controller for progress value storage
    _progressAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
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
    // Send username to Arduino for beacon broadcasting
    if (_serialService != null) {
      final username = _profileService.currentProfile.username;
      await _serialService!.sendData('SET_USERNAME:$username\n');
    }
  }

  void _setupStreams() {
    _serialService?.dataStream.listen((data) {
      // Parse received data to extract username if present
      final messageData = data.trim();
      
      // PARSE PROGRESS MESSAGES FROM ARDUINO
      // TX progress: "TX seg 1/3 len=233" or "TX seg 1/3 [R1] len=233"
      if (messageData.startsWith('TX seg ')) {
        // Ignore retry messages (they have [R1], [R2], etc.) - only track first pass
        if (!messageData.contains('[R')) {
          final match = RegExp(r'TX seg (\d+)/(\d+)').firstMatch(messageData);
          if (match != null) {
            final current = int.parse(match.group(1)!);
            final total = int.parse(match.group(2)!);
            _updateSendingProgress(current, total);
          }
        }
        return; // Don't process as a message
      }
      
      // RX progress: "Audio RX: seg 1/3 (1/3)"
      if (messageData.startsWith('Audio RX: seg ')) {
        final match = RegExp(r'Audio RX: seg (\d+)/(\d+)').firstMatch(messageData);
        if (match != null) {
          final current = int.parse(match.group(1)!);
          final total = int.parse(match.group(2)!);
          _updateReceivingProgress(current, total);
        }
        return; // Don't process as a message
      }
      
      // Audio receiving start: "LoRa Audio: Starting new audio assembly"
      if (messageData.contains('Starting new audio assembly')) {
        // Extract username from the message: "username=XXX"
        String? senderUsername;
        final usernameMatch = RegExp(r'username=([^,\n]+)').firstMatch(messageData);
        if (usernameMatch != null) {
          senderUsername = usernameMatch.group(1)?.trim();
        }
        
        final totalMatch = RegExp(r'total=(\d+)').firstMatch(messageData);
        if (totalMatch != null) {
          final total = int.parse(totalMatch.group(1)!);
          _startReceivingAudio(total, senderUsername);
          
          // Show notification immediately when first segment is detected
          NotificationService.instance.showMessageNotification(
            title: 'Receiving voice message',
            body: senderUsername != null && senderUsername.isNotEmpty 
                ? 'Voice message from $senderUsername'
                : 'Incoming voice message',
          );
        }
        return;
      }
      
      // Audio sending start: "Audio: segmenting into 3 chunks"
      if (messageData.startsWith('Audio: segmenting into ')) {
        final match = RegExp(r'segmenting into (\d+) chunks').firstMatch(messageData);
        if (match != null) {
          final total = int.parse(match.group(1)!);
          // Initialize the sending progress tracking
          _initSendingProgress(total);
        }
        return;
      }
      
      // Filter out Arduino debug/status messages and internal frames
      if (messageData.startsWith('BLE:') || 
          messageData.startsWith('Audio:') ||
          messageData.startsWith('LoRa:') ||
          messageData.startsWith('AUDIO_SEG:') ||  // Internal audio segment frames
          messageData.startsWith('TX ') ||  // TX progress messages
          messageData.startsWith('RX ') ||  // RX progress messages
          messageData.contains('len=') ||
          messageData.contains('RSSI=') ||
          messageData.contains('SNR=') ||
          messageData.contains('assembly') ||  // "Starting new audio assembly"
          messageData.contains('Complete!') ||  // "Audio assembly Complete!"
          messageData.contains('chunks') ||  // "segmenting into X chunks"
          messageData.contains('seg ') ||  // Any segment-related message
          messageData.length < 2 ||  // Filter out very short/empty messages
          RegExp(r'^[^a-zA-Z0-9\s]+$').hasMatch(messageData)) {  // Only special characters
        return; // Don't show as chat message
      }
      
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

      // Detect audio payload: AUDIO_B64_GZIP:<durationMs>:<base64-compressed>
      if (parsedContent.startsWith('AUDIO_B64_GZIP:')) {
        print('App: Detected AUDIO_B64_GZIP payload');
        try {
          final rest = parsedContent.substring('AUDIO_B64_GZIP:'.length);
          final idx = rest.indexOf(':');
          if (idx < 0) {
            print('App: ERROR - Missing second colon in AUDIO_B64_GZIP');
            throw Exception('Invalid AUDIO_B64_GZIP format');
          }
          final durationMs = int.tryParse(rest.substring(0, idx)) ?? 0;
          final b64 = rest.substring(idx + 1);
          print('App: Decoding audio - duration=$durationMs ms, compressed base64 length=${b64.length}');
          final compressedBytes = base64Decode(b64);
          print('App: Compressed bytes=${compressedBytes.length}, decompressing...');
          
          // Decompress using GZIP
          final decompressed = GZipDecoder().decodeBytes(compressedBytes);
          print('App: Decompressed to ${decompressed.length} bytes, saving to file...');
          
          _saveIncomingAudio(decompressed).then((path) {
            print('App: Audio saved to $path, updating message');
            setState(() {
              // Find and replace the receiving message with completed audio
              final receivingIndex = _messages.indexWhere((m) => m.type == MessageType.audioReceiving);
              if (receivingIndex >= 0) {
                // Replace the receiving placeholder with completed audio
                _messages[receivingIndex] = ChatMessage.audioReceived(path, durationMs, username: parsedUsername);
                // Don't show notification here - already shown when reception started
              } else {
                // Fallback: just add it (and show notification since we didn't show one earlier)
                _messages.add(ChatMessage.audioReceived(path, durationMs, username: parsedUsername));
                final title = 'New message' + (parsedUsername != null && parsedUsername.isNotEmpty ? ' from $parsedUsername' : '');
                NotificationService.instance.showMessageNotification(title: title, body: 'Voice message');
              }
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
        
        // Push local notification for text messages only (audio has its own notification)
        final title = 'New message' + (parsedUsername != null && parsedUsername.isNotEmpty ? ' from $parsedUsername' : '');
        NotificationService.instance.showMessageNotification(title: title, body: parsedContent);
      }

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
    
    _recordStopwatch..reset()..start();
    
    // Start timer to update duration display every 100ms
    _recordingTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!_isRecording) {
        timer.cancel();
        return;
      }
      setState(() {
        final elapsed = _recordStopwatch.elapsed;
        final seconds = elapsed.inSeconds;
        final tenths = (elapsed.inMilliseconds % 1000) ~/ 100;
        _recordingDuration = '$seconds:${(elapsed.inSeconds % 60).toString().padLeft(2, '0')}.$tenths';
      });
    });
    
    setState(() { _isRecording = true; });
  }

  Future<void> _cancelRecording() async {
    try {
      _recordingTimer?.cancel();
      _recordingTimer = null;
      
      await _recorder.stopRecorder();
      _recordStopwatch.stop();
      
      // Haptic feedback
      HapticFeedback.mediumImpact();
      
      setState(() { 
        _isRecording = false;
        _recordingDuration = '0:00.0';
        _recordingSwipeOffset = 0.0;
        _recordingCancelled = false;
      });
      
      print('Audio: Recording cancelled');
      
      // Show cancellation message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Recording cancelled'),
          duration: Duration(milliseconds: 1000),
          backgroundColor: Colors.grey,
        ),
      );
    } catch (e) {
      print('Audio: ERROR during cancel - $e');
      setState(() { 
        _isRecording = false;
        _recordingDuration = '0:00.0';
        _recordingSwipeOffset = 0.0;
        _recordingCancelled = false;
      });
    }
  }

  Future<void> _stopAndSendAudio() async {
    try {
      _recordingTimer?.cancel();
      _recordingTimer = null;
      
      final path = await _recorder.stopRecorder();
      _recordStopwatch.stop();
      
      // Check minimum recording duration (at least 0.5 seconds)
      final recordingDurationMs = _recordStopwatch.elapsedMilliseconds;
      setState(() { 
        _isRecording = false;
        _recordingDuration = '0:00.0';
        _recordingSwipeOffset = 0.0;
        _recordingCancelled = false;
      });
      
      if (_recordingCancelled) {
        print('Audio: Recording was cancelled');
        return;
      }
      
      if (recordingDurationMs < 500) {
        print('Audio: Recording too short (${recordingDurationMs}ms), discarding');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Hold to record - recording too short'),
            duration: Duration(milliseconds: 1500),
          ),
        );
        return;
      }
      
      if (path == null) return;
      final file = File(path);
      if (!(await file.exists())) return;
      final bytes = await file.readAsBytes();
      
      final sizeKB = bytes.length / 1024;
      print('Audio: recorded ${bytes.length} bytes (${sizeKB.toStringAsFixed(1)} KB)');
      
      // Compress with GZIP for maximum compression
      final compressedBytes = GZipEncoder().encode(bytes);
      final compressedSizeKB = compressedBytes!.length / 1024;
      final compressionRatio = ((1 - compressedBytes.length / bytes.length) * 100).toStringAsFixed(1);
      print('Audio: compressed to ${compressedBytes.length} bytes (${compressedSizeKB.toStringAsFixed(1)} KB) - ${compressionRatio}% reduction');
      
      // Warn if compressed audio is still large
      if (compressedBytes.length > 10000) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Audio: ${compressedSizeKB.toStringAsFixed(1)} KB. Transmission may take time.')),
        );
      }
      
      final b64 = base64Encode(compressedBytes);
      final durationMs = _recordStopwatch.elapsedMilliseconds;
      final username = _profileService.currentProfile.username;
      
      print('Audio: compressed base64 length=${b64.length}');

      // Calculate estimated segments based on base64 length (200 chars per segment)
      _estimatedTotalSegments = (b64.length / 200).ceil();
      
      // Add to UI immediately
      setState(() {
        _messages.add(ChatMessage.audioSent(path, durationMs, username: username, totalSegments: _estimatedTotalSegments));
      });
      if (_autoScroll) _scrollToBottom();
      
      // Start proactive progress animation based on estimated segments
      _startSegmentProgressAnimation(_estimatedTotalSegments);

      // Send as AUDIO_B64_GZIP (compressed)
      final payload = '$username:AUDIO_B64_GZIP:$durationMs:$b64\n';
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

  // Start receiving audio - add placeholder message
  void _startReceivingAudio(int totalSegments, String? username) {
    setState(() {
      // Check if we already have a receiving message
      final existingIndex = _messages.indexWhere((m) => m.type == MessageType.audioReceiving);
      if (existingIndex < 0) {
        _messages.add(ChatMessage.audioReceiving(totalSegments: totalSegments, username: username));
        if (_autoScroll) _scrollToBottom();
      }
    });
  }
  
  // Start proactive progress animation based on estimated segments
  void _startSegmentProgressAnimation(int totalSegments) {
    _segmentProgressTimer?.cancel();
    _currentAnimatedSegment = 0;
    _progressAnimationController.value = 0.0;
    
    // Create a timer that increments progress conservatively
    // Each segment: 600ms Arduino delay + 300ms BLE/LoRa overhead + 400ms safety = 1300ms
    _segmentProgressTimer = Timer.periodic(const Duration(milliseconds: 1300), (timer) {
      _currentAnimatedSegment++;
      
      // Stop at 95% to ensure we never reach 100% before transmission actually completes
      final maxSegment = (totalSegments * 0.95).round();
      if (_currentAnimatedSegment >= maxSegment) {
        _currentAnimatedSegment = maxSegment;
        timer.cancel();
      }
      
      // Update progress bar
      final progress = _currentAnimatedSegment / totalSegments;
      _progressAnimationController.value = progress;
      
      // Force UI update
      setState(() {});
    });
  }
  
  // Initialize sending progress (called when Arduino confirms actual segment count)
  void _initSendingProgress(int total) {
    // If actual total differs from estimate, update it
    if (total != _estimatedTotalSegments) {
      _estimatedTotalSegments = total;
      _segmentProgressTimer?.cancel();
      _startSegmentProgressAnimation(total);
    }
    
    // Update the segment total in the message
    setState(() {
      for (int i = _messages.length - 1; i >= 0; i--) {
        if (_messages[i].type == MessageType.audioSent && !_messages[i].audioCompleted) {
          final oldMessage = _messages[i];
          _messages[i] = ChatMessage(
            content: oldMessage.content,
            timestamp: oldMessage.timestamp,
            type: oldMessage.type,
            username: oldMessage.username,
            audioFilePath: oldMessage.audioFilePath,
            audioDurationMs: oldMessage.audioDurationMs,
            audioSegmentsCurrent: 0,
            audioSegmentsTotal: total,
            audioCompleted: false,
          );
          break;
        }
      }
    });
  }
  
  // Update sending progress - actual segment confirmations
  void _updateSendingProgress(int current, int total) {
    // Sync animated segment with actual progress (in case they drift)
    if (current > _currentAnimatedSegment) {
      _currentAnimatedSegment = current;
      _progressAnimationController.value = current / total;
    }
    
    // If this is the last segment, stop timer and mark as complete
    if (current >= total) {
      _segmentProgressTimer?.cancel();
      _progressAnimationController.value = 1.0;
      
      Future.delayed(const Duration(milliseconds: 500), () {
        setState(() {
          for (int j = _messages.length - 1; j >= 0; j--) {
            if (_messages[j].type == MessageType.audioSent && 
                !_messages[j].audioCompleted) {
              final msg = _messages[j];
              _messages[j] = ChatMessage(
                content: msg.content,
                timestamp: msg.timestamp,
                type: msg.type,
                username: msg.username,
                audioFilePath: msg.audioFilePath,
                audioDurationMs: msg.audioDurationMs,
                audioSegmentsCurrent: total,
                audioSegmentsTotal: total,
                audioCompleted: true,
              );
              break;
            }
          }
        });
      });
    }
  }
  
  // Update receiving progress
  void _updateReceivingProgress(int current, int total) {
    setState(() {
      // Find the audio receiving message
      for (int i = _messages.length - 1; i >= 0; i--) {
        if (_messages[i].type == MessageType.audioReceiving) {
          // Create a new message object with updated progress values
          final oldMessage = _messages[i];
          _messages[i] = ChatMessage(
            content: oldMessage.content,
            timestamp: oldMessage.timestamp,
            type: oldMessage.type,
            username: oldMessage.username,
            audioFilePath: oldMessage.audioFilePath,
            audioDurationMs: oldMessage.audioDurationMs,
            audioSegmentsCurrent: current,
            audioSegmentsTotal: total,
            audioCompleted: oldMessage.audioCompleted,
          );
          break;
        }
      }
    });
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
                        final isReceived = message.type == MessageType.received || 
                                          message.type == MessageType.audioReceived || 
                                          message.type == MessageType.audioReceiving;
                        final showAvatar = _shouldShowAvatar(index);
                        
                        return Padding(
                          padding: EdgeInsets.only(
                            left: 8,
                            right: isReceived ? 8 : 4,  // Small right padding for sent messages
                            top: 2,
                            bottom: 2,
                          ),
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
                              
                              if (isReceived)
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
                                      if (message.type == MessageType.audioSent || message.type == MessageType.audioReceived || message.type == MessageType.audioReceiving) ...[
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                if (message.type != MessageType.audioReceiving)
                                                  Container(
                                                    decoration: BoxDecoration(
                                                      color: message.type == MessageType.audioSent 
                                                        ? const Color(0xFF005C4B).withOpacity(0.15)
                                                        : const Color(0xFF0088CC).withOpacity(0.15),
                                                      shape: BoxShape.circle,
                                                    ),
                                                    child: IconButton(
                                                      icon: Icon(
                                                        message.type == MessageType.audioSent 
                                                          ? Icons.mic 
                                                          : Icons.play_arrow,
                                                        color: message.type == MessageType.audioSent 
                                                          ? const Color(0xFF005C4B)
                                                          : const Color(0xFF0088CC),
                                                      ),
                                                      onPressed: () async {
                                                        if (message.audioFilePath != null) {
                                                          try {
                                                            await _audioPlayer.setFilePath(message.audioFilePath!);
                                                            await _audioPlayer.play();
                                                          } catch (_) {}
                                                        }
                                                      },
                                                    ),
                                                  )
                                                else
                                                  const Padding(
                                                    padding: EdgeInsets.all(12.0),
                                                    child: Icon(Icons.downloading, color: Colors.grey),
                                                  ),
                                                const SizedBox(width: 4),
                                                Flexible(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        message.type == MessageType.audioSent 
                                                          ? 'Voice Message'
                                                          : 'Audio',
                                                        style: TextStyle(
                                                          fontSize: 13,
                                                          fontWeight: FontWeight.bold,
                                                          color: message.type == MessageType.audioSent 
                                                            ? const Color(0xFF005C4B)
                                                            : const Color(0xFF0088CC),
                                                        ),
                                                      ),
                                                      Text(
                                                        message.content,
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color: Colors.grey[700],
                                                        ),
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                            // Progress bar for audio - always visible for audioSent messages
                                            const SizedBox(height: 4),
                                            Container(
                                              constraints: const BoxConstraints(maxWidth: 200),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  if (!message.audioCompleted) ...[
                                                    // Show progress bar
                                                    LinearProgressIndicator(
                                                      value: message.type == MessageType.audioSent 
                                                        ? _progressAnimationController.value  // Use animation value for sending
                                                        : message.audioProgress,  // Use actual progress for receiving
                                                      backgroundColor: Colors.grey[300],
                                                      valueColor: AlwaysStoppedAnimation<Color>(
                                                        message.type == MessageType.audioSent 
                                                          ? const Color(0xFF005C4B)  // Green for sent
                                                          : const Color(0xFF0088CC),  // Blue for received
                                                      ),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      message.type == MessageType.audioSent
                                                        ? '${(_progressAnimationController.value * 100).toInt()}%'  // Use animation value
                                                        : (message.audioProgress != null
                                                            ? '${(message.audioProgress! * 100).toInt()}%'
                                                            : 'Receiving...'),
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        color: Colors.grey[600],
                                                        fontWeight: FontWeight.w500,
                                                      ),
                                                    ),
                                                  ] else ...[
                                                    // Completed: show success indicator only for sent messages
                                                    if (message.type == MessageType.audioSent)
                                                      Row(
                                                        children: const [
                                                          Icon(Icons.check_circle, size: 14, color: whatsappGreen),
                                                          SizedBox(width: 4),
                                                          Text(
                                                            'Sent',
                                                            style: TextStyle(
                                                              fontSize: 10,
                                                              color: whatsappGreen,
                                                              fontWeight: FontWeight.bold,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                  ],
                                                ],
                                              ),
                                            ),
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
                              )
                              else
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: sentBubbleColor,
                                    borderRadius: const BorderRadius.only(
                                      topLeft: Radius.circular(8),
                                      topRight: Radius.circular(8),
                                      bottomLeft: Radius.circular(8),
                                      bottomRight: Radius.circular(2),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      if (message.type == MessageType.audioSent || message.type == MessageType.audioReceived || message.type == MessageType.audioReceiving) ...[
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                if (message.type != MessageType.audioReceiving)
                                                  Container(
                                                    decoration: BoxDecoration(
                                                      color: message.type == MessageType.audioSent 
                                                        ? const Color(0xFF005C4B).withOpacity(0.15)
                                                        : const Color(0xFF0088CC).withOpacity(0.15),
                                                      shape: BoxShape.circle,
                                                    ),
                                                    child: IconButton(
                                                      icon: Icon(
                                                        message.type == MessageType.audioSent 
                                                          ? Icons.mic 
                                                          : Icons.play_arrow,
                                                        color: message.type == MessageType.audioSent 
                                                          ? const Color(0xFF005C4B)
                                                          : const Color(0xFF0088CC),
                                                      ),
                                                      onPressed: () async {
                                                        if (message.audioFilePath != null) {
                                                          try {
                                                            await _audioPlayer.setFilePath(message.audioFilePath!);
                                                            await _audioPlayer.play();
                                                          } catch (_) {}
                                                        }
                                                      },
                                                    ),
                                                  )
                                                else
                                                  const Padding(
                                                    padding: EdgeInsets.all(12.0),
                                                    child: Icon(Icons.downloading, color: Colors.grey),
                                                  ),
                                                const SizedBox(width: 4),
                                                Flexible(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        message.type == MessageType.audioSent 
                                                          ? 'Voice Message'
                                                          : 'Audio',
                                                        style: TextStyle(
                                                          fontSize: 13,
                                                          fontWeight: FontWeight.bold,
                                                          color: message.type == MessageType.audioSent 
                                                            ? const Color(0xFF005C4B)
                                                            : const Color(0xFF0088CC),
                                                        ),
                                                      ),
                                                      Text(
                                                        message.content,
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color: Colors.grey[700],
                                                        ),
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                            // Progress bar for audio - always visible for audioSent messages
                                            const SizedBox(height: 4),
                                            Container(
                                              constraints: const BoxConstraints(maxWidth: 200),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  if (!message.audioCompleted) ...[
                                                    // Show progress bar
                                                    LinearProgressIndicator(
                                                      value: message.type == MessageType.audioSent 
                                                        ? _progressAnimationController.value  // Use animation value for sending
                                                        : message.audioProgress,  // Use actual progress for receiving
                                                      backgroundColor: Colors.grey[300],
                                                      valueColor: AlwaysStoppedAnimation<Color>(
                                                        message.type == MessageType.audioSent 
                                                          ? const Color(0xFF005C4B)  // Green for sent
                                                          : const Color(0xFF0088CC),  // Blue for received
                                                      ),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      message.type == MessageType.audioSent
                                                        ? '${(_progressAnimationController.value * 100).toInt()}%'  // Use animation value
                                                        : (message.audioProgress != null
                                                            ? '${(message.audioProgress! * 100).toInt()}%'
                                                            : 'Receiving...'),
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        color: Colors.grey[600],
                                                        fontWeight: FontWeight.w500,
                                                      ),
                                                    ),
                                                  ] else ...[
                                                    // Completed: show success indicator only for sent messages
                                                    if (message.type == MessageType.audioSent)
                                                      Row(
                                                        children: const [
                                                          Icon(Icons.check_circle, size: 14, color: whatsappGreen),
                                                          SizedBox(width: 4),
                                                          Text(
                                                            'Sent',
                                                            style: TextStyle(
                                                              fontSize: 10,
                                                              color: whatsappGreen,
                                                              fontWeight: FontWeight.bold,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                  ],
                                                ],
                                              ),
                                            ),
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
                            ],
                          ),
                        );
                      },
                    ),
          ),
          
          // Recording overlay with timer and swipe-to-cancel
          if (_isRecording)
            Stack(
              children: [
                Container(
                  color: whatsappLightGray,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Transform.translate(
                    offset: Offset(_recordingSwipeOffset, 0),
                    child: Row(
                      children: [
                        // Pulsing red dot
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0.5, end: 1.0),
                          duration: const Duration(milliseconds: 800),
                          builder: (context, value, child) {
                            return Opacity(
                              opacity: value * (1 - (_recordingSwipeOffset.abs() / 120)),
                              child: Container(
                                width: 12,
                                height: 12,
                                decoration: const BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            );
                          },
                          onEnd: () {
                            // Restart animation by rebuilding
                            if (_isRecording) {
                              setState(() {});
                            }
                          },
                        ),
                        const SizedBox(width: 12),
                        Text(
                          _recordingDuration,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87.withOpacity(1 - (_recordingSwipeOffset.abs() / 120)),
                          ),
                        ),
                        const Spacer(),
                        Opacity(
                          opacity: 1 - (_recordingSwipeOffset.abs() / 120),
                          child: Row(
                            children: [
                              Icon(
                                Icons.keyboard_arrow_left,
                                color: Colors.grey,
                                size: 16,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _recordStopwatch.elapsed.inMilliseconds < 500 
                                    ? 'Keep holding...' 
                                    : 'Swipe to cancel',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Cancel zone indicator (appears when swiping)
                if (_recordingSwipeOffset < -20)
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    child: Container(
                      width: 60,
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1 + (_recordingSwipeOffset.abs() / 120) * 0.3),
                        border: Border(
                          right: BorderSide(
                            color: Colors.red.withOpacity(_recordingSwipeOffset.abs() / 120),
                            width: 2,
                          ),
                        ),
                      ),
                      child: Icon(
                        Icons.delete_outline,
                        color: Colors.red.withOpacity(0.5 + (_recordingSwipeOffset.abs() / 120) * 0.5),
                        size: 24,
                      ),
                    ),
                  ),
              ],
            ),
          
          // Input Field
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: SafeArea(
              child: Row(
                children: [
                  // Record button - Hold to record, swipe left to cancel
                  Listener(
                    onPointerDown: _isConnected ? (event) {
                      _recordingStartX = event.position.dx;
                      _recordingSwipeOffset = 0.0;
                      _recordingCancelled = false;
                      _startRecording();
                    } : null,
                    onPointerMove: _isConnected ? (event) {
                      if (_isRecording) {
                        setState(() {
                          // Calculate swipe offset (negative = left, positive = right)
                          double offset = event.position.dx - _recordingStartX;
                          // Only allow left swipe, clamp the values
                          _recordingSwipeOffset = offset.clamp(-120.0, 0.0);
                          
                          // If swiped far enough left, mark as cancelled
                          if (_recordingSwipeOffset <= -100) {
                            _recordingCancelled = true;
                          }
                        });
                      }
                    } : null,
                    onPointerUp: _isConnected ? (_) {
                      if (_isRecording) {
                        if (_recordingCancelled || _recordingSwipeOffset <= -100) {
                          // Cancelled by swipe
                          _cancelRecording();
                        } else {
                          // Normal send
                          _stopAndSendAudio();
                        }
                      }
                    } : null,
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: _isRecording 
                            ? (_recordingCancelled 
                                ? Colors.grey 
                                : (_recordStopwatch.elapsed.inMilliseconds < 500 ? Colors.orange : Colors.red))
                            : Colors.grey.shade200,
                        shape: BoxShape.circle,
                        boxShadow: _isRecording && !_recordingCancelled ? [
                          BoxShadow(
                            color: Colors.red.withOpacity(0.3),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ] : null,
                      ),
                      child: Icon(
                        _isRecording ? Icons.mic : Icons.mic_none,
                        color: _isRecording ? Colors.white : Colors.black87,
                        size: 24,
                      ),
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
    _recordingTimer?.cancel();
    _segmentProgressTimer?.cancel();
    _progressAnimationController.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _audioPlayer.dispose();
    _recorder.closeRecorder();
    super.dispose();
  }
}
