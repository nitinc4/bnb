import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart'; // Import Provider
import 'screens/support_screen.dart';
import 'providers/cart_provider.dart';
import 'models/magento_models.dart';

import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/product_detail_screen.dart';
import 'screens/cart_screen.dart';

import 'screens/order_success_screen.dart';
import 'screens/categories_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");

  runApp(
    ChangeNotifierProvider(
      create: (context) => CartProvider(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BNB Store',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00599c),
          primary: const Color(0xFF00599c),
          secondary: const Color(0xFFF54336),
          surface: Colors.white,
        ),
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(color: Color(0xFF00599c), fontWeight: FontWeight.bold, fontSize: 20),
          iconTheme: IconThemeData(color: Color(0xFF00599c)),
        ),
      ),
      initialRoute: '/splash',
      routes: {
        '/splash': (context) => const SplashScreen(),
        '/login': (context) => const LoginScreen(),
        '/home': (context) => const HomeScreen(),
        '/cart': (context) => const CartScreen(),
        '/categories': (context) => const CategoriesScreen(),
        '/support': (context) => const SupportScreen(isEmbedded: false),
      },
      onGenerateRoute: (settings) {
        if (settings.name == '/productDetail') {
          final product = settings.arguments as Product;
          return MaterialPageRoute(
            builder: (context) => ProductDetailScreen(product: product),
          );
        }
       
        if (settings.name == '/orderSuccess') {
          final amount = settings.arguments as double;
          return MaterialPageRoute(
            builder: (context) => OrderSuccessScreen(amount: amount),
          );
        }
        return null;
      },
    );
  }
}