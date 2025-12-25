// lib/providers/cart_provider.dart
import 'dart:convert';
import 'dart:async'; // [OPTIMIZATION] For timer/debounce
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart'; // [SECURITY]
import '../models/magento_models.dart';
import '../api/magento_api.dart';

class CartProvider with ChangeNotifier {
  List<CartItem> _items = [];
  bool _isLoading = false;
  final MagentoAPI _api = MagentoAPI();
  Timer? _debounceTimer; // [OPTIMIZATION]
  final _storage = const FlutterSecureStorage(); // [SECURITY]

  List<CartItem> get items => _items;
  bool get isLoading => _isLoading;

  int get itemCount {
    int count = 0;
    for (var item in _items) {
      count += item.qty;
    }
    return count;
  }

  double get totalAmount {
    double total = 0.0;
    for (var item in _items) {
      total += item.price * item.qty;
    }
    return total;
  }

  Future<void> fetchCart() async {
    _isLoading = true;
    notifyListeners();

    await _loadLocalCart();
    
    // [SECURITY] Read token securely
    final token = await _storage.read(key: 'customer_token');

    if (token != null) {
      await _mergeGuestItems(token);
      final serverItems = await _api.getCartItems();
      
      if (serverItems == null) {
        debugPrint(" Token Invalid/Expired. Reverting to Guest Mode.");
        await _storage.delete(key: 'customer_token'); // [SECURITY] Clean up
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('cached_user_data');
        MagentoAPI.cachedUser = null;
      } else {
        final mergedList = _mergeServerWithLocalImages(serverItems, _items);
        _items = mergedList;
        _saveLocalCart(); // No need to await or debounce here, single call
      }
    } 
    
    _isLoading = false;
    notifyListeners();
  }

  Future<void> _mergeGuestItems(String token) async {
    if (_items.isNotEmpty) {
      final guestItems = _items.where((i) => i.quoteId == 'guest_local').toList();
      if (guestItems.isNotEmpty) {
        debugPrint("Merging ${guestItems.length} Guest Items to Server...");
        for (var item in guestItems) {
          await _api.addToCart(item.sku, item.qty);
        }
      }
    }
  }

  List<CartItem> _mergeServerWithLocalImages(List<CartItem> serverItems, List<CartItem> localItems) {
    return serverItems.map((sItem) {
      if (sItem.imageUrl != null && sItem.imageUrl!.isNotEmpty) {
        return sItem;
      }
      final localMatch = localItems.firstWhere(
        (lItem) => lItem.sku == sItem.sku, 
        orElse: () => CartItem(itemId: 0, sku: '', qty: 0, name: '', price: 0, quoteId: '')
      );
      if (localMatch.imageUrl != null && localMatch.imageUrl!.isNotEmpty) {
        return sItem.copyWith(imageUrl: localMatch.imageUrl);
      }
      return sItem;
    }).toList();
  }

  Future<void> addToCart(Product product, {int qty = 1}) async {
    final token = await _storage.read(key: 'customer_token'); // [SECURITY]

    int index = _items.indexWhere((i) => i.sku == product.sku);
    if (index >= 0) {
      _items[index] = _items[index].copyWith(qty: _items[index].qty + qty);
    } else {
      _items.add(CartItem.fromProduct(product, qty));
    }
    notifyListeners();
    _debounceSaveLocalCart(); // [OPTIMIZATION]

    if (token != null) {
      _api.addToCart(product.sku, qty).then((success) {
        if (success) {
          _api.getCartItems().then((serverItems) {
             if (serverItems != null) {
               _items = _mergeServerWithLocalImages(serverItems, _items);
               _debounceSaveLocalCart();
               notifyListeners();
             }
          });
        }
      });
    }
  }

  Future<void> removeFromCart(CartItem item) async {
    final token = await _storage.read(key: 'customer_token');

    _items.removeWhere((i) => i.sku == item.sku); 
    notifyListeners();
    _debounceSaveLocalCart();

    if (token != null && item.itemId != 0) {
      _api.removeCartItem(item.itemId);
    }
  }

  Future<void> updateQty(CartItem item, int newQty) async {
    if (newQty < 1) return;
    final token = await _storage.read(key: 'customer_token');

    int index = _items.indexWhere((i) => i.sku == item.sku);
    if (index >= 0) {
      _items[index] = _items[index].copyWith(qty: newQty);
      notifyListeners();
      _debounceSaveLocalCart();
    }

    if (token != null && item.itemId != 0) {
      _api.updateCartItemQty(item.itemId, newQty, item.quoteId);
    }
  }

  Future<void> clearCart() async {
    _items = [];
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('cart_items_local');
    notifyListeners();
  }

  Future<void> _loadLocalCart() async {
    final prefs = await SharedPreferences.getInstance();
    final String? cartString = prefs.getString('cart_items_local');
    if (cartString != null) {
      final List<dynamic> decoded = jsonDecode(cartString);
      _items = decoded.map((e) => CartItem.fromJson(e)).toList();
    }
  }

  // [OPTIMIZATION] Debounce implementation
  void _debounceSaveLocalCart() {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), _saveLocalCart);
  }

  Future<void> _saveLocalCart() async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded = jsonEncode(_items.map((e) => e.toJson()).toList());
    await prefs.setString('cart_items_local', encoded);
  }
}