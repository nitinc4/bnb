// lib/screens/cart_screen.dart
import 'package:bnb/screens/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart'; 
import '../providers/cart_provider.dart';
import '../models/magento_models.dart';
import 'product_detail_screen.dart';
import 'website_webview_screen.dart'; 

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final _storage = const FlutterSecureStorage();
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<CartProvider>(context, listen: false).fetchCart();
    });
  }

  Future<void> _handleCheckout(BuildContext context, double total) async {
    final token = await _storage.read(key: 'customer_token');

    if (token != null && token.isNotEmpty) {
      // [FIX] Reverted to URL Parameter because server expects 'input_token' in the URL.
      // Headers are cleaner, but the server script must support them.
      final String bridgeUrl = "https://buynutbolts.com/mobile/auth/login?input_token=$token"; 

      debugPrint("Launching Checkout Bridge: $bridgeUrl");

      Navigator.push(
        context, 
        MaterialPageRoute(
          builder: (_) => WebsiteWebViewScreen(
            url: bridgeUrl, 
            title: "Checkout",
            // We don't pass headers here anymore as we are using the URL param
          )
        )
      );
    } else {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Sign In Required"),
          content: const Text("Please sign in to sync your cart and proceed to checkout."),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const LoginScreen()), (route) => false);
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00599c)),
              child: const Text("Go to Sign In", style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Your Cart", style: TextStyle(color: Color(0xFF00599c), fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Color(0xFF00599c)),
        elevation: 1,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF00599c)),
            onPressed: () => Provider.of<CartProvider>(context, listen: false).fetchCart(),
          ),
        ],
      ),
      body: Consumer<CartProvider>(
        builder: (context, cart, child) {
          if (cart.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (cart.items.isEmpty) {
            return _buildEmptyCart();
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
            itemCount: cart.items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final item = cart.items[index];
              return GestureDetector(
                onTap: () {
                  final product = Product(
                    name: item.name,
                    sku: item.sku,
                    price: item.price,
                    imageUrl: item.imageUrl ?? "",
                    description: "", 
                    
                  );
                  Navigator.push(
                    context, 
                    MaterialPageRoute(builder: (_) => ProductDetailScreen(product: product))
                  );
                },
                child: Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 2,
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(12),
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: item.imageUrl != null && item.imageUrl!.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: item.imageUrl!,
                            width: 60, height: 60, fit: BoxFit.cover,
                            placeholder: (context, url) => Container(color: Colors.grey.shade100),
                            errorWidget: (context, url, error) => const Icon(Icons.broken_image),
                          )
                        : Container(width: 60, height: 60, color: Colors.grey.shade200, child: const Icon(Icons.image, color: Colors.grey)),
                    ),
                    title: Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text("₹${item.price.toStringAsFixed(2)}", style: const TextStyle(color: Colors.black54)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: () {
                          if(item.qty > 1) {
                            cart.updateQty(item, item.qty - 1);
                          } else {
                            cart.removeFromCart(item);
                          }
                        }),
                        Text("${item.qty}", style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00599c), fontSize: 16)),
                        IconButton(icon: const Icon(Icons.add_circle_outline, color: Color(0xFF00599c)), onPressed: () => cart.updateQty(item, item.qty + 1)),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
      bottomNavigationBar: Consumer<CartProvider>(builder: (context, cart, child) {
         return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: IntrinsicHeight(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                // ignore: deprecated_member_use
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, -2))]),
                child: Column(
                  mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      const Text("Total:", style: TextStyle(fontSize: 18, color: Colors.black54)),
                      Text("₹${cart.totalAmount.toStringAsFixed(2)}", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF00599c))),
                    ]),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: cart.items.isEmpty ? null : () => _handleCheckout(context, cart.totalAmount),
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00599c), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 3, minimumSize: const Size(double.infinity, 50)),
                      child: const Text("Proceed to Checkout", style: TextStyle(color: Colors.white, fontSize: 16)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildEmptyCart() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.shopping_cart_outlined, size: 100, color: Colors.grey),
            const SizedBox(height: 20),
            const Text("Your cart is empty", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.black87)),
            const SizedBox(height: 8),
            const Text("Looks like you haven’t added anything yet.", style: TextStyle(color: Colors.black54), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}