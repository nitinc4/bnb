import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/magento_api.dart';
import 'signup_screen.dart'; // Import the new screen

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

  Future<void> _handleLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter email and password")),
      );
      return;
    }

    setState(() => _isLoading = true);

    // Call Real API
    final api = MagentoAPI();
    final token = await api.loginCustomer(email, password);

    if (token != null) {
      // SUCCESS: Save Token & State
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('customer_token', token);
      await prefs.setBool('has_logged_in', true);
      await prefs.setBool('is_guest', false);

      if (mounted) {
        Navigator.pushReplacementNamed(context, '/home');
      }
    } else {
      // FAILURE
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Invalid Credentials")),
        );
      }
    }
  }

  Future<void> _handleGuest() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_guest', true);
    await prefs.setBool('has_logged_in', false);
    // Clear any old tokens just in case
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
                        const Text("Welcome Back", style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Color(0xFF00599c))),
                        const SizedBox(height: 6),
                        const Text("Login to continue", style: TextStyle(fontSize: 14, color: Colors.black87)),
                        const SizedBox(height: 32),

                        // Inputs
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

                        // Login Button
                        SizedBox(
                          width: double.infinity, height: 50,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _handleLogin,
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00599c), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                            child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text("Login", style: TextStyle(color: Colors.white, fontSize: 16)),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Create Account Button
                        SizedBox(
                          width: double.infinity, height: 50,
                          child: OutlinedButton(
                            onPressed: () {
                              Navigator.push(context, MaterialPageRoute(builder: (_) => const SignupScreen()));
                            },
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFF00599c), width: 1.5),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            child: const Text("Create Account", style: TextStyle(color: Color(0xFF00599c), fontSize: 16, fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Guest
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