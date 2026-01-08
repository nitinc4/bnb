import 'dart:async';
import 'dart:math';
import 'package:bnb/api/client_helper.dart';
import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
// ignore: library_prefixes
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'dart:convert';
import 'package:flutter_html/flutter_html.dart' hide Content;
import 'package:url_launcher/url_launcher.dart';

// Ensure these imports match your project structure
import '../api/magento_api.dart';
import '../models/magento_models.dart';
import '../widgets/product_card.dart';
import 'category_detail_screen.dart';

class SupportScreen extends StatefulWidget {
  final bool isEmbedded;
  const SupportScreen({super.key, this.isEmbedded = false});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  // --- UI STATE ---
  final TextEditingController _messageController = TextEditingController();

  // Contact Details
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  
  // OTP State
  final TextEditingController _otpController = TextEditingController();
  String? _generatedOtp;
  
  // 0: Email, 1: OTP, 2: Details, 3: Waiting (Queue), 4: Active Chat, 5: Fallback/Error
  int _onboardingStep = 0; 

  final ScrollController _scrollController = ScrollController();

  final List<Map<String, dynamic>> _messages = [];
  bool _isLiveSupport = false;

  // --- LOCAL FLOW STATE (For Quick Buttons) ---
  String? _flowState;
  final Map<String, String> _flowData = {};

  // --- AI STATE ---
  late GenerativeModel _aiModel;
  late ChatSession _chatSession;
  bool _aiInitialized = false;
  bool _isLoadingAi = false;

  // --- LIVE SUPPORT STATE (Socket.IO) ---
  IO.Socket? socket;
  bool _isConnected = false;
  bool _isAssigned = false;
  
  // Connection handling variables
  bool _isConnectionFailed = false;
  bool _isConnecting = false;
  Timer? _connectionTimer;
  Timer? _assignmentTimer; // New timer for 30s wait

  int _queuePosition = 0;
  String? _chatId;
  String? _agentName;
  bool _isAgentTyping = false;

  String _customerId = "";

  // Server URL
  final String _serverUrl = "https://support-server.onrender.com";

  @override
  void initState() {
    super.initState();
    _loadUserIdentity();
    _initGemini();
    // 1. Connect immediately when screen opens
    _connectSocket(); 
  }

