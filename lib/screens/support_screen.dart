// lib/screens/support_screen.dart
import 'package:flutter/material.dart';
// ignore: library_prefixes
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'dart:convert';
import '../api/magento_api.dart';

class SupportScreen extends StatefulWidget {
  final bool isEmbedded;
  const SupportScreen({super.key, this.isEmbedded = false});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  late IO.Socket socket;
  
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _nameController = TextEditingController(); 
  final ScrollController _scrollController = ScrollController();
  
  // [FIX] Made final
  final List<Map<String, dynamic>> _messages = [];
  
  bool _isConnected = false;
  bool _isAssigned = false;
  bool _isNameSubmitted = false;
  int _queuePosition = 0;
  String? _chatId;
  String? _agentName;
  bool _isAgentTyping = false;
  
  String _customerId = "";
  
  final String _serverUrl = "https://support-sever.onrender.com"; 

  @override
  void initState() {
    super.initState();
    _loadUserIdentity();
  }

  Future<void> _loadUserIdentity() async {
    final prefs = await SharedPreferences.getInstance();
    
    if (MagentoAPI.cachedUser != null) {
      _customerId = MagentoAPI.cachedUser!['id'].toString();
      _nameController.text = "${MagentoAPI.cachedUser!['firstname']} ${MagentoAPI.cachedUser!['lastname']}";
    } else if (prefs.containsKey('cached_user_data')) {
      final data = jsonDecode(prefs.getString('cached_user_data')!);
      _customerId = data['id'].toString();
      _nameController.text = "${data['firstname']} ${data['lastname']}";
    } else {
      String? storedGuestId = prefs.getString('guest_support_id');
      if (storedGuestId == null) {
        storedGuestId = const Uuid().v4();
        await prefs.setString('guest_support_id', storedGuestId);
      }
      _customerId = "guest_$storedGuestId";
    }
    setState(() {}); 
  }

