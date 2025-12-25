// lib/screens/website_webview_screen.dart
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class WebsiteWebViewScreen extends StatefulWidget {
  final String url;
  final String title;
  final Map<String, String>? headers; // [FIX] Accept headers

  const WebsiteWebViewScreen({
    super.key, 
    this.url = 'https://buynutbolts.com', 
    this.title = 'BuyNutBolts Website',
    this.headers,
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

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..enableZoom(true)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {},
          onPageStarted: (String url) {
            if (mounted) setState(() => _isLoading = true);
          },
          onPageFinished: (String url) {
            if (mounted) {
              if (url.contains('/mobile/auth/login')) {
                return;
              }
              setState(() => _isLoading = false);
            }
          },
          onNavigationRequest: (NavigationRequest request) {
            if (request.url.contains('/mobile/auth/login')) {
              return NavigationDecision.navigate;
            }
            if (request.url.startsWith('https://buynutbolts.com') || 
                request.url.startsWith('https://www.buynutbolts.com') ||
                request.url.startsWith('https://rfq.buynutbolts.com')) { 
              return NavigationDecision.navigate;
            }
            if (request.url.contains('razorpay.com') || 
                request.url.contains('paypal.com')) {
               return NavigationDecision.navigate;
            }
            return NavigationDecision.prevent;
          },
        ),
      )
      // [FIX] Load request with headers
      ..loadRequest(Uri.parse(widget.url), headers: widget.headers ?? {});
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
            Container(
              color: Colors.white,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Color(0xFF00599c)),
                    SizedBox(height: 16),
                    Text("Securely logging you in...", style: TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}