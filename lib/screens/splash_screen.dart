// lib/screens/splash_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/cart_provider.dart';
import '../api/magento_api.dart';
import 'home_screen.dart';
import 'login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: const Duration(seconds: 2), vsync: this)..repeat(reverse: true);
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await _loadResourcesAndNavigate();
  }


  Future<void> _loadResourcesAndNavigate() async {
    final api = MagentoAPI();
    final cart = Provider.of<CartProvider>(context, listen: false);

    try {
      debugPrint("[SplashScreen] Starting Cache Warm-up...");
      
      await api.warmUpHomeData();
      
      await cart.fetchCart();
      await Future.delayed(const Duration(seconds: 1)); // Small delay for effect

      final prefs = await SharedPreferences.getInstance();
      final hasLoggedIn = prefs.getBool('has_logged_in') ?? false;
      final isGuest = prefs.getBool('is_guest') ?? false;
      
      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => (hasLoggedIn || isGuest) ? const HomeScreen() : const LoginScreen(),
        ),
      );
    } catch (e) {
      debugPrint('Splash init error: $e');
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/login_bg.png',
            fit: BoxFit.cover,
            color: Colors.white.withOpacity(0.9),
            colorBlendMode: BlendMode.modulate,
          ),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FadeTransition(
                  opacity: _animation,
                  child: const Text(
                    'BNB STORE',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF00599c),
                      letterSpacing: 2,
                    ),
                  ),
                ),
                const SizedBox(height: 30),
                const CircularProgressIndicator(color: Color(0xFF00599c)),
                const SizedBox(height: 10),
                const Text('Initializing...', style: TextStyle(color: Colors.grey)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}