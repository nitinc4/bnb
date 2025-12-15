import 'package:flutter/material.dart';
import '../api/magento_api.dart';
import '../models/magento_models.dart';
import 'order_detail_screen.dart';

class OrdersScreen extends StatefulWidget {
  final String userEmail;
  const OrdersScreen({super.key, required this.userEmail});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  late Future<List<Order>> _ordersFuture;

  @override
  void initState() {
    super.initState();
    // Fetch up to 20 recent orders
    _ordersFuture = MagentoAPI().fetchOrders(widget.userEmail, pageSize: 20);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text("My Orders", style: TextStyle(color: Color(0xFF00599c), fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF00599c)),
      ),
      body: FutureBuilder<List<Order>>(
        future: _ordersFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text("No orders found."));
          }

          final orders = snapshot.data!;
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: orders.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final order = orders[index];
              return GestureDetector(
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => OrderDetailScreen(order: order)));
                },
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("Order #${order.incrementId}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          Text(order.createdAt.split(' ')[0], style: const TextStyle(color: Colors.grey, fontSize: 12)),
                        ],
                      ),
                      const Divider(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _statusBadge(order.status),
                          Text("₹${order.grandTotal.toStringAsFixed(2)}", style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00599c), fontSize: 16)),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _statusBadge(String status) {
    Color color = Colors.grey;
    if (status == 'pending') color = Colors.orange;
    if (status == 'complete' || status == 'processing') color = Colors.green;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
      child: Text(status.toUpperCase(), style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }
}