// lib/screens/login_screen.dart
import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../api/magento_api.dart';
import 'signup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  
  bool _isLoading = false;
  bool _isSyncingWebSession = false; 
  bool _obscureText = true;
  bool _hasAttemptedInjection = false;

  late final WebViewController _bgWebController;
  Timer? _urlPollingTimer; 

  @override
  void initState() {
    super.initState();
    _initializeBackgroundWebView();
  }

  @override
  void dispose() {
    _urlPollingTimer?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _initializeBackgroundWebView() {
    _bgWebController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setOnConsoleMessage((message) {
      debugPrint("[WebView Console]: ${message.message}");
      })
      ..addJavaScriptChannel(
        'LoginChannel',
        onMessageReceived: (JavaScriptMessage message) {
          if (message.message == 'success') {
            debugPrint("[JS Channel] Success Signal Received!");
            _onWebLoginSuccess();
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
             if (_isSyncingWebSession) _checkLoginSuccess(url);
          },
          onPageFinished: (String url) {
            if (_isSyncingWebSession) {
               
               if (_checkLoginSuccess(url)) return; 
               _startSuccessMonitor();
               if (url.contains('/customer/account/login') && !_hasAttemptedInjection) {
                 debugPrint(" [WebView] Login page loaded. Starting injection...");
                 _hasAttemptedInjection = true; 
                 _injectLoginCredentials();
               }
            }
          },
        ),
      );
  }

  bool _checkLoginSuccess(String url) {
    bool isDashboard = url.contains('/customer/account/') && !url.contains('login');
    bool isHome = url == 'https://buynutbolts.com/' || url == 'https://buynutbolts.com';
    bool isCheckout = url.contains('/checkout/'); 

    if (isDashboard || isHome || isCheckout) {
       debugPrint(" [WebView] Login Success Detected! URL: $url");
       _onWebLoginSuccess();
       return true;
    }
    return false;
  }

  void _startSuccessMonitor() {
    _bgWebController.runJavaScript("""
      (function() {
          var checkInterval = setInterval(function() {
              var url = window.location.href;
              var bodyText = document.body.innerText;
              
              var isSuccessUrl = (url.includes('/customer/account/') && !url.includes('login')) || 
                                 url.includes('/checkout/') || 
                                 url === 'https://buynutbolts.com/';
              
              var hasWelcome = bodyText.includes('Welcome,') || bodyText.includes('Sign Out') || bodyText.includes('My Dashboard');

              if (isSuccessUrl || hasWelcome) {
                  if(window.LoginChannel) {
                      window.LoginChannel.postMessage('success');
                      clearInterval(checkInterval);
                  }
              }
          }, 500);
      })();
    """);
  }

  void _injectLoginCredentials() {
    if (!_isSyncingWebSession) return;

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    _bgWebController.runJavaScript("""
      (function() {
        console.log(" Starting Auto-Login Script...");
        var attempts = 0;

        function tryLogin() {
          attempts++;
          if (attempts > 30) return;

          // Try various selectors
          var emailInput = document.getElementById('email') || document.querySelector('input[name="login[username]"]');
          var passInput = document.getElementById('pass') || document.querySelector('input[name="login[password]"]');
          var btn = document.getElementById('send2') || document.querySelector('button.action.login.primary');

          if (emailInput && passInput) {
             console.log("Inputs found.");

             // Fill & Trigger Events
             emailInput.value = '$email';
             emailInput.dispatchEvent(new Event('input'));
             emailInput.dispatchEvent(new Event('change'));

             passInput.value = '$password';
             passInput.dispatchEvent(new Event('input'));
             passInput.dispatchEvent(new Event('change'));

             // Click Login
             setTimeout(function() {
                if (btn) {
                   if(btn.disabled) btn.removeAttribute('disabled');
                   btn.click();
                } else if (document.forms.length > 0) {
                   document.forms[0].submit();
                }
             }, 500);

          } else {
             setTimeout(tryLogin, 500);
          }
        }

        tryLogin();
      })();
    """);
  }

  void _onWebLoginSuccess() {
    if (!_isSyncingWebSession || !mounted) return;
    _urlPollingTimer?.cancel();
    
    setState(() { _isSyncingWebSession = false; });

    debugPrint("[App] Synced. Navigating Home.");
    Navigator.pushReplacementNamed(context, '/home');
  }

  Future<void> _handleLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please enter email and password")));
      return;
    }

    setState(() => _isLoading = true);
    debugPrint("[App] Starting API Login...");

    final api = MagentoAPI();
    final token = await api.loginCustomer(email, password);

    if (token != null) {
      debugPrint("[App] API Login Success.");
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('customer_token', token);
      await prefs.setBool('has_logged_in', true);
      await prefs.setBool('is_guest', false);

      if (mounted) {
        setState(() {
          _isLoading = false;
          _isSyncingWebSession = true; 
          _hasAttemptedInjection = false;
        });
        
        await _bgWebController.clearCache();
        final cookieManager = WebViewCookieManager();
        await cookieManager.clearCookies();

        debugPrint("[App] Loading Website Login...");
        _bgWebController.loadRequest(Uri.parse('https://buynutbolts.com/customer/account/login/'));
        
        // Backup Poller
        _urlPollingTimer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
           if(mounted && _isSyncingWebSession) {
             final url = await _bgWebController.currentUrl();
             if(url != null) _checkLoginSuccess(url);
           }
        });

        // 15s Timeout
        Future.delayed(const Duration(seconds: 15), () {
          if (mounted && _isSyncingWebSession) {
             debugPrint("[App] Web sync timed out. Proceeding.");
             _onWebLoginSuccess();
          }
        });
      }
    } else {
      debugPrint("[App] API Login Failed.");
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Invalid Credentials")));
      }
    }
  }

  Future<void> _handleGuest() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_guest', true);
    await prefs.setBool('has_logged_in', false);
    await prefs.remove('customer_token'); 

    if (mounted) {
      Navigator.pushReplacementNamed(context, '/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/images/login_bg.png', fit: BoxFit.cover),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.black.withOpacity(0.3), Colors.white.withOpacity(0.3)],
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
              ),
            ),
          ),
          
          Positioned(
            bottom: 0, right: 0,
            width: 1, height: 1, 
            child: WebViewWidget(controller: _bgWebController),
          ),

          Center(
            child: SingleChildScrollView(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: Container(
                    width: MediaQuery.of(context).size.width * 0.9,
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.25),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white.withOpacity(0.3), width: 1.2),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20)],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text("Welcome", style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Color(0xFF00599c))),
                        const SizedBox(height: 6),
                        Text(
                          _isSyncingWebSession ? "Syncing session..." : "Login to continue", 
                          style: TextStyle(fontSize: 14, color: _isSyncingWebSession ? const Color(0xFF00599c) : Colors.black87, fontWeight: _isSyncingWebSession ? FontWeight.bold : FontWeight.normal)
                        ),
                        const SizedBox(height: 32),

                        if (_isSyncingWebSession)
                           Column(
                             children: [
                               const CircularProgressIndicator(color: Color(0xFF00599c)),
                               const SizedBox(height: 16),
                               
                             ],
                           )
                        else ...[
                          TextField(
                            controller: _emailController,
                            decoration: InputDecoration(
                              hintText: 'Email Address',
                              prefixIcon: const Icon(Icons.email_outlined, color: Color(0xFF00599c)),
                              filled: true, fillColor: Colors.white.withOpacity(0.8),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                            ),
                          ),
                          const SizedBox(height: 18),
                          TextField(
                            controller: _passwordController,
                            obscureText: _obscureText,
                            decoration: InputDecoration(
                              hintText: 'Password',
                              prefixIcon: const Icon(Icons.lock_outline, color: Color(0xFF00599c)),
                              suffixIcon: IconButton(
                                icon: Icon(_obscureText ? Icons.visibility_off : Icons.visibility),
                                onPressed: () => setState(() => _obscureText = !_obscureText),
                              ),
                              filled: true, fillColor: Colors.white.withOpacity(0.8),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                            ),
                          ),
                          const SizedBox(height: 28),
                          SizedBox(
                            width: double.infinity, height: 50,
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _handleLogin,
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00599c), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                              child: _isLoading 
                                ? const CircularProgressIndicator(color: Colors.white) 
                                : const Text("Login", style: TextStyle(color: Colors.white, fontSize: 16)),
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity, height: 50,
                            child: OutlinedButton(
                              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SignupScreen())),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Color(0xFF00599c), width: 1.5),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                              child: const Text("Create Account", style: TextStyle(color: Color(0xFF00599c), fontSize: 16, fontWeight: FontWeight.bold)),
                            ),
                          ),
                          const SizedBox(height: 24),
                          GestureDetector(
                            onTap: _handleGuest,
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: const Text("Continue as Guest", style: TextStyle(fontWeight: FontWeight.w600, decoration: TextDecoration.underline)),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}