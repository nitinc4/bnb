// lib/screens/product_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../models/magento_models.dart';
import '../providers/cart_provider.dart';
import '../api/magento_api.dart';

class ProductDetailScreen extends StatefulWidget {
  final Product product;

  const ProductDetailScreen({super.key, required this.product});

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  late Product _currentProduct;

  @override
  void initState() {
    super.initState();
    _currentProduct = widget.product;
  }

  Future<void> _onRefresh() async {
    // Fetch fresh details for this specific product using SKU
    final refreshedProduct = await MagentoAPI().fetchProductBySku(_currentProduct.sku);
    if (refreshedProduct != null && mounted) {
      setState(() {
        _currentProduct = refreshedProduct;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Product updated"), duration: Duration(milliseconds: 500)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(_currentProduct.name),
        actions: [
          Consumer<CartProvider>(
            builder: (_, cart, ch) => Stack(
              children: [
                IconButton(
                  icon: const Icon(Icons.shopping_cart_outlined),
                  onPressed: () => Navigator.pushNamed(context, '/cart'),
                ),
                if (cart.itemCount > 0)
                  Positioned(right: 8, top: 8, child: Container(padding: const EdgeInsets.all(4), decoration: const BoxDecoration(color: Color(0xFFF54336), shape: BoxShape.circle), child: Text('${cart.itemCount}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)))),
              ],
            ),
          )
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(), // Ensures refresh works even if content is short
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 300, width: double.infinity,
                child: CachedNetworkImage(
                  imageUrl: _currentProduct.imageUrl,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(color: Colors.grey.shade100),
                  errorWidget: (context, url, error) => const Icon(Icons.broken_image),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_currentProduct.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text("SKU: ${_currentProduct.sku}", style: TextStyle(color: Colors.grey.shade600)),
                    const SizedBox(height: 16),
                    Text("₹${_currentProduct.price.toStringAsFixed(2)}", style: const TextStyle(fontSize: 24, color: Color(0xFF00599c), fontWeight: FontWeight.w800)),
                    const SizedBox(height: 24),
                    const Text("Description", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 8),
                    Text(_currentProduct.description, style: const TextStyle(color: Colors.black54, height: 1.5)),
                    const SizedBox(height: 80), // Extra space for FAB/BottomBar
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: const Offset(0, -2))]),
        child: ElevatedButton(
          onPressed: () {
            Provider.of<CartProvider>(context, listen: false).addToCart(_currentProduct);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${_currentProduct.name} added to cart!"), backgroundColor: const Color(0xFF00599c), duration: const Duration(seconds: 1)));
          },
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00599c), padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          child: const Text("Add to Cart", style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
}