import 'package:flutter/material.dart';
import 'add_edit_address_screen.dart';

class AddressBookScreen extends StatelessWidget {
  final List<dynamic> addresses;
  final Function onRefresh;

  const AddressBookScreen({super.key, required this.addresses, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text("Address Book", style: TextStyle(color: Color(0xFF00599c), fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF00599c)),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () async {
              final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => const AddEditAddressScreen()));
              if (result == true) onRefresh();
            },
          )
        ],
      ),
      body: addresses.isEmpty
          ? const Center(child: Text("No addresses saved."))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: addresses.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final addr = addresses[index];
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("${addr['firstname']} ${addr['lastname']}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          TextButton(
                            onPressed: () async {
                              final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => AddEditAddressScreen(address: addr)));
                              if (result == true) onRefresh();
                            },
                            child: const Text("Edit", style: TextStyle(color: Color(0xFF00599c))),
                          ),
                        ],
                      ),
                      Text((addr['street'] as List).join(", ")),
                      Text("${addr['city']}, ${addr['postcode']}"),
                      if (addr['telephone'] != null) Text("T: ${addr['telephone']}"),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (addr['default_billing'] == true) _tag("Default Billing"),
                          const SizedBox(width: 8),
                          if (addr['default_shipping'] == true) _tag("Default Shipping"),
                        ],
                      )
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _tag(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
      child: Text(text, style: const TextStyle(fontSize: 10, color: Colors.blue, fontWeight: FontWeight.bold)),
    );
  }
}