  void _startChat() {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter your name")),
      );
      return;
    }
    FocusScope.of(context).unfocus(); 
    setState(() {
      _isNameSubmitted = true;
      _messages.clear(); 
    });
    _connectSocket();
  }

  void _endChat() {
    if (_chatId != null && socket.connected) {
      socket.emit('end_chat', {'chatId': _chatId});
    }

    socket.disconnect();
    
    setState(() {
      _isConnected = false;
      _isAssigned = false;
      _isNameSubmitted = false;
      _chatId = null;
      _queuePosition = 0;
      _agentName = null;
    });
  }

  void _connectSocket() {
    socket = IO.io(_serverUrl, IO.OptionBuilder()
      .setTransports(['websocket'])
      .disableAutoConnect()
      .setExtraHeaders({'origin': 'https://support-sever.onrender.com'})
      .build()
    );

    socket.connect();

    socket.onConnect((_) {
      debugPrint('⚡ Socket Connected');
      if (mounted) setState(() => _isConnected = true);
      
      socket.emit('customer_joined', {
        'customerId': _customerId,
        'customerName': _nameController.text.trim(),
      });
    });

    socket.onDisconnect((_) {
      debugPrint('Disconnected');
      if (mounted) setState(() => _isConnected = false);
    });

    socket.on('queue_update', (data) {
      if (mounted) {
        setState(() {
          _queuePosition = data['position'] ?? 0;
          _isAssigned = false;
        });
      }
    });

    socket.on('assign_agent', (data) {
      if (mounted) {
        setState(() {
          _isAssigned = true;
          _chatId = data['chatId'];
          _agentName = data['agentName'] ?? "Support Agent";
          _queuePosition = 0;
          _messages.add({
            'type': 'system',
            'content': 'You are now connected with $_agentName.',
            'time': DateTime.now()
          });
        });
      }
    });

    socket.on('new_message', (data) {
      final msgData = data['message'];
      if (msgData != null) {
        if (mounted) {
          setState(() {
            _messages.add({
              'type': 'chat',
              'content': msgData['content'],
              'isUser': msgData['sender_type'] == 'customer',
              'time': DateTime.parse(msgData['created_at'] ?? DateTime.now().toIso8601String()),
            });
            _isAgentTyping = false;
          });
          _scrollToBottom();
        }
      }
    });

    socket.on('typing_indicator', (data) {
      if (data['senderType'] == 'agent') {
        if (mounted) {
          setState(() => _isAgentTyping = data['isTyping'] ?? false);
          if (_isAgentTyping) _scrollToBottom();
        }
      }
    });

    socket.on('chat_ended', (_) {
      if (mounted) {
        setState(() {
          _messages.add({
            'type': 'system',
            'content': 'The chat has been ended by the agent.',
            'time': DateTime.now()
          });
          _isAssigned = false;
          _chatId = null;
        });
      }
    });
  }

  void _sendMessage() {
    if (_messageController.text.trim().isEmpty || !_isAssigned || _chatId == null) return;

    final text = _messageController.text;
    
    socket.emit('customer_message', {
      'chatId': _chatId,
      'customerId': _customerId,
      'customerName': _nameController.text.trim(),
      'message': text,
    });

    _messageController.clear();
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

  @override
  void dispose() {
    if (_isNameSubmitted) socket.disconnect(); 
    _messageController.dispose();
    _nameController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: widget.isEmbedded 
          ? null 
          : AppBar(
              title: const Text("Support Chat"),
              backgroundColor: Colors.white,
              elevation: 1,
              actions: [
                if (_isNameSubmitted)
                  IconButton(
                    icon: const Icon(Icons.logout, color: Colors.red),
                    tooltip: "End Chat",
                    onPressed: _endChat,
                  )
              ],
            ),
      body: !_isNameSubmitted 
        ? _buildWelcomeScreen() 
        : _buildChatInterface(),
    );
  }

  Widget _buildWelcomeScreen() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10)]
              ),
              child: const Icon(Icons.support_agent, size: 60, color: Color(0xFF00599c)),
            ),
            const SizedBox(height: 30),
            const Text(
              "How can we help you?",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF00599c)),
            ),
            const SizedBox(height: 10),
            const Text(
              "Please enter your name to start chatting with an agent.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 30),
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: "Your Name",
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Colors.white,
                prefixIcon: const Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00599c),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _startChat,
                child: const Text("Start Chat", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatInterface() {
    return Column(
      children: [
        if (!_isConnected)
          Container(
            width: double.infinity,
            color: Colors.red[100],
            padding: const EdgeInsets.all(8),
            child: const Text("Connecting to server...", textAlign: TextAlign.center, style: TextStyle(color: Colors.red)),
          )
        else if (!_isAssigned)
          Container(
            width: double.infinity,
            color: Colors.orange[100],
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Icon(Icons.hourglass_empty, color: Colors.deepOrange, size: 30),
                const SizedBox(height: 8),
                const Text(
                  "Waiting for an agent...", 
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange, fontSize: 16)
                ),
                const SizedBox(height: 4),
                if (_queuePosition > 0)
                   Text("You are number $_queuePosition in the queue.", style: const TextStyle(color: Colors.deepOrange))
                else
                   const Text("All agents are currently busy.", style: TextStyle(color: Colors.deepOrange)),
              ],
            ),
          ),

        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              final msg = _messages[index];
              
              if (msg['type'] == 'system') {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Center(
                    child: Text(msg['content'], style: TextStyle(color: Colors.grey[600], fontStyle: FontStyle.italic, fontSize: 12)),
                  ),
                );
              }

              final isUser = msg['isUser'];
              return Align(
                alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                  decoration: BoxDecoration(
                    color: isUser ? const Color(0xFF00599c) : Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(12),
                      topRight: const Radius.circular(12),
                      bottomLeft: isUser ? const Radius.circular(12) : Radius.zero,
                      bottomRight: isUser ? Radius.zero : const Radius.circular(12),
                    ),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5, offset: const Offset(0, 2))
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        msg['content'],
                        style: TextStyle(color: isUser ? Colors.white : Colors.black87, fontSize: 15),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        DateFormat('hh:mm a').format(msg['time']),
                        style: TextStyle(color: isUser ? Colors.white70 : Colors.grey, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        
        if (_isAgentTyping)
          Padding(
            padding: const EdgeInsets.only(left: 20, bottom: 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text("$_agentName is typing...", style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ),
          ),

        Container(
          padding: const EdgeInsets.all(10),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Colors.black12)),
          ),
          child: SafeArea(
            child: Row(
              children: [
                if (widget.isEmbedded && _isNameSubmitted)
                   IconButton(
                     icon: const Icon(Icons.logout, color: Colors.red),
                     onPressed: _endChat,
                   ),
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    enabled: _isAssigned && _isConnected,
                    decoration: InputDecoration(
                      hintText: _isAssigned ? "Type a message..." : "Waiting for agent...",
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(25), borderSide: BorderSide.none),
                      filled: true,
                      fillColor: Colors.grey[100],
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: _isAssigned && _isConnected ? const Color(0xFF00599c) : Colors.grey,
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white, size: 20),
                    onPressed: (_isAssigned && _isConnected) ? _sendMessage : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}