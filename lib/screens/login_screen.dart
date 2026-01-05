// lib/screens/login_screen.dart
import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart'; 
import '../api/magento_api.dart';
import '../api/firebase_api.dart'; 
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
  bool _obscureText = true;
  final _storage = const FlutterSecureStorage();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter email and password"))
      );
      return;
    }

    setState(() => _isLoading = true);
    debugPrint("[App] Starting API Login...");

    final api = MagentoAPI();
    
    final token = await api.loginCustomer(email, password);

    if (token != null) {
      await _storage.write(key: 'customer_token', value: token);
      await FirebaseApi().syncTokenWithServer(email);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('has_logged_in', true);
      await prefs.setBool('is_guest', false);

      if (mounted) {
        setState(() => _isLoading = false);
        Navigator.pushReplacementNamed(context, '/home');
      }
    } else {
      debugPrint("[App] API Login Failed.");
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Invalid Credentials"))
        );
      }
    }
  }

  Future<void> _handleGuest() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_guest', true);
    await prefs.setBool('has_logged_in', false);
    await _storage.delete(key: 'customer_token'); 

    if (mounted) {
      Navigator.pushReplacementNamed(context, '/home');
    }
  }

  // [UPDATED] Forgot Password Dialog
  void _showForgotPasswordDialog() {
    final emailResetCtrl = TextEditingController();
    
    showDialog(
      context: context,
      barrierDismissible: false, 
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            // Local state variables for the dialog
            bool isSending = false;
            String? statusMessage;
            bool isSuccess = false;

            return _ForgotPasswordContent(); 
          },
        );
      }
    );
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
                        const Text("Login to continue", style: TextStyle(fontSize: 14, color: Colors.black87)),
                        const SizedBox(height: 32),

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
                        
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _showForgotPasswordDialog,
                            child: const Text("Forgot Password?", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                          ),
                        ),

                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity, height: 50,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _handleLogin,
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00599c), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                            child: _isLoading 
                              ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
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

// [NEW] Helper Widget to manage dialog state correctly
class _ForgotPasswordContent extends StatefulWidget {
  @override
  State<_ForgotPasswordContent> createState() => _ForgotPasswordContentState();
}

class _ForgotPasswordContentState extends State<_ForgotPasswordContent> {
  final TextEditingController _emailResetCtrl = TextEditingController();
  bool _isSending = false;
  String? _statusMessage;
  bool _isSuccess = false;

  @override
  void dispose() {
    _emailResetCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleSend() async {
    if (_emailResetCtrl.text.trim().isEmpty) {
      setState(() {
        _statusMessage = "Please enter an email.";
        _isSuccess = false;
      });
      return;
    }
    
    // Immediate Feedback
    setState(() {
      _isSending = true;
      _statusMessage = "Sending request...";
      _isSuccess = false;
    });

    final success = await MagentoAPI().initiatePasswordReset(_emailResetCtrl.text.trim());

    if (mounted) {
      setState(() {
        _isSending = false;
        _isSuccess = success;
        _statusMessage = success 
            ? "Success! Reset link sent." 
            : "Failed. Please check the email.";
      });

      if (success) {
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            Navigator.pop(context);
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text("Reset Password", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          if (!_isSending && !_isSuccess)
            IconButton(
              icon: const Icon(Icons.close, color: Colors.grey),
              onPressed: () => Navigator.pop(context),
            ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text("Enter your email address to receive a password reset link.", style: TextStyle(fontSize: 14, color: Colors.black54)),
          const SizedBox(height: 16),
          TextField(
            controller: _emailResetCtrl,
            decoration: InputDecoration(
              labelText: "Email Address",
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            keyboardType: TextInputType.emailAddress,
            enabled: !_isSending && !_isSuccess,
          ),
          const SizedBox(height: 16),
          
          // Status Feedback Area
          if (_isSending)
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00599c))),
                SizedBox(width: 12),
                Text("Processing...", style: TextStyle(color: Color(0xFF00599c), fontWeight: FontWeight.bold)),
              ],
            )
          else if (_statusMessage != null)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _isSuccess ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _statusMessage!,
                style: TextStyle(
                  color: _isSuccess ? Colors.green[700] : Colors.red[700],
                  fontWeight: FontWeight.bold
                ),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
      actions: [
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: (_isSending || _isSuccess) ? null : _handleSend,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00599c),
              disabledBackgroundColor: Colors.grey.shade400, // Explicit grey when disabled
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(
              _isSending ? "Please Wait..." : "Send Reset Link",
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }
}