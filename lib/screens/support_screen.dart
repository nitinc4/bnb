import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
// ignore: library_prefixes
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'dart:convert';
// Hide 'Content' from flutter_html to avoid conflict with Gemini's Content class
import 'package:flutter_html/flutter_html.dart' hide Content;
import 'package:url_launcher/url_launcher.dart';

import '../api/magento_api.dart';
// Ensure this model file exists and has Product/Order classes
import '../models/magento_models.dart'; 

class SupportScreen extends StatefulWidget {
  final bool isEmbedded;
  const SupportScreen({super.key, this.isEmbedded = false});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  // --- UI STATE ---
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  // Stores both AI and Live Chat messages
  final List<Map<String, dynamic>> _messages = [];
  
  // Toggle: FALSE = AI Bot (Default), TRUE = Human Agent
  bool _isLiveSupport = false; 

  // --- AI STATE ---
  late GenerativeModel _aiModel;
  late ChatSession _chatSession;
  bool _aiInitialized = false;
  bool _isLoadingAi = false;

  // --- LIVE SUPPORT STATE (Socket.IO) ---
  late IO.Socket socket;
  bool _isConnected = false;
  bool _isAssigned = false;
  bool _isNameSubmitted = false;
  int _queuePosition = 0;
  String? _chatId;
  String? _agentName;
  bool _isAgentTyping = false;
  
  String _customerId = "";
  
  // [FIX] Ensure this URL is correct (no typo in 'server')
  final String _serverUrl = "https://support-server.onrender.com";

  @override
  void initState() {
    super.initState();
    _loadUserIdentity();
    _initGemini();
  }

  Future<void> _loadUserIdentity() async {
    final prefs = await SharedPreferences.getInstance();
    if (MagentoAPI.cachedUser != null) {
      _customerId = MagentoAPI.cachedUser!['id'].toString();
      _nameController.text = "${MagentoAPI.cachedUser!['firstname']} ${MagentoAPI.cachedUser!['lastname']}";
      if (_nameController.text.isNotEmpty) {
        _isNameSubmitted = true;
      }
    } else if (prefs.containsKey('cached_user_data')) {
      final data = jsonDecode(prefs.getString('cached_user_data')!);
      _customerId = data['id'].toString();
      _nameController.text = "${data['firstname']} ${data['lastname']}";
      _isNameSubmitted = true;
    } else {
      String? storedGuestId = prefs.getString('guest_support_id');
      if (storedGuestId == null) {
        storedGuestId = const Uuid().v4();
        await prefs.setString('guest_support_id', storedGuestId);
      }
      _customerId = "guest_$storedGuestId";
    }
    if (mounted) setState(() {});
  }

  // ---------------------------------------------------------------------------
  // 1. AI & GEMINI LOGIC
  // ---------------------------------------------------------------------------

  Future<void> _initGemini() async {
    final apiKey = dotenv.env['GEMINI_API_KEY'];
    if (apiKey == null) {
      _addSystemMessage("System Warning: GEMINI_API_KEY missing in .env");
      return;
    }

    // 1. Fetch Categories for Context
    String categoryContext = "";
    try {
      final cats = await MagentoAPI().fetchCategories();
      final catNames = cats.map((c) => c.name).take(30).join(", ");
      categoryContext = "Available Categories: $catNames";
    } catch (_) {
      categoryContext = "Hardware and Tools Store";
    }

    // 2. Define System Instruction
    final systemPrompt = """
You are the AI Assistant for 'Buy Nut Bolts' ($categoryContext).
Goal: Help users find products, check orders, or submit Requests for Quote (RFQ).

CRITICAL: You have access to TOOLS. Trigger them by outputting ONLY the command:

1. SEARCH PRODUCTS:
   Output: SEARCH: <query>

2. CHECK ORDER STATUS:
   Output: ORDER: <order_id> | <email>

3. SUBMIT RFQ (Bulk Orders):
   Output: RFQ: <product> | <qty> | <name> | <email> | <mobile>

4. GENERAL CHAT:
   Keep it brief. If you can't help, suggest tapping the headset icon for a live agent.
""";

    try {
      // [FIX] CHANGED MODEL NAME to 'gemini-2.5-flash' because '1.5' is deprecated/shutdown
      _aiModel = GenerativeModel(
        model: 'gemini-2.5-flash', 
        apiKey: apiKey,
      );
      
      _chatSession = _aiModel.startChat(history: [
        Content.multi([TextPart(systemPrompt)])
      ]);
      
      if (mounted) {
        setState(() => _aiInitialized = true);
        _messages.add({
          'type': 'system',
          'content': '👋 Hi! I can help you find products, track orders, or take RFQs. Tap the headset 🎧 to talk to a human.',
          'time': DateTime.now()
        });
      }
    } catch (e) {
      debugPrint("Gemini Init Error: $e");
      _addSystemMessage("Error initializing AI. Please update your app.");
    }
  }

