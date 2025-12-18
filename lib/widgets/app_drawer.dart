// lib/widgets/app_drawer.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/magento_api.dart';
import '../models/magento_models.dart';
import '../screens/category_detail_screen.dart';
import '../screens/all_products_screen.dart'; 
import '../screens/website_webview_screen.dart';

class AppDrawer extends StatefulWidget {
  const AppDrawer({super.key});

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  String _accountName = "Welcome Guest";
  String _accountEmail = "Login to track orders";
  
  @override
  void initState() {
    super.initState();
    _loadUserInstant();
  }

  // --- FAST LOAD STRATEGY ---
  Future<void> _loadUserInstant() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('customer_token');

    if (token != null) {
      // Try Memory Cache (Fastest - Immediate)
      if (MagentoAPI.cachedUser != null) {
        _updateUi(MagentoAPI.cachedUser!);
      } 
      // Try Disk Cache (Fast - persisted across restarts)
      else if (prefs.containsKey('cached_user_data')) {
        try {
          final data = jsonDecode(prefs.getString('cached_user_data')!);
          _updateUi(data);
          MagentoAPI.cachedUser = data; // Sync memory
        } catch (e) {
          // ignore error
        }
      }

      // 3. Background Refresh 
      try {
        final api = MagentoAPI();
        final user = await api.fetchCustomerDetails(token);
        if (user != null && mounted) {
          _updateUi(user);
        }
      } catch (e) {
        // ignore network errors, keep showing cached data
      }
    }
  }

  void _updateUi(Map<String, dynamic> user) {
    if (!mounted) return;
    setState(() {
      _accountName = "${user['firstname']} ${user['lastname']}";
      _accountEmail = user['email'] ?? "";
    });
  }

  @override
  Widget build(BuildContext context) {
    final categories = MagentoAPI.cachedCategories;

    return Drawer(
      backgroundColor: Colors.white,
      child: Column(
        children: [
          UserAccountsDrawerHeader(
            decoration: const BoxDecoration(color: Color(0xFF00599c)),
            accountName: Text(
              _accountName, 
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)
            ),
            accountEmail: Text(_accountEmail),
            currentAccountPicture: CircleAvatar(
              backgroundColor: Colors.white,
              child: Text(
                _accountName.isNotEmpty && _accountName != "Welcome Guest" 
                    ? _accountName[0].toUpperCase() 
                    : "G",
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF00599c)),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                // Standard Pages
                ListTile(
                  leading: const Icon(Icons.home_outlined),
                  title: const Text('Home'),
                  onTap: () => Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false),
                ),
                
                // All Products
                ListTile(
                  leading: const Icon(Icons.grid_view),
                  title: const Text('All Products'),
                  onTap: () {
                    Navigator.pop(context); // Close drawer
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const AllProductsScreen()),
                    );
                  },
                ),

                ListTile(
                  leading: const Icon(Icons.shopping_cart_outlined),
                  title: const Text('Cart'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/cart');
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: const Text('Profile'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/profile');
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('About Us'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const WebsiteWebViewScreen(
                          title: "About Us",
                          url: "https://buynutbolts.com/about-us",
                        ),
                      ),
                    );
                  },
                ),
                const Divider(),
                const Padding(
                  padding: EdgeInsets.only(left: 16, top: 10, bottom: 10),
                  child: Text("CATEGORIES", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                ),
                
                // Recursive Categories List
                if (categories.isEmpty)
                  const Padding(padding: EdgeInsets.all(16), child: Text("No categories loaded"))
                else
                  ...categories.map((cat) => _buildCategoryTile(context, cat)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryTile(BuildContext context, Category category) {
    if (category.children.isNotEmpty) {
      return ExpansionTile(
        leading: const Icon(Icons.circle, size: 8, color: Color(0xFF00599c)),
        title: Text(category.name, style: const TextStyle(fontSize: 14)),
        childrenPadding: const EdgeInsets.only(left: 16),
        children: category.children.map((child) => _buildCategoryTile(context, child)).toList(),
      );
    } 
    else {
      return ListTile(
        title: Text(category.name, style: const TextStyle(fontSize: 14)),
        onTap: () {
          Navigator.pop(context); // Close drawer
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CategoryDetailScreen(category: category),
            ),
          );
        },
      );
    }
  }
}