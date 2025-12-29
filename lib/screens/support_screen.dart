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
import '../widgets/product_card.dart'; // Ensure this exists
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
  final TextEditingController _nameController = TextEditingController();
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
  late IO.Socket socket;
  bool _isConnected = false;
  bool _isAssigned = false;
  bool _isNameSubmitted = false;
  int _queuePosition = 0;
  String? _chatId;
  String? _agentName;
  bool _isAgentTyping = false;
  
  String _customerId = "";
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
      if (_nameController.text.isNotEmpty) _isNameSubmitted = true;
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
    final apiKey = dotenv.env['GEMINI_API_KEY'];
    if (apiKey == null) {
      _addSystemMessage("System Warning: GEMINI_API_KEY missing in .env");
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

    // RFQ Steps
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

    // Order Status Steps
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
      setState(() { _isLiveSupport = false; _messages.clear(); _addSystemMessage("Switched back to AI Assistant."); });
      if (!_aiInitialized) _initGemini();
    } else {
      if (_flowState != null) {
        _addBotMessage("You're in the middle of another flow. Type 'exit' to cancel it first.");
        return;
      }
      setState(() { _isLiveSupport = true; _messages.clear(); });
      if (_nameController.text.isNotEmpty) _startChat();
    }
  }

  void _startChat() {
    if (_nameController.text.trim().isEmpty) return;
    FocusScope.of(context).unfocus(); 
    setState(() => _isNameSubmitted = true);
    if (_messages.isEmpty) setState(() => _messages.clear());
    _connectSocket();
  }

  void _endChat() {
    if (_chatId != null && _isConnected) socket.emit('end_chat', {'chatId': _chatId});
    if (_isConnected) socket.disconnect();
    setState(() {
      _isConnected = false; _isAssigned = false; _isNameSubmitted = false;
      _chatId = null; _queuePosition = 0; _agentName = null;
    });
  }

  void _connectSocket() {
    socket = IO.io(_serverUrl, IO.OptionBuilder().setTransports(['websocket']).disableAutoConnect().setExtraHeaders({'origin': 'https://buynutbolts.com'}).build());
    socket.connect();
    socket.onConnect((_) {
      if (mounted) setState(() => _isConnected = true);
      socket.emit('customer_joined', { 'customerId': _customerId, 'customerName': _nameController.text.trim() });
    });
    socket.onDisconnect((_) { if (mounted) setState(() => _isConnected = false); });
    socket.on('queue_update', (data) { if (mounted) setState(() { _queuePosition = data['position'] ?? 0; _isAssigned = false; }); });
    socket.on('assign_agent', (data) {
      if (mounted) {
        setState(() {
          _isAssigned = true; _chatId = data['chatId']; _agentName = data['agentName'] ?? "Support Agent"; _queuePosition = 0;
          _messages.add({ 'type': 'system', 'content': 'You are now connected with $_agentName.', 'time': DateTime.now() });
        });
      }
    });
    socket.on('new_message', (data) {
      final msgData = data['message'];
      if (msgData != null && mounted) {
        setState(() {
          _messages.add({ 'type': 'chat', 'content': msgData['content'], 'isUser': msgData['sender_type'] == 'customer', 'time': DateTime.parse(msgData['created_at'] ?? DateTime.now().toIso8601String()) });
          _isAgentTyping = false;
        });
        _scrollToBottom();
      }
    });
    socket.on('typing_indicator', (data) { if (data['senderType'] == 'agent' && mounted) setState(() => _isAgentTyping = data['isTyping'] ?? false); if (_isAgentTyping) _scrollToBottom(); });
    socket.on('chat_ended', (_) { if (mounted) setState(() { _messages.add({ 'type': 'system', 'content': 'The chat has been ended by the agent.', 'time': DateTime.now() }); _isAssigned = false; _chatId = null; }); });
  }

  void _sendLiveMessage(String text) {
    if (!_isAssigned || _chatId == null) return;
    socket.emit('customer_message', { 'chatId': _chatId, 'customerId': _customerId, 'customerName': _nameController.text.trim(), 'message': text });
  }

  // --- UI ---

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    _messageController.clear();
    setState(() => _messages.add({ 'type': 'chat', 'content': text, 'isUser': true, 'time': DateTime.now() }));
    _scrollToBottom();
    if (_isLiveSupport) { _sendLiveMessage(text); } 
    else if (_flowState != null) { _handleFlowInput(text); } 
    else { _handleAiMessage(text); }
  }

  void _addBotMessage(String content) { setState(() => _messages.add({ 'type': 'chat', 'content': content, 'isUser': false, 'time': DateTime.now() })); _scrollToBottom(); }
  void _addSystemMessage(String content) { setState(() => _messages.add({ 'type': 'system', 'content': content, 'time': DateTime.now() })); _scrollToBottom(); }
  void _scrollToBottom() { WidgetsBinding.instance.addPostFrameCallback((_) { if (_scrollController.hasClients) _scrollController.animateTo(_scrollController.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut); }); }

  @override
  void dispose() {
    if (_isLiveSupport && _isConnected) socket.disconnect();
    _messageController.dispose(); _nameController.dispose(); _scrollController.dispose();
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
            backgroundColor: Colors.white, elevation: 1,
            actions: [
              if (_isLiveSupport)
                IconButton(icon: const Icon(Icons.logout, color: Colors.red), tooltip: "Exit Support", onPressed: _toggleLiveSupport)
            ],
          ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLiveSupport && !_isNameSubmitted) return _buildWelcomeScreen();
    return _buildChatInterface();
  }

  Widget _buildWelcomeScreen() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10)]), child: const Icon(Icons.support_agent, size: 60, color: Color(0xFF00599c))),
            const SizedBox(height: 30),
            const Text("Connect to Live Support", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF00599c))),
            const SizedBox(height: 10),
            const Text("Please enter your name to join the queue.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 30),
            TextField(controller: _nameController, decoration: InputDecoration(labelText: "Your Name", border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), filled: true, fillColor: Colors.white, prefixIcon: const Icon(Icons.person_outline))),
            const SizedBox(height: 20),
            SizedBox(width: double.infinity, height: 50, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00599c), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), onPressed: _startChat, child: const Text("Start Chat", style: TextStyle(color: Colors.white, fontSize: 16)))),
            TextButton(onPressed: _toggleLiveSupport, child: const Text("Back to AI Assistant"))
          ],
        ),
      ),
    );
  }

  // [RESTORED] Quick Buttons Bar
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
        if (_isLiveSupport) ...[
          if (widget.isEmbedded)
            Container(color: Colors.grey[200], padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [const Text("Live Support Active", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)), const Spacer(), TextButton.icon(onPressed: _toggleLiveSupport, icon: const Icon(Icons.logout, color: Colors.red, size: 16), label: const Text("Exit", style: TextStyle(color: Colors.red)))])),
          if (!_isConnected)
            Container(width: double.infinity, color: Colors.red[100], padding: const EdgeInsets.all(8), child: const Text("Connecting to server...", textAlign: TextAlign.center, style: TextStyle(color: Colors.red)))
          else if (!_isAssigned)
            Container(width: double.infinity, color: Colors.orange[100], padding: const EdgeInsets.all(12), child: Column(children: [const Text("Waiting for an agent...", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange)), if (_queuePosition > 0) Text("Position in queue: $_queuePosition", style: const TextStyle(color: Colors.deepOrange))])),
        ],
        Expanded(
          child: ListView.builder(
            controller: _scrollController, padding: const EdgeInsets.all(16), itemCount: _messages.length,
            itemBuilder: (context, index) {
              final msg = _messages[index];
              final isUser = msg['isUser'] == true;

              // [RESTORED] Render Product List
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
        if (_isLoadingAi) const Padding(padding: EdgeInsets.all(8), child: Text("Thinking...", style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic))),
        if (_isAgentTyping) Padding(padding: const EdgeInsets.all(8), child: Text("$_agentName is typing...", style: const TextStyle(color: Colors.grey))),
        
        // [RESTORED] Quick Buttons added here
        _buildQuickButtons(),

        Container(
          padding: const EdgeInsets.all(10), decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Colors.black12))),
          child: SafeArea(
            child: Row(children: [Expanded(child: TextField(controller: _messageController, enabled: !_isLiveSupport || (_isAssigned && _isConnected), decoration: InputDecoration(hintText: _isLiveSupport ? (_isAssigned ? "Type a message..." : "Waiting...") : (_flowState != null ? "Type your answer..." : "Ask AI about products..."), border: OutlineInputBorder(borderRadius: BorderRadius.circular(25), borderSide: BorderSide.none), filled: true, fillColor: Colors.grey[100], contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10)), onSubmitted: (_) => _sendMessage())), const SizedBox(width: 8), CircleAvatar(backgroundColor: (!_isLiveSupport || (_isAssigned && _isConnected)) ? const Color(0xFF00599c) : Colors.grey, child: IconButton(icon: const Icon(Icons.send, color: Colors.white, size: 20), onPressed: (!_isLiveSupport || (_isAssigned && _isConnected)) ? _sendMessage : null))]),
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
      // [CRITICAL] This requires the recursive search fix in magento_api.dart
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