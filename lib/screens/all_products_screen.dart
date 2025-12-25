// lib/screens/all_products_screen.dart
import 'package:flutter/material.dart';
import '../api/magento_api.dart';
import '../models/magento_models.dart';
import '../widgets/product_card.dart';
import '../widgets/bnb_shimmer.dart'; // [NEW]

class AllProductsScreen extends StatefulWidget {
  const AllProductsScreen({super.key});

  @override
  State<AllProductsScreen> createState() => _AllProductsScreenState();
}

class _AllProductsScreenState extends State<AllProductsScreen> {
  final MagentoAPI _api = MagentoAPI();
  final List<Product> _products = [];
  
  bool _isLoading = false;
  int _currentPage = 1;
  bool _hasMore = true;
  final int _pageSize = 20;
  
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _fetchProducts();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoading && _hasMore) {
        _fetchProducts();
      }
    }
  }

  Future<void> _fetchProducts() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      final newProducts = await _api.fetchProducts(
        page: _currentPage,
        pageSize: _pageSize,
      );

      if (mounted) {
        setState(() {
          if (newProducts.isEmpty) {
            _hasMore = false;
          } else {
            _products.addAll(newProducts);
            _currentPage++;
          }
        });
      }
    } catch (e) {
      debugPrint("Error fetching all products: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("All Products", style: TextStyle(color: Color(0xFF00599c))),
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Color(0xFF00599c)),
        elevation: 1,
      ),
      body: _products.isEmpty && _isLoading
          ? BNBShimmer.productGrid() // [FIX] Use Shimmer
          : GridView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              itemCount: _products.length + (_hasMore ? 1 : 0),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 0.7,
              ),
              itemBuilder: (context, index) {
                if (index == _products.length) {
                  return const Center(child: CircularProgressIndicator());
                }
                final product = _products[index];
                return GestureDetector(
                  onTap: () {
                    Navigator.pushNamed(context, '/productDetail', arguments: product);
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