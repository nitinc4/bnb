import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class WebsiteWebViewScreen extends StatefulWidget {
  final String url;
  final String title;

  const WebsiteWebViewScreen({
    super.key, 
    this.url = 'https://buynutbolts.com', 
    this.title = 'BNB Website'
  });

  @override
  State<WebsiteWebViewScreen> createState() => _WebsiteWebViewScreenState();
}

class _WebsiteWebViewScreenState extends State<WebsiteWebViewScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();

    // 1. Initialize Controller
    _controller = WebViewController()
      // 2. Configure JavaScript Mode
      // Unrestricted is usually required for modern e-commerce sites
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      
      // 3. Set Background Color (prevents white flash)
      ..setBackgroundColor(const Color(0x00000000))
      
      // 4. Implement Navigation Delegate for Security
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            // Update loading bar.
          },
          onPageStarted: (String url) {
            if (mounted) setState(() => _isLoading = true);
          },
          onPageFinished: (String url) {
            if (mounted) setState(() => _isLoading = false);
          },
          
          // CRITICAL SECURITY FEATURE: Navigation Restriction
          onNavigationRequest: (NavigationRequest request) {
            // Only allow navigation to your own domain
            if (request.url.startsWith('https://buynutbolts.com') || 
                request.url.startsWith('https://www.buynutbolts.com')) {
              return NavigationDecision.navigate;
            }
            
            // Allow payment gateways if necessary (e.g., razorpay, paypal)
            if (request.url.contains('razorpay.com')) {
               return NavigationDecision.navigate;
            }

            // Block everything else (ads, malicious redirects, etc.)
            debugPrint('Blocking navigation to: ${request.url}');
            return NavigationDecision.prevent;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(color: Color(0xFF00599c))),
        backgroundColor: Colors.white,
        elevation: 1,
        iconTheme: const IconThemeData(color: Color(0xFF00599c)),
        actions: [
          // Navigation Controls
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              if (await _controller.canGoBack()) {
                _controller.goBack();
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _controller.reload(),
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(color: Color(0xFF00599c)),
            ),
        ],
      ),
    );
  }
}