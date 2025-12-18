// lib/screens/website_webview_screen.dart
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class WebsiteWebViewScreen extends StatefulWidget {
  final String url;
  final String title;

  const WebsiteWebViewScreen({
    super.key, 
    this.url = 'https://buynutbolts.com', 
    this.title = 'BuyNutBolts Website',
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

    // Initialize Controller
    _controller = WebViewController()
      //Configure JavaScript Mode
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      
      // Set Background Color
      ..setBackgroundColor(const Color(0x00000000))

      // Enable Zoom (Fix for non-mobile optimized sites)
      ..enableZoom(true)
      
      // Implement Navigation Delegate
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
            // Only website domain and RFQ subdomain allowed
            if (request.url.startsWith('https://buynutbolts.com') || 
                request.url.startsWith('https://www.buynutbolts.com') ||
                request.url.startsWith('https://rfq.buynutbolts.com')) { 
              return NavigationDecision.navigate;
            }
            
            // Allow payment gateways
            if (request.url.contains('razorpay.com') || 
                request.url.contains('paypal.com')) {
               return NavigationDecision.navigate;
            }

            // Block everything else
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