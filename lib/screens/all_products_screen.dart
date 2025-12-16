// lib/screens/all_products_screen.dart
import 'package:flutter/material.dart';
import '../api/magento_api.dart';
import '../models/magento_models.dart';
import '../widgets/product_card.dart';
import 'product_detail_screen.dart';

class AllProductsScreen extends StatefulWidget {
  const AllProductsScreen({super.key});

  @override
  State<AllProductsScreen> createState() => _AllProductsScreenState();
}

class _AllProductsScreenState extends State<AllProductsScreen> {
  final List<Product> _products = [];
  bool _isLoading = false;
  bool _hasMore = true;
  int _page = 1;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _fetchProducts();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      _fetchProducts();
    }
  }

  Future<void> _fetchProducts() async {
    if (_isLoading || !_hasMore) return;

    setState(() {
      _isLoading = true;
    });

    // Fetch page by page
    final newProducts = await MagentoAPI().fetchProducts(page: _page);

    if (mounted) {
      setState(() {
        if (newProducts.isEmpty) {
          _hasMore = false;
        } else {
          _products.addAll(newProducts);
          _page++;
        }
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("All Products", style: TextStyle(color: Color(0xFF00599c), fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF00599c)),
      ),
      body: _products.isEmpty && _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00599c)))
          : GridView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _products.length + (_hasMore ? 1 : 0),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.7,
              ),
              itemBuilder: (context, index) {
                if (index == _products.length) {
                  return const Center(
                    child: CircularProgressIndicator(color: Color(0xFF00599c)),
                  );
                }
                
                final product = _products[index];
                return GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => ProductDetailScreen(product: product)),
                    );
                  },
                  child: ProductCard(
                    name: product.name,
                    price: product.price.toStringAsFixed(2),
                    imageUrl: product.imageUrl,
                  ),
                );
              },
            ),
    );
  }
}