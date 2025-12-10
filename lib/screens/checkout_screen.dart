import 'package:flutter/material.dart';
import 'order_success_screen.dart';

class CheckoutScreen extends StatefulWidget {
  final double total;
  const CheckoutScreen({super.key, required this.total});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _formKey = GlobalKey<FormState>();
  String paymentMode = "COD";

  final nameController = TextEditingController();
  final addressController = TextEditingController();
  final cityController = TextEditingController();
  final pinController = TextEditingController();
  final phoneController = TextEditingController();

  void _placeOrder() {
    if (_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Placing your order..."),
          duration: Duration(seconds: 2),
        ),
      );

      Future.delayed(const Duration(seconds: 2), () {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => OrderSuccessScreen(amount: widget.total),
          ),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          "Checkout",
          style: TextStyle(
            color: Color(0xFF00599c),
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Color(0xFF00599c)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Shipping Details",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF00599c),
                ),
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: "Full Name",
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (v) =>
                    v == null || v.isEmpty ? "Enter your name" : null,
              ),
              const SizedBox(height: 14),

              TextFormField(
                controller: addressController,
                decoration: const InputDecoration(
                  labelText: "Full Address",
                  prefixIcon: Icon(Icons.home_outlined),
                ),
                validator: (v) =>
                    v == null || v.isEmpty ? "Enter your address" : null,
              ),
              const SizedBox(height: 14),

              TextFormField(
                controller: cityController,
                decoration: const InputDecoration(
                  labelText: "City",
                  prefixIcon: Icon(Icons.location_city_outlined),
                ),
                validator: (v) =>
                    v == null || v.isEmpty ? "Enter city" : null,
              ),
              const SizedBox(height: 14),

              TextFormField(
                controller: pinController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "PIN Code",
                  prefixIcon: Icon(Icons.pin_drop_outlined),
                ),
                validator: (v) =>
                    v == null || v.isEmpty ? "Enter PIN code" : null,
              ),
              const SizedBox(height: 14),

              TextFormField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: "Contact Number",
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
                validator: (v) => v == null || v.isEmpty
                    ? "Enter contact number"
                    : null,
              ),
              const SizedBox(height: 30),

              const Text(
                "Payment Method",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF00599c),
                ),
              ),
              const SizedBox(height: 10),

              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    RadioListTile<String>(
                      value: "COD",
                      groupValue: paymentMode,
                      activeColor: const Color(0xFF00599c),
                      onChanged: (value) =>
                          setState(() => paymentMode = value!),
                      title: const Text("Cash on Delivery"),
                    ),
                    RadioListTile<String>(
                      value: "Online",
                      groupValue: paymentMode,
                      activeColor: const Color(0xFF00599c),
                      onChanged: (value) =>
                          setState(() => paymentMode = value!),
                      title: const Text("Online Payment (Demo)"),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),

              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Total Amount:",
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      "₹${widget.total.toStringAsFixed(2)}",
                      style: const TextStyle(
                        color: Color(0xFFF54336),
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _placeOrder,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00599c),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 5,
                  ),
                  child: const Text(
                    "Place Order",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
