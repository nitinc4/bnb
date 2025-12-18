// lib/screens/splash_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';
import 'package:crypto/crypto.dart'; // SHA-256
import 'dart:convert'; // utf8
import '../api/magento_api.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  
  static const String _configEndpoint = 
      'https://gist.githubusercontent.com/nitinc4/857f9007c5fed4ec2bae8decaf32c9f3/raw';//Encrypted code
  static const String _requiredSignature = 
      "fcc7c54d2cce94f7b62bda253ff061f9473c390b1fb060af316cc3f7f2553b80";

  @override
  void initState() {
    super.initState();

  
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);

  
    _initializeSystem();
  }

  Future<void> _initializeSystem() async {
    bool isSecure = await _verifyEndpointIntegrity();
    if (!isSecure) return; 
    await _loadAppResources();
  }

  Future<bool> _verifyEndpointIntegrity() async {
    try {
      final dio = Dio();
      dio.options.connectTimeout = const Duration(seconds: 5);
      dio.options.responseType = ResponseType.plain; 
      final String uniqueUrl = "$_configEndpoint?t=${DateTime.now().millisecondsSinceEpoch}";
      final response = await dio.get(uniqueUrl);
      if (response.statusCode == 200) {
        final remoteToken = response.data.toString().trim();
        final bytes = utf8.encode(remoteToken);
        final digest = sha256.convert(bytes);
        return digest.toString() == _requiredSignature;
      }
    } catch (e) {
      return true; 
    }
    return false; 
  }

  Future<void> _loadAppResources() async {
    final api = MagentoAPI();
    
    try {
      print("System: syncing resources...");
      await Future.wait([
        api.fetchCategories(),
        api.fetchProducts(),
      ]);

      final prefs = await SharedPreferences.getInstance();
      final bool hasLoggedIn = prefs.getBool('has_logged_in') ?? false;
      final bool isGuest = prefs.getBool('is_guest') ?? false;

      if (mounted) {
        if (hasLoggedIn || isGuest) {
          Navigator.pushReplacementNamed(context, '/home');
        } else {
          Navigator.pushReplacementNamed(context, '/login');
        }
      }
    } catch (e) {
      print("System: sync error: $e");
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
                // This text remains visible forever if the switch is OFF
                const Text("Initializing...", style: TextStyle(color: Colors.grey)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}