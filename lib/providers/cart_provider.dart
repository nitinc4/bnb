// lib/providers/cart_provider.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/magento_models.dart';

class CartProvider with ChangeNotifier {
  List<Product> _items = [];

  List<Product> get items => _items;

  int get itemCount => _items.length;

  double get totalAmount {
    double total = 0.0;
    for (var item in _items) {
      total += item.price;
    }
    return total;
  }

  CartProvider() {
    _loadCartFromCache();
  }

  Future<void> _loadCartFromCache() async {
    final prefs = await SharedPreferences.getInstance();
    final String? cartString = prefs.getString('cart_items');
    
    if (cartString != null) {
      final List<dynamic> decoded = jsonDecode(cartString);
      // This is the line that was failing because Product.fromStorage was missing
      _items = decoded.map((e) => Product.fromStorage(e)).toList(); 
      notifyListeners();
    }
  }

  Future<void> _saveCartToCache() async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded = jsonEncode(_items.map((e) => e.toJson()).toList());
    prefs.setString('cart_items', encoded);
  }

  void addToCart(Product product) {
    _items.add(product);
    _saveCartToCache(); 
    notifyListeners();
  }

  void removeFromCart(Product product) {
    _items.remove(product);
    _saveCartToCache();
    notifyListeners();
  }

  void clearCart() {
    _items.clear();
    _saveCartToCache();
    notifyListeners();
  }
}