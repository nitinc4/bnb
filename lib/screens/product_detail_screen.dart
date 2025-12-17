// lib/screens/product_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../models/magento_models.dart';
import '../providers/cart_provider.dart';
import '../api/magento_api.dart';
import 'website_webview_screen.dart'; // Import WebView Screen

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
    if (_currentProduct.description.isEmpty) _fetchFullDetails();
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

  // --- NEW: Open RFQ Webview ---
  void _openRFQ() {
    // Construct URL with parameters
    final String rfqUrl = "https://rfq.buynutbolts.com/rfq.php"
        "?sku=${Uri.encodeComponent(_currentProduct.sku)}"
        "&name=${Uri.encodeComponent(_currentProduct.name)}"
        "&part=${Uri.encodeComponent(_currentProduct.sku)}"
        "&qty=1"
        "&url=${Uri.encodeComponent('https://buynutbolts.com')}"; // Fallback URL since slug is missing

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => WebsiteWebViewScreen(
          url: rfqUrl,
          title: "Request Quote",
        ),
      ),
    );
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
                    
                    // --- NEW: RFQ Button ---
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _openRFQ,
                        icon: const Icon(Icons.request_quote, color: Color(0xFF00599c)),
                        label: const Text("Request for Quote (Bulk Order)", style: TextStyle(color: Color(0xFF00599c), fontWeight: FontWeight.bold)),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          side: const BorderSide(color: Color(0xFF00599c)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

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
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: const Offset(0, -2))]),
        child: SafeArea(
          child: Row(
            children: [
              // 1. PRICE (Left)
              Expanded(
                flex: 2,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Price", style: TextStyle(fontSize: 12, color: Colors.grey)),
                    Text("₹${_currentProduct.price.toStringAsFixed(2)}", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF00599c))),
                  ],
                ),
              ),
              
              // 2. ACTION BUTTON (Right)
              Expanded(
                flex: 3,
                child: Consumer<CartProvider>(
                  builder: (context, cart, child) {
                    final cartItemIndex = cart.items.indexWhere((i) => i.sku == _currentProduct.sku);
                    final isInCart = cartItemIndex >= 0;
                    final qty = isInCart ? cart.items[cartItemIndex].qty : 0;
        
                    if (!isInCart) {
                      return ElevatedButton(
                        onPressed: () {
                          cart.addToCart(_currentProduct);
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${_currentProduct.name} added to cart!"), duration: const Duration(seconds: 1)));
                        },
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00599c), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                        child: const Text("Add to Cart", style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold)),
                      );
                    } else {
                      return Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(color: const Color(0xFF00599c), borderRadius: BorderRadius.circular(12)),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            InkWell(
                              onTap: () {
                                if (qty > 1) {
                                  cart.updateQty(cart.items[cartItemIndex], qty - 1);
                                } else {
                                  cart.removeFromCart(cart.items[cartItemIndex]);
                                }
                              },
                              child: const Icon(Icons.remove, color: Colors.white),
                            ),
                            Text("$qty", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                            InkWell(
                              onTap: () {
                                cart.updateQty(cart.items[cartItemIndex], qty + 1);
                              },
                              child: const Icon(Icons.add, color: Colors.white),
                            ),
                          ],
                        ),
                      );
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}