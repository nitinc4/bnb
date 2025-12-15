// lib/screens/profile_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart'; // Needed for Reorder
import 'package:shared_preferences/shared_preferences.dart';
import '../api/magento_api.dart';
import '../models/magento_models.dart';
import '../providers/cart_provider.dart'; // Needed for Reorder

import 'login_screen.dart';
import 'signup_screen.dart';
import 'orders_screen.dart';
import 'address_book_screen.dart';
import 'add_edit_address_screen.dart';
import 'edit_profile_screen.dart'; // NEW
import 'order_detail_screen.dart'; // NEW

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isLoggedIn = false;
  bool _isLoading = true;
  Map<String, dynamic>? _userData;
  List<Order> _recentOrders = [];

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);
    
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('customer_token');

    if (token != null && token.isNotEmpty) {
      final api = MagentoAPI();
      final userData = await api.fetchCustomerDetails(token);
      List<Order> orders = [];
      if (userData != null && userData['email'] != null) {
        orders = await api.fetchOrders(userData['email']);
      }

      if (mounted) {
        setState(() {
          _isLoggedIn = true;
          _userData = userData;
          _recentOrders = orders;
          _isLoading = false;
        });
      }
    } else {
      if (mounted) setState(() { _isLoggedIn = false; _isLoading = false; });
    }
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('customer_token');
    await prefs.setBool('has_logged_in', false);
    await prefs.setBool('is_guest', false);
    if (mounted) Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
  }

  // --- REORDER LOGIC ---
  Future<void> _reorder(Order order) async {
    final cart = Provider.of<CartProvider>(context, listen: false);
    
    // We iterate through order items and add them to cart locally
    // Note: We need full Product objects for the cart provider.
    // Ideally, we fetch product by SKU to get image/details.
    
    int addedCount = 0;
    for (var item in order.items) {
      // Basic product object for cart (missing image/desc but works for now)
      // For better UX, you might want to fetchProductBySku(item.sku) first.
      final simpleProduct = Product(
        name: item.name,
        sku: item.sku,
        price: item.price,
        imageUrl: "https://buynutbolts.com/media/catalog/product/placeholder.jpg", // Fallback
        description: "",
      );
      
      // Add quantity times
      for(int i=0; i<item.qty; i++) {
        cart.addToCart(simpleProduct);
      }
      addedCount++;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("$addedCount items added to cart")),
    );
    // Navigate to Cart
    Navigator.pushNamed(context, '/cart');
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator(color: Color(0xFF00599c)));
    if (!_isLoggedIn) return _buildGuestView();

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text("My Account", style: TextStyle(color: Color(0xFF00599c), fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.logout, color: Color(0xFFF54336)), onPressed: _logout),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadAllData,
        color: const Color(0xFF00599c),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionTitle("Account Information"),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _buildInfoBox("Contact Information", [
                    "${_userData?['firstname'] ?? ''} ${_userData?['lastname'] ?? ''}",
                    _userData?['email'] ?? '',
                  ], actions: [
                    _buildLink("Edit", () async {
                      final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => EditProfileScreen(
                        firstName: _userData?['firstname'] ?? '',
                        lastName: _userData?['lastname'] ?? '',
                        email: _userData?['email'] ?? '',
                      )));
                      if (result == true) _loadAllData();
                    }),
                    _buildLink("Change Password", () async {
                       final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => EditProfileScreen(
                        firstName: _userData?['firstname'] ?? '',
                        lastName: _userData?['lastname'] ?? '',
                        email: _userData?['email'] ?? '',
                      ))); // Password logic is inside same screen
                      if (result == true) _loadAllData();
                    }),
                  ])),
                  const SizedBox(width: 12),
                  Expanded(child: _buildInfoBox("Newsletters", [
                    "Newsletter settings"
                  ], actions: [
                    _buildLink("Edit", () {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Newsletter management coming soon")));
                    }),
                  ])),
                ],
              ),

              const SizedBox(height: 24),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  _buildSectionTitle("Address Book"),
                  _buildLink("Manage Addresses", () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => AddressBookScreen(addresses: _userData?['addresses'] ?? [], onRefresh: _loadAllData)));
                  }),
              ]),
              const SizedBox(height: 10),
              Column(children: [
                  _buildAddressBox("Default Billing Address", _getDefaultAddress(isBilling: true)),
                  const SizedBox(height: 12),
                  _buildAddressBox("Default Shipping Address", _getDefaultAddress(isBilling: false)),
              ]),

              const SizedBox(height: 24),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  _buildSectionTitle("Recent Orders"),
                  _buildLink("View All", () => Navigator.push(context, MaterialPageRoute(builder: (_) => OrdersScreen(userEmail: _userData?['email'] ?? '')))),
              ]),
              const SizedBox(height: 10),
              _buildRecentOrdersTable(),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  // --- WIDGET HELPERS ---
  Map<String, dynamic>? _getDefaultAddress({required bool isBilling}) {
    final List addresses = _userData?['addresses'] ?? [];
    if (addresses.isEmpty) return null;
    try {
      return addresses.firstWhere((addr) => addr[isBilling ? 'default_billing' : 'default_shipping'] == true);
    } catch (e) { return null; }
  }

  Widget _buildSectionTitle(String title) => Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF333333)));
  
  Widget _buildLink(String text, VoidCallback onTap) => GestureDetector(onTap: onTap, child: Text(text, style: const TextStyle(color: Color(0xFF00599c), fontWeight: FontWeight.w600, fontSize: 13)));

  Widget _buildInfoBox(String title, List<String> content, {List<Widget>? actions}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const Divider(height: 20),
          ...content.map((c) => Text(c, style: const TextStyle(fontSize: 13, color: Colors.black87, height: 1.4))),
          if (actions != null) ...[const SizedBox(height: 12), Wrap(spacing: 12, children: actions)]
      ]),
    );
  }

  Widget _buildAddressBox(String title, Map<String, dynamic>? address) {
    return Container(
      width: double.infinity, padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              _buildLink("Edit Address", () async {
                 if (address != null) {
                   final res = await Navigator.push(context, MaterialPageRoute(builder: (_) => AddEditAddressScreen(address: address)));
                   if (res == true) _loadAllData();
                 }
              }),
          ]),
          const Divider(height: 20),
          if (address != null) ...[
            Text("${address['firstname']} ${address['lastname']}", style: const TextStyle(fontWeight: FontWeight.w600)),
            Text((address['street'] as List).join("\n")),
            Text("${address['city']}, ${address['postcode']}"),
            if (address['telephone'] != null) Text("T: ${address['telephone']}", style: const TextStyle(color: Color(0xFF00599c))),
          ] else const Text("You have not set a default address.", style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),
      ]),
    );
  }

  Widget _buildRecentOrdersTable() {
    if (_recentOrders.isEmpty) {
      return Container(width: double.infinity, padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)), child: const Text("No recent orders.", style: TextStyle(color: Colors.grey)));
    }
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: MaterialStateProperty.all(Colors.grey.shade50),
          columns: const [
            DataColumn(label: Text("Order #")), DataColumn(label: Text("Date")),
            DataColumn(label: Text("Total")), DataColumn(label: Text("Status")), DataColumn(label: Text("Action")),
          ],
          rows: _recentOrders.map((order) {
            return DataRow(cells: [
              DataCell(Text(order.incrementId)), DataCell(Text(order.createdAt.split(' ')[0])),
              DataCell(Text("₹${order.grandTotal.toStringAsFixed(2)}", style: const TextStyle(fontWeight: FontWeight.bold))),
              DataCell(Text(order.status.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold))),
              DataCell(Row(children: [
                  _buildLink("View", () => Navigator.push(context, MaterialPageRoute(builder: (_) => OrderDetailScreen(order: order)))),
                  const SizedBox(width: 10),
                  _buildLink("Reorder", () => _reorder(order)),
              ])),
            ]);
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildGuestView() {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.account_circle_outlined, size: 80, color: Colors.grey),
              const SizedBox(height: 20),
              const Text("You are currently a Guest", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              const Text("Login to view your profile.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 30),
              SizedBox(width: double.infinity, height: 50, child: ElevatedButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen())), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00599c)), child: const Text("Login", style: TextStyle(color: Colors.white, fontSize: 16)))),
              const SizedBox(height: 16),
              SizedBox(width: double.infinity, height: 50, child: OutlinedButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SignupScreen())), child: const Text("Create Account"))),
            ],
          ),
        ),
      ),
    );
  }
}