  Future<void> _handleAiMessage(String text) async {
    if (!_aiInitialized) {
       _addSystemMessage("AI is still initializing... please wait.");
       return;
    }
    setState(() => _isLoadingAi = true);

    try {
      final response = await _chatSession.sendMessage(Content.text(text));
      final reply = response.text?.trim() ?? "I didn't catch that.";
      final upperReply = reply.toUpperCase();

      if (upperReply.startsWith("SEARCH:")) {
        final query = reply.substring(7).trim();
        await _performProductSearch(query);
      } 
      else if (upperReply.startsWith("ORDER:")) {
        final parts = reply.substring(6).split('|');
        if (parts.length >= 2) {
          await _performOrderCheck(parts[0].trim(), parts[1].trim());
        } else {
          _addBotMessage("I need both Order ID and Email to check status.");
        }
      }
      else if (upperReply.startsWith("RFQ:")) {
        final parts = reply.substring(4).split('|');
        if (parts.length >= 5) {
          await _performRfqSubmit(parts[0], parts[1], parts[2], parts[3], parts[4]);
        } else {
          _addBotMessage("I missed some details. Please provide Product, Qty, Name, Email, and Mobile.");
        }
      } 
      else {
        _addBotMessage(reply);
      }

    } catch (e) {
      debugPrint("AI Error: $e");
      // Handle "404 Not Found" gracefully in UI
      if (e.toString().contains("404")) {
         _addSystemMessage("Error: AI Model deprecated. Please contact support.");
      } else {
         _addSystemMessage("AI Error. Please try again or switch to Live Support.");
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingAi = false);
        _scrollToBottom();
      }
    }
  }

  // --- AI TOOL EXECUTIONS ---

  Future<void> _performProductSearch(String query) async {
    _addBotMessage("🔍 Searching for '$query'...");
    final products = await MagentoAPI().searchProducts(query);
    
    if (products.isEmpty) {
      _addBotMessage("I couldn't find any matching products.");
      return;
    }

    String html = "<b>Found these matches:</b><br>";
    for (var p in products.take(3)) {
       html += """
       <div style='margin-top:8px; border-bottom:1px solid #eee; padding-bottom:4px;'>
         <a href='product:${p.sku}'><b>${p.name}</b></a><br>
         <span style='color:green'>${p.price}</span>
       </div>
       """;
    }
    _addBotMessage(html);
  }

  Future<void> _performOrderCheck(String orderId, String email) async {
    _addBotMessage("Checking order #$orderId...");
    final result = await MagentoAPI().checkOrderStatus(orderId, email);
    
    if (result['success'] == true) {
      _addBotMessage("✅ <b>Order Found!</b><br>Status: <b>${result['status']}</b><br>Date: ${result['eta']}");
    } else {
      _addBotMessage("❌ ${result['message']}");
    }
  }

  Future<void> _performRfqSubmit(String prod, String qty, String name, String email, String mobile) async {
    _addBotMessage("Submitting your request...");
    final result = await MagentoAPI().submitRfq(
      product: prod.trim(), 
      quantity: qty.trim(), 
      name: name.trim(), 
      email: email.trim(), 
      mobile: mobile.trim()
    );

    if (result['success'] == true) {
      _addBotMessage("✅ <b>RFQ Submitted!</b><br>${result['message']}");
    } else {
      _addBotMessage("❌ Failed: ${result['message']}");
    }
  }

  // ---------------------------------------------------------------------------
  // 2. LIVE SUPPORT LOGIC (Socket.IO)
  // ---------------------------------------------------------------------------

  void _toggleLiveSupport() {
    if (_isLiveSupport) {
      _endChat(); 
      setState(() {
        _isLiveSupport = false;
        _messages.clear();
        _addSystemMessage("Switched back to AI Assistant.");
      });
      if (!_aiInitialized) _initGemini();
    } else {
      setState(() {
        _isLiveSupport = true;
        _messages.clear();
      });
      if (_nameController.text.isNotEmpty) {
        _startChat();
      }
    }
  }

  void _startChat() {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter your name")),
      );
      return;
    }
    FocusScope.of(context).unfocus(); 
    setState(() => _isNameSubmitted = true);
    if (_messages.isEmpty) setState(() => _messages.clear());
    _connectSocket();
  }

  void _endChat() {
    if (_chatId != null && _isConnected) {
      socket.emit('end_chat', {'chatId': _chatId});
    }
    if (_isConnected) socket.disconnect();
    
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
      .setExtraHeaders({'origin': 'https://buynutbolts.com'}) 
      .build()
    );

    socket.connect();

    socket.onConnect((_) {
      if (mounted) setState(() => _isConnected = true);
      socket.emit('customer_joined', {
        'customerId': _customerId,
        'customerName': _nameController.text.trim(),
      });
    });

    socket.onDisconnect((_) {
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
      if (msgData != null && mounted) {
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
    });

    socket.on('typing_indicator', (data) {
      if (data['senderType'] == 'agent' && mounted) {
        setState(() => _isAgentTyping = data['isTyping'] ?? false);
        if (_isAgentTyping) _scrollToBottom();
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

  void _sendLiveMessage(String text) {
    if (!_isAssigned || _chatId == null) return;
    
    socket.emit('customer_message', {
      'chatId': _chatId,
      'customerId': _customerId,
      'customerName': _nameController.text.trim(),
      'message': text,
    });
  }

  // ---------------------------------------------------------------------------
  // 3. UI HELPERS
  // ---------------------------------------------------------------------------

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    _messageController.clear();

    setState(() {
      _messages.add({
        'type': 'chat',
        'content': text,
        'isUser': true,
        'time': DateTime.now()
      });
    });
    _scrollToBottom();

    if (_isLiveSupport) {
      _sendLiveMessage(text);
    } else {
      _handleAiMessage(text);
    }
  }

  void _addBotMessage(String content) {
    setState(() {
      _messages.add({
        'type': 'chat',
        'content': content,
        'isUser': false,
        'time': DateTime.now()
      });
    });
    _scrollToBottom();
  }

  void _addSystemMessage(String content) {
    setState(() {
      _messages.add({
        'type': 'system',
        'content': content,
        'time': DateTime.now()
      });
    });
    _scrollToBottom();
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
    if (_isLiveSupport && _isConnected) socket.disconnect();
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
            title: Text(_isLiveSupport ? "Live Support" : "AI Assistant"),
            backgroundColor: Colors.white,
            elevation: 1,
            actions: [
              IconButton(
                icon: Icon(_isLiveSupport ? Icons.smart_toy : Icons.headset_mic, color: const Color(0xFF00599c)),
                tooltip: _isLiveSupport ? "Switch to AI" : "Talk to Human",
                onPressed: _toggleLiveSupport,
              ),
              if (_isLiveSupport && _isNameSubmitted)
                IconButton(
                  icon: const Icon(Icons.logout, color: Colors.red),
                  tooltip: "End Chat",
                  onPressed: _endChat,
                )
            ],
          ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLiveSupport && !_isNameSubmitted) {
      return _buildWelcomeScreen();
    }
    return _buildChatInterface();
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
              "Connect to Live Support",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF00599c)),
            ),
            const SizedBox(height: 10),
            const Text(
              "Please enter your name to join the queue.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 30),
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: "Your Name",
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true, fillColor: Colors.white,
                prefixIcon: const Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity, height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00599c),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _startChat,
                child: const Text("Start Chat", style: TextStyle(color: Colors.white, fontSize: 16)),
              ),
            ),
            TextButton(
              onPressed: _toggleLiveSupport,
              child: const Text("Back to AI Assistant"),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildChatInterface() {
    return Column(
      children: [
        if (_isLiveSupport) ...[
          if (!_isConnected)
            Container(
              width: double.infinity, color: Colors.red[100], padding: const EdgeInsets.all(8),
              child: const Text("Connecting to server...", textAlign: TextAlign.center, style: TextStyle(color: Colors.red)),
            )
          else if (!_isAssigned)
            Container(
              width: double.infinity, color: Colors.orange[100], padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  const Text("Waiting for an agent...", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange)),
                  if (_queuePosition > 0) Text("Position in queue: $_queuePosition", style: const TextStyle(color: Colors.deepOrange)),
                ],
              ),
            ),
        ],

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

              final isUser = msg['isUser'] == true;
              return Align(
                alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
                  decoration: BoxDecoration(
                    color: isUser ? const Color(0xFF00599c) : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5)],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      isUser
                        ? Text(msg['content'], style: const TextStyle(color: Colors.white, fontSize: 15))
                        : Html(
                            data: msg['content'],
                            style: {
                              "body": Style(margin: Margins.all(0), padding: HtmlPaddings.all(0)),
                              "a": Style(color: Colors.blue, textDecoration: TextDecoration.underline),
                            },
                            onLinkTap: (url, _, __) {
                              if (url != null) _handleLinkTap(url);
                            },
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

        if (_isLoadingAi)
           const Padding(padding: EdgeInsets.all(8), child: Text("AI is thinking...", style: TextStyle(color: Colors.grey))),
        if (_isAgentTyping)
           Padding(padding: const EdgeInsets.all(8), child: Text("$_agentName is typing...", style: const TextStyle(color: Colors.grey))),

        Container(
          padding: const EdgeInsets.all(10),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Colors.black12)),
          ),
          child: SafeArea(
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    enabled: !_isLiveSupport || (_isAssigned && _isConnected),
                    decoration: InputDecoration(
                      hintText: _isLiveSupport 
                          ? (_isAssigned ? "Type a message..." : "Waiting for agent...") 
                          : "Ask AI about products...",
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
                  backgroundColor: (!_isLiveSupport || (_isAssigned && _isConnected)) ? const Color(0xFF00599c) : Colors.grey,
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white, size: 20),
                    onPressed: (!_isLiveSupport || (_isAssigned && _isConnected)) ? _sendMessage : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _handleLinkTap(String url) async {
    if (url.startsWith("product:")) {
      final sku = url.split(":")[1];
      try {
        final product = await MagentoAPI().fetchProductBySku(sku);
        if (product != null && mounted) {
           Navigator.pushNamed(context, '/productDetail', arguments: product);
        } else {
           if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Product not found")));
        }
      } catch (e) {
        debugPrint("Nav Error: $e");
      }
      return;
    }
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    }
  }
}