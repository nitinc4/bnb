import 'package:flutter/material.dart';
import '../api/magento_api.dart';

class AddEditAddressScreen extends StatefulWidget {
  final Map<String, dynamic>? address;
  const AddEditAddressScreen({super.key, this.address});

  @override
  State<AddEditAddressScreen> createState() => _AddEditAddressScreenState();
}

class _AddEditAddressScreenState extends State<AddEditAddressScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _fNameCtrl;
  late TextEditingController _lNameCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _streetCtrl;
  late TextEditingController _cityCtrl;
  late TextEditingController _postcodeCtrl;

  bool _isDefaultBilling = false;
  bool _isDefaultShipping = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final addr = widget.address;
    _fNameCtrl = TextEditingController(text: addr?['firstname'] ?? '');
    _lNameCtrl = TextEditingController(text: addr?['lastname'] ?? '');
    _phoneCtrl = TextEditingController(text: addr?['telephone'] ?? '');
    _streetCtrl = TextEditingController(text: (addr?['street'] as List?)?.join(', ') ?? '');
    _cityCtrl = TextEditingController(text: addr?['city'] ?? '');
    _postcodeCtrl = TextEditingController(text: addr?['postcode'] ?? '');
    
    _isDefaultBilling = addr?['default_billing'] ?? false;
    _isDefaultShipping = addr?['default_shipping'] ?? false;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final addressData = {
      if (widget.address != null) "id": widget.address!['id'],
      "firstname": _fNameCtrl.text,
      "lastname": _lNameCtrl.text,
      "telephone": _phoneCtrl.text,
      "street": [_streetCtrl.text],
      "city": _cityCtrl.text,
      "postcode": _postcodeCtrl.text,
      "country_id": "IN", 
      "default_billing": _isDefaultBilling,
      "default_shipping": _isDefaultShipping,
    };

    final success = await MagentoAPI().saveAddress(addressData);

    if (mounted) {
      setState(() => _isLoading = false);
      if (success) {
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Failed to save address")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(widget.address == null ? "Add Address" : "Edit Address", style: const TextStyle(color: Color(0xFF00599c))),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF00599c)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              _field("First Name", _fNameCtrl),
              _field("Last Name", _lNameCtrl),
              _field("Phone", _phoneCtrl, type: TextInputType.phone),
              _field("Street Address", _streetCtrl),
              Row(children: [
                Expanded(child: _field("City", _cityCtrl)),
                const SizedBox(width: 12),
                Expanded(child: _field("Postcode", _postcodeCtrl, type: TextInputType.number)),
              ]),
              SwitchListTile(title: const Text("Default Billing"), value: _isDefaultBilling, activeColor: const Color(0xFF00599c), onChanged: (v) => setState(() => _isDefaultBilling = v)),
              SwitchListTile(title: const Text("Default Shipping"), value: _isDefaultShipping, activeColor: const Color(0xFF00599c), onChanged: (v) => setState(() => _isDefaultShipping = v)),
              const SizedBox(height: 30),
              SizedBox(width: double.infinity, height: 50, child: ElevatedButton(onPressed: _isLoading ? null : _save, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00599c)), child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text("Save Address", style: TextStyle(color: Colors.white)))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl, {TextInputType type = TextInputType.text}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(controller: ctrl, keyboardType: type, decoration: InputDecoration(labelText: label, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), filled: true, fillColor: Colors.grey.shade50), validator: (v) => v!.isEmpty ? "Required" : null),
    );
  }
}