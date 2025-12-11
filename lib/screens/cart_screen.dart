import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/cart_provider.dart';
import '../models/magento_models.dart';
import 'checkout_screen.dart';

class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          "Your Cart",
          style: TextStyle(
            color: Color(0xFF00599c),
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Color(0xFF00599c)),
        elevation: 1,
        actions: [
          // Optional: Clear Cart Button
          Consumer<CartProvider>(
            builder: (_, cart, __) => cart.items.isEmpty 
              ? const SizedBox()
              : IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.grey),
                  onPressed: () {
                    cart.clearCart();
                  },
                ),
          ),
        ],
      ),
      // Use Consumer to rebuild UI when cart changes
      body: Consumer<CartProvider>(
        builder: (context, cart, child) {
          if (cart.items.isEmpty) {
            return _buildEmptyCart();
          }

          // 1. Group items by SKU to calculate Quantity
          final groupedItems = <String, List<Product>>{};
          for (var item in cart.items) {
            if (!groupedItems.containsKey(item.sku)) {
              groupedItems[item.sku] = [];
            }
            groupedItems[item.sku]!.add(item);
          }
          
          final uniqueSkuList = groupedItems.keys.toList();

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
            itemCount: uniqueSkuList.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final sku = uniqueSkuList[index];
              final productList = groupedItems[sku]!;
              final product = productList.first;
              final quantity = productList.length;

              return Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
                child: ListTile(
                  contentPadding: const EdgeInsets.all(12),
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: CachedNetworkImage(
                      imageUrl: product.imageUrl,
                      width: 60,
                      height: 60,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(color: Colors.grey.shade200),
                      errorWidget: (context, url, error) => const Icon(Icons.broken_image),
                    ),
                  ),
                  title: Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  subtitle: Text(
                    "₹${product.price.toStringAsFixed(2)}",
                    style: const TextStyle(
                      color: Colors.black54,
                      fontSize: 14,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Decrease Qty
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: () {
                          cart.removeFromCart(product);
                        },
                      ),
                      // Count
                      Text(
                        "$quantity",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF00599c),
                          fontSize: 16,
                        ),
                      ),
                      // Increase Qty
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline,
                            color: Color(0xFF00599c)),
                        onPressed: () {
                          cart.addToCart(product);
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      bottomNavigationBar: Consumer<CartProvider>(
        builder: (context, cart, child) {
           return SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: IntrinsicHeight(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 8,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            "Total:",
                            style: TextStyle(fontSize: 18, color: Colors.black54),
                          ),
                          Text(
                            "₹${cart.totalAmount.toStringAsFixed(2)}",
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF00599c),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: cart.items.isEmpty
                            ? null
                            : () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => CheckoutScreen(total: cart.totalAmount),
                                  ),
                                );
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00599c),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 3,
                          minimumSize: const Size(double.infinity, 50),
                        ),
                        child: const Text(
                          "Proceed to Checkout",
                          style: TextStyle(color: Colors.white, fontSize: 16),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
      ),
    );
  }

  // Empty Cart UI
  Widget _buildEmptyCart() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.shopping_cart_outlined, size: 100, color: Colors.grey),
            const SizedBox(height: 20),
            const Text(
              "Your cart is empty",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "Looks like you haven’t added anything yet.",
              style: TextStyle(color: Colors.black54),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}