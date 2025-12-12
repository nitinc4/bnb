// lib/screens/categories_screen.dart
import 'package:flutter/material.dart';
import '../api/magento_api.dart';
import '../models/magento_models.dart';
import 'category_detail_screen.dart';

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  // We use a future here just to signal UI rebuilds, data comes from cache/network
  Future<void>? _refreshFuture;

  Future<void> _handleRefresh() async {
    await MagentoAPI().clearCache();
    setState(() {
      // Trigger a re-fetch in the background or just setState to rebuild
      // Since fetchCategories handles cache internally, calling it again updates it
      _refreshFuture = MagentoAPI().fetchCategories(); 
    });
    await _refreshFuture;
  }

  @override
  Widget build(BuildContext context) {
    // If we are just entering, we use cached data. If refreshing, we wait.
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Categories"),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 1,
      ),
      body: RefreshIndicator(
        onRefresh: _handleRefresh,
        color: const Color(0xFF00599c),
        child: FutureBuilder<List<Category>>(
          future: MagentoAPI().fetchCategories(), // Always calls API (which checks cache first)
          builder: (context, snapshot) {
            final categories = snapshot.data ?? MagentoAPI.cachedCategories;
            
            if (categories.isEmpty && snapshot.connectionState == ConnectionState.waiting) {
               return const Center(child: CircularProgressIndicator());
            }
            
            if (categories.isEmpty) {
              return const Center(child: Text("No categories loaded. Pull to refresh."));
            }

            return GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2, crossAxisSpacing: 16, mainAxisSpacing: 16, childAspectRatio: 0.9,
              ),
              itemCount: categories.length,
              itemBuilder: (context, index) {
                final cat = categories[index];
                return GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => CategoryDetailScreen(category: cat)),
                    );
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, 4))],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: cat.imageUrl != null 
                              ? Image.network(cat.imageUrl!, fit: BoxFit.contain)
                              : Image.asset("assets/icons/placeholder.png"),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12.0, left: 8, right: 8),
                          child: Text(cat.name, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF00599c), fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}