import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/serial_communication_service.dart';
import '../providers/serial_service_provider.dart';
import '../models/chat_message.dart';
import '../services/profile_service.dart';
import '../services/notification_service.dart';

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

      setState(() {
        _messages.add(ChatMessage.received(parsedContent, username: parsedUsername));
      });

      // Push local notification for the received message
      final title = 'New message' + (parsedUsername != null && parsedUsername.isNotEmpty ? ' from $parsedUsername' : '');
      NotificationService.instance.showMessageNotification(
        title: title,
        body: parsedContent,
      );
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
                                      Text(
                                        message.content,
                                        style: const TextStyle(
                                          fontSize: 15,
                                          color: Color(0xFF111B21),
                                        ),
                                      ),
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
    super.dispose();
  }
}
