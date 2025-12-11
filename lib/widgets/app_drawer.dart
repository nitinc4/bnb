import 'package:flutter/material.dart';
import '../api/magento_api.dart';
import '../models/magento_models.dart';
import '../screens/category_detail_screen.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    // Uses the static cache we built in Splash Screen
    final categories = MagentoAPI.cachedCategories;

    return Drawer(
      backgroundColor: Colors.white,
      child: Column(
        children: [
          UserAccountsDrawerHeader(
            decoration: const BoxDecoration(color: Color(0xFF00599c)),
            accountName: const Text("Welcome Guest"),
            accountEmail: const Text("Login to track orders"),
            currentAccountPicture: const CircleAvatar(
              backgroundColor: Colors.white,
              child: Icon(Icons.person, color: Color(0xFF00599c), size: 40),
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
                    // Add navigation to profile if needed
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
    // If it has subcategories, use ExpansionTile
    if (category.children.isNotEmpty) {
      return ExpansionTile(
        leading: const Icon(Icons.circle, size: 8, color: Color(0xFF00599c)),
        title: Text(category.name, style: const TextStyle(fontSize: 14)),
        childrenPadding: const EdgeInsets.only(left: 16),
        children: category.children.map((child) => _buildCategoryTile(context, child)).toList(),
      );
    } 
    // If it's a final category, navigate to details
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