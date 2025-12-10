import 'package:flutter/material.dart';
import '../api/magento_api.dart'; // Import API
import 'login_screen.dart'; // Or HomeScreen if you skip login

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
      duration: const Duration(seconds: 2), // Faster animation loop
      vsync: this,
    )..repeat(reverse: true); // Loop the fade effect while loading

    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);

    // START LOADING REAL DATA
    _loadData();
  }

  Future<void> _loadData() async {
    final api = MagentoAPI();
    
    // Fetch both simultaneously to save time
    try {
      print("Splash: Starting data fetch...");
      await Future.wait([
        api.fetchCategories(),
        api.fetchProducts(),
      ]);
      print("Splash: Data loaded!");
    } catch (e) {
      print("Splash: Error loading data (proceeding anyway): $e");
    }

    // Navigate only after data is ready
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/login'); 
      // OR if you want to go straight to home: Navigator.pushReplacementNamed(context, '/home');
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
          // Background Image
          Image.asset(
            'assets/images/login_bg.png',
            fit: BoxFit.cover,
            color: Colors.white.withOpacity(0.9), // Lighten it slightly
            colorBlendMode: BlendMode.modulate,
          ),
          
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo or Title
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
                
                // Real Loading Indicator
                const CircularProgressIndicator(
                  color: Color(0xFF00599c),
                ),
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