  Future<void> _loadUserIdentity() async {
    final prefs = await SharedPreferences.getInstance();
    if (MagentoAPI.cachedUser != null) {
      _customerId = MagentoAPI.cachedUser!['id'].toString();
      _nameController.text = "${MagentoAPI.cachedUser!['firstname']} ${MagentoAPI.cachedUser!['lastname']}";
      _emailController.text = MagentoAPI.cachedUser!['email'] ?? "";
    } else if (prefs.containsKey('cached_user_data')) {
      final data = jsonDecode(prefs.getString('cached_user_data')!);
      _customerId = data['id'].toString();
      _nameController.text = "${data['firstname']} ${data['lastname']}";
      _emailController.text = data['email'] ?? "";
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

  // --- AI & Category Helper Methods ---
  String _buildCategoryTree(List<Category> categories) {
    final buffer = StringBuffer();
    for (var cat in categories) {
      _serializeCategory(cat, "", buffer);
    }
    return buffer.toString();
  }

  void _serializeCategory(Category cat, String parentPath, StringBuffer buffer) {
    if (!cat.isActive) return;
    final fullPath = parentPath.isEmpty ? cat.name : "$parentPath > ${cat.name}";
    buffer.writeln("- $fullPath");
    for (var child in cat.children) {
      _serializeCategory(child, fullPath, buffer);
    }
  }

  Future<void> _initGemini() async {
    final apiKey = AppConfig.geminiApiKey; 
    
    if (apiKey.isEmpty) {
      _addSystemMessage("System Warning: GEMINI_API_KEY missing.");
      return;
    }
    String categoryContext = "";
    try {
      final cats = await MagentoAPI().fetchCategories();
      final catTree = _buildCategoryTree(cats);
      categoryContext = catTree.isNotEmpty
          ? "Here is the full list of Categories available in the store:\n$catTree"
          : "Store Categories: Hardware, Nuts, Bolts, Fasteners";
    } catch (e) {
      categoryContext = "Hardware and Tools Store";
    }
    final systemPrompt = """
You are the AI Assistant for 'Buy Nut Bolts'.
Goal: Help users find products, check orders, or submit Requests for Quote (RFQ).

CONTEXT:
$categoryContext

CRITICAL FORMATTING RULES:
1. **NO MARKDOWN**: Do NOT use markdown bold (**text**) or italics (*text*).
2. **USE LINKS**:
   - For categories: <a href="category:CategoryName">CategoryName</a>
   - For specific SKUs: <a href="product:SKU">ProductName</a>
   - Example: "Try <a href="category:Hex Bolts">Hex Bolts</a>."

3. Suggest products using the category list provided.

TOOLS (Trigger by outputting ONLY the command):
- SEARCH: <query>
- GENERAL CHAT: Keep it brief.
""";
    try {
      _aiModel = GenerativeModel(model: 'gemini-2.5-flash', apiKey: apiKey);
      _chatSession = _aiModel.startChat(history: [Content.multi([TextPart(systemPrompt)])]);
      if (mounted) {
        setState(() => _aiInitialized = true);
        if (_messages.isEmpty) {
          _messages.add({
            'type': 'system',
            'content': '👋 Hi! I can help you find products, track orders, or take RFQs. Select an option below or type to chat.',
            'time': DateTime.now()
          });
        }
      }
    } catch (e) {
      _addSystemMessage("Error initializing AI.");
    }
  }

  // --- FLOW LOGIC (BUTTON ACTIONS) ---
  void _startRfqFlow() { setState(() { _flowState = 'rfq_product'; _flowData.clear(); }); _addBotMessage("Let's start your RFQ. What product do you need?"); }
  void _startOrderFlow() { setState(() { _flowState = 'order_id'; _flowData.clear(); }); _addBotMessage("Please enter your Order ID:"); }
  void _startProductSearchFlow() { setState(() { _flowState = 'product_search'; _flowData.clear(); }); _addBotMessage("What product are you looking for?"); }
  void _startSuggestFlow() { setState(() { _flowState = 'ai_suggest'; _flowData.clear(); }); _addBotMessage("Describe your requirement and I will suggest products."); }

  Future<void> _handleFlowInput(String input) async {
    if (input.toLowerCase() == 'exit') {
      setState(() { _flowState = null; _flowData.clear(); });
      _addBotMessage("Okay, I've exited the current action.");
      return;
    }
    if (_flowState != null && _flowState!.startsWith('rfq_')) {
      if (_flowState == 'rfq_product') { _flowData['product'] = input; setState(() => _flowState = 'rfq_qty'); _addBotMessage("How many pieces?"); }
      else if (_flowState == 'rfq_qty') { _flowData['qty'] = input; setState(() => _flowState = 'rfq_name'); _addBotMessage("Your name or company?"); }
      else if (_flowState == 'rfq_name') { _flowData['name'] = input; setState(() => _flowState = 'rfq_email'); _addBotMessage("Your email?"); }
      else if (_flowState == 'rfq_email') { _flowData['email'] = input; setState(() => _flowState = 'rfq_mobile'); _addBotMessage("Your mobile number?"); }
      else if (_flowState == 'rfq_mobile') {
        _flowData['mobile'] = input;
        setState(() { _flowState = null; _isLoadingAi = true; });
        await _performRfqSubmit(_flowData['product']!, _flowData['qty']!, _flowData['name']!, _flowData['email']!, _flowData['mobile']!);
        setState(() => _isLoadingAi = false);
      }
      return;
    }
    if (_flowState != null && _flowState!.startsWith('order_')) {
      if (_flowState == 'order_id') { _flowData['order_id'] = input; setState(() => _flowState = 'order_email'); _addBotMessage("Enter the email used for this order:"); }
      else if (_flowState == 'order_email') {
        _flowData['email'] = input;
        setState(() { _flowState = null; _isLoadingAi = true; });
        await _performOrderCheck(_flowData['order_id']!, _flowData['email']!);
        setState(() => _isLoadingAi = false);
      }
      return;
    }
    if (_flowState == 'product_search') {
      setState(() { _flowState = null; _isLoadingAi = true; });
      await _performProductSearch(input);
      setState(() => _isLoadingAi = false);
      return;
    }
    if (_flowState == 'ai_suggest') {
       setState(() { _flowState = null; _isLoadingAi = true; });
      await _handleAiMessage("Suggest products for: $input");
      return;
    }
  }

  // --- STANDARD AI HANDLER ---
  Future<void> _handleAiMessage(String text) async {
    if (!_aiInitialized) { _addSystemMessage("AI is still initializing... please wait."); return; }
    setState(() => _isLoadingAi = true);
    try {
      final response = await _chatSession.sendMessage(Content.text(text));
      final reply = response.text?.trim() ?? "I didn't catch that.";
      if (reply.toUpperCase().startsWith("SEARCH:")) {
        final query = reply.substring(7).trim();
        await _performProductSearch(query);
      } else {
        _addBotMessage(reply);
      }
    } catch (e) {
        debugPrint("AI Error: $e");
      _addSystemMessage("AI Error. Please try again.");
    } finally {
      if (mounted) { setState(() => _isLoadingAi = false); _scrollToBottom(); }
    }
  }

  // --- TOOLS IMPL ---
  Future<void> _performProductSearch(String query) async {
    _addBotMessage("🔍 Searching for '$query'...");
    final products = await MagentoAPI().searchProducts(query.trim());
    if (products.isEmpty) {
      _addBotMessage("I searched for '$query' but found nothing matching.");
      return;
    }
    setState(() {
      _messages.add({
        'type': 'product_list',
        'content': products,
        'isUser': false,
        'time': DateTime.now()
      });
    });
    _scrollToBottom();
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
      product: prod.trim(), quantity: qty.trim(), name: name.trim(), email: email.trim(), mobile: mobile.trim()
    );
    if (result['success'] == true) {
      _addBotMessage("✅ <b>RFQ Submitted!</b><br>${result['message']}");
    } else {
      _addBotMessage("❌ Failed: ${result['message']}");
    }
  }

  // --- LIVE SUPPORT LOGIC ---

  void _toggleLiveSupport() {
    if (_isLiveSupport) {
      _endChat();
      setState(() {
        _isLiveSupport = false;
        _messages.clear();
        _addSystemMessage("Switched back to AI Assistant.");
        _onboardingStep = 0; // Reset flow
      });
      if (!_aiInitialized) _initGemini();
    } else {
      if (_flowState != null) {
        _addBotMessage("You're in the middle of another flow. Type 'exit' to cancel it first.");
        return;
      }
      setState(() {
        _isLiveSupport = true;
        _messages.clear();
        _onboardingStep = 0; 
      });
    }
  }

  // --- OTP & JOIN FLOW ---

  Future<void> _sendOtp() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please enter a valid email")));
      return;
    }

