// lib/screens/splash_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Import this
import '../api/magento_api.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);

    // Load Data AND Check Login State
    _loadDataAndNavigate();
  }

  Future<void> _loadDataAndNavigate() async {
    final api = MagentoAPI();
    
    try {
      print("Splash: Starting data fetch...");
      // 1. Fetch Catalog Data
      await Future.wait([
        api.fetchCategories(),
        api.fetchProducts(),
      ]);
      print("Splash: Data loaded!");

      // 2. Check Login/Guest State
      final prefs = await SharedPreferences.getInstance();
      final bool hasLoggedIn = prefs.getBool('has_logged_in') ?? false;
      final bool isGuest = prefs.getBool('is_guest') ?? false;

      if (mounted) {
        // 3. Navigate Logic
        if (hasLoggedIn || isGuest) {
          // User is known (Logged in OR Guest) -> Go Home
          Navigator.pushReplacementNamed(context, '/home');
        } else {
          // First time / Not logged in -> Go Login
          Navigator.pushReplacementNamed(context, '/login');
        }
      }
    } catch (e) {
      print("Splash: Error loading data: $e");
      // Safety fallback -> Login
      if (mounted) Navigator.pushReplacementNamed(context, '/login');
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
                    "BNB STORE",
                    style: TextStyle(
                      fontSize: 32, 
                      fontWeight: FontWeight.bold, 
                      color: Color(0xFF00599c),
                      letterSpacing: 2
                    ),
                  ),
                ),
                const SizedBox(height: 30),
                const CircularProgressIndicator(color: Color(0xFF00599c)),
                const SizedBox(height: 10),
                const Text("Loading Catalog...", style: TextStyle(color: Colors.grey)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}