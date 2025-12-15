// lib/screens/edit_profile_screen.dart
import 'package:flutter/material.dart';
import '../api/magento_api.dart';

class EditProfileScreen extends StatefulWidget {
  final String firstName;
  final String lastName;
  final String email;

  const EditProfileScreen({
    super.key,
    required this.firstName,
    required this.lastName,
    required this.email,
  });

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late TextEditingController _fNameCtrl;
  late TextEditingController _lNameCtrl;
  late TextEditingController _emailCtrl;
  
  // Password Fields
  final _currentPassCtrl = TextEditingController();
  final _newPassCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();
  
  bool _changePassword = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fNameCtrl = TextEditingController(text: widget.firstName);
    _lNameCtrl = TextEditingController(text: widget.lastName);
    _emailCtrl = TextEditingController(text: widget.email);
  }

  Future<void> _save() async {
    setState(() => _isLoading = true);
    final api = MagentoAPI();

    // 1. Update Profile (Name/Email)
    bool profileSuccess = await api.updateCustomerProfile({
      "firstname": _fNameCtrl.text,
      "lastname": _lNameCtrl.text,
      "email": _emailCtrl.text,
    });

    // 2. Change Password (if requested)
    bool passSuccess = true;
    if (_changePassword) {
      if (_newPassCtrl.text != _confirmPassCtrl.text) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Passwords do not match")));
        setState(() => _isLoading = false);
        return;
      }
      passSuccess = await api.changePassword(_currentPassCtrl.text, _newPassCtrl.text);
    }

    if (mounted) {
      setState(() => _isLoading = false);
      if (profileSuccess && passSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Profile Updated Successfully")));
        Navigator.pop(context, true); // Refresh parent
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Failed to update profile. Check password if changing.")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Edit Profile", style: TextStyle(color: Color(0xFF00599c))),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF00599c)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Contact Information", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _buildField("First Name", _fNameCtrl),
            _buildField("Last Name", _lNameCtrl),
            _buildField("Email", _emailCtrl, type: TextInputType.emailAddress),
            
            const SizedBox(height: 24),
            Row(
              children: [
                Checkbox(
                  value: _changePassword,
                  activeColor: const Color(0xFF00599c),
                  onChanged: (v) => setState(() => _changePassword = v!),
                ),
                const Text("Change Password", style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            
            if (_changePassword) ...[
              _buildField("Current Password", _currentPassCtrl, isPass: true),
              _buildField("New Password", _newPassCtrl, isPass: true),
              _buildField("Confirm New Password", _confirmPassCtrl, isPass: true),
            ],

            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _save,
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00599c)),
                child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text("Save", style: TextStyle(color: Colors.white, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField(String label, TextEditingController ctrl, {TextInputType type = TextInputType.text, bool isPass = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: ctrl,
        keyboardType: type,
        obscureText: isPass,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          filled: true,
          fillColor: Colors.grey.shade50,
        ),
      ),
    );
  }
}