    setState(() => _isLoadingAi = true); // Recycle loading state for UI spinner
    
    // Generate 6-digit OTP
    final rng = Random();
    _generatedOtp = (100000 + rng.nextInt(900000)).toString();

    final success = await sendSecureEmail(
      to: email,
      subject: "BuyNutBolts Support Verification Code",
      text: "Your verification code for live support is: $_generatedOtp"
    );

    setState(() => _isLoadingAi = false);

    if (success) {
      setState(() => _onboardingStep = 1);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("OTP sent to your email.")));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Failed to send OTP. Please try again.")));
    }
  }

  void _verifyOtp() {
    if (_otpController.text.trim() == _generatedOtp) {
      setState(() => _onboardingStep = 2);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Invalid OTP.")));
    }
  }

  void _joinQueue() {
    if (_nameController.text.trim().isEmpty || _phoneController.text.trim().isEmpty) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please complete your details")));
       return;
    }
    
    if (!_isConnected) {
      _connectSocket(); // Try connecting again if lost
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _onboardingStep = 3; // Waiting State
    });

    // 2. Emit Join
    if (socket != null && socket!.connected) {
      socket!.emit('customer_joined', {
        'customerId': _customerId,
        'customerName': _nameController.text.trim(),
      });
    }

    // 3. Start 30s Timeout
    _assignmentTimer?.cancel();
    _assignmentTimer = Timer(const Duration(seconds: 30), _handleAssignmentTimeout);
  }

  Future<void> _handleAssignmentTimeout() async {
    if (!mounted || _isAssigned) return;

    // Timeout triggered
    setState(() => _onboardingStep = 5); // Error/Fallback State
    
    // Fallback: Send emails to admin and user separately
    
    // 1. Email to Admin
    await sendSecureEmail(
      to: "buynbs.com@gmail.com",
      subject: "Missed Support Request: ${_nameController.text}",
      text: """
User attempted to join live support but no agent was assigned within 30 seconds.

Details:
Name: ${_nameController.text}
Email: ${_emailController.text}
Phone: ${_phoneController.text}
Customer ID: $_customerId

Please contact them as soon as possible.
"""
    );

    // 2. Email to Customer
    await sendSecureEmail(
      to: _emailController.text,
      subject: "Support Request Received - BuyNutBolts",
      text: """
Hello ${_nameController.text},

Unfortunately, all our support agents are currently busy.
We have created a high-priority support ticket for you.

Our team has been notified and will contact you shortly at ${_phoneController.text} or via this email.

Your Details:
Name: ${_nameController.text}
Email: ${_emailController.text}
Phone: ${_phoneController.text}

Thank you for your patience.
"""
    );
  }

  void _endChat() {
    if (_chatId != null && socket != null && socket!.connected) {
      socket!.emit('end_chat', {'chatId': _chatId});
    }
    
    _assignmentTimer?.cancel();
    setState(() {
      _isAssigned = false; 
      _chatId = null; 
      _queuePosition = 0; 
      _agentName = null;
      _onboardingStep = 0;
    });
  }

  // --- UPDATED SOCKET CONNECTION LOGIC ---
  void _connectSocket() {
    if (_isConnected) return; // Already connected

    // 1. Cleanup if needed
    if (socket != null) {
      socket!.disconnect();
      socket!.dispose();
    }

    debugPrint("Attempting to connect to: $_serverUrl");

    // 2. Initialize Socket
    socket = IO.io(_serverUrl, IO.OptionBuilder()
      .setTransports(['websocket']) 
      .disableAutoConnect()
      .setExtraHeaders({'origin': 'https://support-server.onrender.com'}) 
      .build()
    );

    // 3. Connect
    socket!.connect();
    setState(() => _isConnecting = true);

    // 4. Handle "Cold Start" Timeout for initial connection
    _connectionTimer?.cancel();
    _connectionTimer = Timer(const Duration(seconds: 45), () {
      if (mounted && !_isConnected) {
        debugPrint("Connection timed out.");
        setState(() => _isConnectionFailed = true);
      }
    });

    // --- EVENT LISTENERS ---

    socket!.onConnect((_) {
      debugPrint('✅ Socket Connected');
      _connectionTimer?.cancel();
      if (mounted) {
        setState(() {
          _isConnected = true;
          _isConnectionFailed = false;
          _isConnecting = false;
        });
        
        // Re-join if we were waiting
        if (_onboardingStep == 3) {
           socket!.emit('customer_joined', {
            'customerId': _customerId,
            'customerName': _nameController.text.trim(),
          });
        }
      }
    });

    socket!.onDisconnect((_) {
      debugPrint('⚠️ Socket Disconnected');
      if (mounted) setState(() => _isConnected = false);
    });

    socket!.on('queue_update', (data) {
      if (mounted) setState(() { _queuePosition = data['position'] ?? 0; _isAssigned = false; });
    });

    socket!.on('assign_agent', (data) {
      if (mounted) {
        _assignmentTimer?.cancel(); // Cancel timeout
        setState(() {
          _isAssigned = true;
          _onboardingStep = 4; // Active Chat State
          _chatId = data['chatId'];
          _agentName = data['agentName'] ?? "Support Agent";
          _queuePosition = 0;
          _messages.add({ 'type': 'system', 'content': 'You are now connected with $_agentName.', 'time': DateTime.now() });
        });
      }
    });

    socket!.on('new_message', (data) {
      final msgData = data['message'];
      if (msgData != null && mounted) {
        setState(() {
          _messages.add({
            'type': 'chat',
            'content': msgData['content'],
            'isUser': msgData['sender_type'] == 'customer',
            'time': DateTime.parse(msgData['created_at'] ?? DateTime.now().toIso8601String())
          });
          _isAgentTyping = false;
        });
        _scrollToBottom();
      }
    });

    socket!.on('typing_indicator', (data) {
      if (data['senderType'] == 'agent' && mounted) {
        setState(() => _isAgentTyping = data['isTyping'] ?? false);
        if (_isAgentTyping) _scrollToBottom();
      }
    });

    socket!.on('chat_ended', (_) {
      if (mounted) {
        setState(() {
          _messages.add({ 'type': 'system', 'content': 'The chat has been ended by the agent.', 'time': DateTime.now() });
          _isAssigned = false;
          _chatId = null;
        });
      }
    });
  }

  // --- MESSAGE SENDING ---
  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    // 1. LIVE SUPPORT LOGIC
    if (_isLiveSupport) {
      if (!_isConnected) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Reconnecting to server...")));
        _connectSocket();
        return;
      }
      if (!_isAssigned || _chatId == null) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Waiting for an agent...")));
          return;
      }
      socket!.emit('customer_message', {
        'chatId': _chatId,
        'customerId': _customerId,
        'customerName': _nameController.text.trim(),
        'message': text
      });
      _messageController.clear();
    }
    // 2. AI / FLOW LOGIC
    else {
      _messageController.clear();
      setState(() => _messages.add({ 'type': 'chat', 'content': text, 'isUser': true, 'time': DateTime.now() }));
      _scrollToBottom();

      if (_flowState != null) {
        _handleFlowInput(text);
      } else {
        _handleAiMessage(text);
      }
    }
  }

  void _addBotMessage(String content) { setState(() => _messages.add({ 'type': 'chat', 'content': content, 'isUser': false, 'time': DateTime.now() })); _scrollToBottom(); }
  void _addSystemMessage(String content) { setState(() => _messages.add({ 'type': 'system', 'content': content, 'time': DateTime.now() })); _scrollToBottom(); }
  
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut
        );
      }
    });
  }

  @override
  void dispose() {
    if (socket != null) {
        socket!.disconnect();
        socket!.dispose();
    }
    _connectionTimer?.cancel();
    _assignmentTimer?.cancel();
    _messageController.dispose(); _nameController.dispose();
    _emailController.dispose(); _phoneController.dispose();
    _otpController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // --- UI CONSTRUCTION ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: widget.isEmbedded
        ? null
        : AppBar(
            title: Text(_isLiveSupport ? "Live Support" : "AI Assistant"),
            backgroundColor: Colors.white, elevation: 1,
            actions: [
              if (_isLiveSupport && _onboardingStep >= 3) 
                 Container(
                   margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                   padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                   decoration: BoxDecoration(
                     color: _isConnectionFailed ? Colors.red : (_isConnected && _isAssigned ? Colors.green : Colors.orange),
                     borderRadius: BorderRadius.circular(20)
                   ),
                   child: Text(
                     _isConnectionFailed
                       ? "Failed"
                       : (_isConnected && _isAssigned
                           ? "Active"
                           : (_isConnecting ? "Connecting..." : "Waiting")),
                     style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                   ),
                 ),
              if (_isLiveSupport)
                IconButton(icon: const Icon(Icons.logout, color: Colors.red), tooltip: "Exit Support", onPressed: _toggleLiveSupport)
            ],
          ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLiveSupport) {
      if (_onboardingStep < 4) return _buildOnboardingFlow();
      if (_onboardingStep == 5) return _buildFallbackState();
    }
    return _buildChatInterface();
  }

  Widget _buildFallbackState() {
     return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 60, color: Colors.orange),
            const SizedBox(height: 20),
            const Text("No Agents Available", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text(
              "Our agents are currently busy or unavailable. We have sent a support ticket to our team and a copy to ${_emailController.text}.",
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: _toggleLiveSupport,
              child: const Text("Back to AI Assistant"),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildOnboardingFlow() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
             Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10)]), child: const Icon(Icons.support_agent, size: 60, color: Color(0xFF00599c))),
             const SizedBox(height: 30),
             
             if (_onboardingStep == 0) ...[
               const Text("Step 1: Verify Email", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
               const SizedBox(height: 10),
               TextField(controller: _emailController, keyboardType: TextInputType.emailAddress, decoration: InputDecoration(labelText: "Email Address", border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), filled: true, fillColor: Colors.white, prefixIcon: const Icon(Icons.email))),
               const SizedBox(height: 20),
               if (_isLoadingAi) const CircularProgressIndicator() else
               SizedBox(width: double.infinity, height: 50, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00599c), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), onPressed: _sendOtp, child: const Text("Send Verification Code", style: TextStyle(color: Colors.white)))),
             ]
             else if (_onboardingStep == 1) ...[
               const Text("Step 2: Enter OTP", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
               const SizedBox(height: 10),
               Text("Sent to ${_emailController.text}", style: const TextStyle(color: Colors.grey, fontSize: 12)),
               const SizedBox(height: 20),
               TextField(controller: _otpController, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: "6-Digit Code", border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), filled: true, fillColor: Colors.white, prefixIcon: const Icon(Icons.lock))),
               const SizedBox(height: 20),
               SizedBox(width: double.infinity, height: 50, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00599c), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), onPressed: _verifyOtp, child: const Text("Verify & Continue", style: TextStyle(color: Colors.white)))),
               TextButton(onPressed: () => setState(() => _onboardingStep = 0), child: const Text("Change Email"))
             ]
             else if (_onboardingStep == 2) ...[
               const Text("Step 3: Contact Details", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
               const SizedBox(height: 10),
               TextField(controller: _nameController, decoration: InputDecoration(labelText: "Your Name", border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), filled: true, fillColor: Colors.white, prefixIcon: const Icon(Icons.person))),
               const SizedBox(height: 10),
               TextField(controller: _phoneController, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: "Phone Number", border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), filled: true, fillColor: Colors.white, prefixIcon: const Icon(Icons.phone))),
               const SizedBox(height: 20),
               SizedBox(width: double.infinity, height: 50, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00599c), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), onPressed: _joinQueue, child: const Text("Join Live Chat", style: TextStyle(color: Colors.white)))),
             ]
             else if (_onboardingStep == 3) ...[
               // Waiting UI
               const CircularProgressIndicator(),
               const SizedBox(height: 20),
               const Text("Connecting to an agent...", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
               const SizedBox(height: 10),
               const Text("Please wait while we assign you to a support representative.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
               if (_queuePosition > 0) ...[
                 const SizedBox(height: 20),
                 Text("You are #$_queuePosition in the queue.", style: const TextStyle(color: Color(0xFF00599c), fontWeight: FontWeight.bold))
               ],
               const SizedBox(height: 30),
               TextButton(onPressed: _toggleLiveSupport, child: const Text("Cancel & Exit", style: TextStyle(color: Colors.red)))
             ]
          ],
        ),
      ),
    );
  }

  Widget _buildQuickButtons() {
    if (_isLiveSupport) return const SizedBox.shrink();
    final buttons = [
      {'label': 'Generate RFQ', 'action': _startRfqFlow},
      {'label': 'Find Product', 'action': _startProductSearchFlow},
      {'label': 'Suggest Products', 'action': _startSuggestFlow},
      {'label': 'Order Status', 'action': _startOrderFlow},
      {'label': 'Customer Support', 'action': _toggleLiveSupport},
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), color: Colors.grey[200],
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: buttons.map((btn) {
            return Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00599c), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)),
                onPressed: () { if (_flowState != null) _addBotMessage("You're already in a flow. Type 'exit' to cancel it."); else (btn['action'] as VoidCallback)(); },
                child: Text(btn['label'] as String, style: const TextStyle(fontSize: 12)),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildChatInterface() {
    return Column(
      children: [
        if (_isLiveSupport)
           Container(color: Colors.grey[200], padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [const Text("Live Support", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)), const Spacer(), TextButton.icon(onPressed: _toggleLiveSupport, icon: const Icon(Icons.logout, color: Colors.red, size: 16), label: const Text("End Chat", style: TextStyle(color: Colors.red)))])),

        Expanded(
          child: ListView.builder(
            controller: _scrollController, padding: const EdgeInsets.all(16), itemCount: _messages.length,
            itemBuilder: (context, index) {
              final msg = _messages[index];
              final isUser = msg['isUser'] == true;

              if (msg['type'] == 'product_list') {
                final List<Product> products = msg['content'];
                return Container(
                    height: 220,
                    margin: const EdgeInsets.symmetric(vertical: 10),
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: products.length,
                      itemBuilder: (ctx, i) {
                        final product = products[i];
                        return Container(
                          width: 160,
                          margin: const EdgeInsets.only(right: 12),
                          child: GestureDetector(
                            onTap: () => Navigator.pushNamed(context, '/productDetail', arguments: product),
                            child: ProductCard(name: product.name, price: product.price.toStringAsFixed(2), imageUrl: product.imageUrl),
                          ),
                        );
                      },
                    ),
                );
              }

              if (msg['type'] == 'system') return Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Center(child: Text(msg['content'], style: TextStyle(color: Colors.grey[600], fontStyle: FontStyle.italic, fontSize: 12))));

              return Align(
                alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 4), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
                  decoration: BoxDecoration(color: isUser ? const Color(0xFF00599c).withOpacity(0.18) : Colors.white, borderRadius: BorderRadius.circular(12), border: isUser ? null : Border.all(color: Colors.grey.shade300)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      isUser
                        ? Text(msg['content'], style: const TextStyle(color: Colors.black87, fontSize: 15))
                        : Html(
                            data: msg['content'],
                            style: {
                              "body": Style(margin: Margins.all(0), padding: HtmlPaddings.all(0), color: const Color(0xFF003b9f)),
                              "a": Style(color: Colors.blue, textDecoration: TextDecoration.underline, fontWeight: FontWeight.bold),
                            },
                            onLinkTap: (url, _, __) {
                              if (url != null) _handleLinkTap(url);
                            },
                          ),
                      const SizedBox(height: 4),
                      Text(DateFormat('hh:mm a').format(msg['time']), style: TextStyle(color: Colors.grey[500], fontSize: 10)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        if (_isLoadingAi && !_isLiveSupport) const Padding(padding: EdgeInsets.all(8), child: Text("Thinking...", style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic))),
        if (_isAgentTyping) Padding(padding: const EdgeInsets.all(8), child: Text("$_agentName is typing...", style: const TextStyle(color: Colors.grey))),

        _buildQuickButtons(),

        Container(
          padding: const EdgeInsets.all(10), decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Colors.black12))),
          child: SafeArea(
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _messageController,
                  enabled: !_isLiveSupport || (_isLiveSupport && _isAssigned && _isConnected), 
                  decoration: InputDecoration(
                    hintText: _isLiveSupport ? (_isAssigned ? "Type a message..." : "Waiting for agent...") : (_flowState != null ? "Type your answer..." : "Ask AI about products..."),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(25), borderSide: BorderSide.none),
                    filled: true,
                    fillColor: Colors.grey[100],
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10)
                  ),
                  onSubmitted: (_) => _sendMessage()
                )
              ),
              const SizedBox(width: 8),
              CircleAvatar(
                backgroundColor: (!_isLiveSupport || (_isAssigned && _isConnected)) ? const Color(0xFF00599c) : Colors.grey,
                child: IconButton(
                  icon: const Icon(Icons.send, color: Colors.white, size: 20),
                  onPressed: (!_isLiveSupport || (_isAssigned && _isConnected)) ? _sendMessage : null
                )
              )
            ]),
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
        if (product != null && mounted) Navigator.pushNamed(context, '/productDetail', arguments: product);
        else if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Product not found")));
      } catch (e) { debugPrint("Nav Error: $e"); }
      return;
    }
    if (url.startsWith("category:")) {
      final catName = url.split(":")[1];
      final category = MagentoAPI().findCategoryByName(catName);
      if (category != null && mounted) {
        Navigator.push(context, MaterialPageRoute(builder: (context) => CategoryDetailScreen(category: category)));
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Category '$catName' not found")));
      }
      return;
    }
    if (await canLaunchUrl(Uri.parse(url))) await launchUrl(Uri.parse(url));
  }
}