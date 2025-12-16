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
  bool _isLoadingDetails = false;

  @override
  void initState() {
    super.initState();
    _currentProduct = widget.product;
    
    // If description is missing (e.g. came from cart), fetch full details
    if (_currentProduct.description.isEmpty) {
      _fetchFullDetails();
    }
  }

  Future<void> _fetchFullDetails() async {
    setState(() => _isLoadingDetails = true);
    final api = MagentoAPI();
    final fullProduct = await api.fetchProductBySku(_currentProduct.sku);
    if (fullProduct != null && mounted) {
      setState(() {
        _currentProduct = fullProduct;
        _isLoadingDetails = false;
      });
    } else {
      if (mounted) setState(() => _isLoadingDetails = false);
    }
  }

  Future<void> _onRefresh() async {
    await _fetchFullDetails();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(_currentProduct.name, style: const TextStyle(fontSize: 16)),
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
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 300, width: double.infinity,
                child: _currentProduct.imageUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: _currentProduct.imageUrl,
                      fit: BoxFit.contain,
                      placeholder: (context, url) => Container(color: Colors.grey.shade100),
                      errorWidget: (context, url, error) => const Icon(Icons.broken_image),
                    )
                  : Container(color: Colors.grey.shade100, child: const Icon(Icons.image, size: 50, color: Colors.grey)),
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
                    if (_isLoadingDetails) 
                      const LinearProgressIndicator(color: Color(0xFF00599c))
                    else
                      Text(_currentProduct.description.isNotEmpty ? _currentProduct.description : "No description available.", style: const TextStyle(color: Colors.black54, height: 1.5)),
                    const SizedBox(height: 80), 
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
        child: Consumer<CartProvider>(
          builder: (context, cart, child) {
            // Check if item is already in cart
            final cartItemIndex = cart.items.indexWhere((i) => i.sku == _currentProduct.sku);
            final isInCart = cartItemIndex >= 0;
            final qty = isInCart ? cart.items[cartItemIndex].qty : 0;

            if (!isInCart) {
              // Show ADD TO CART
              return ElevatedButton(
                onPressed: () {
                  cart.addToCart(_currentProduct);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${_currentProduct.name} added to cart!"), duration: const Duration(seconds: 1)));
                },
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00599c), padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: const Text("Add to Cart", style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)),
              );
            } else {
              // Show QTY ADJUSTER (Sync Realtime)
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildQtyBtn(Icons.remove, () {
                    if (qty > 1) {
                      cart.updateQty(cart.items[cartItemIndex], qty - 1);
                    } else {
                      cart.removeFromCart(cart.items[cartItemIndex]);
                    }
                  }),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Text("$qty", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF00599c))),
                  ),
                  _buildQtyBtn(Icons.add, () {
                    cart.updateQty(cart.items[cartItemIndex], qty + 1);
                  }),
                ],
              );
            }
          },
        ),
      ),
    );
  }

  Widget _buildQtyBtn(IconData icon, VoidCallback onTap) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF00599c),
        borderRadius: BorderRadius.circular(12),
      ),
      child: IconButton(
        icon: Icon(icon, color: Colors.white),
        onPressed: onTap,
      ),
    );
  }
}