// lib/providers/cart_provider.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/magento_models.dart';
import '../api/magento_api.dart';

class CartProvider with ChangeNotifier {
  List<CartItem> _items = [];
  bool _isLoading = false;
  final MagentoAPI _api = MagentoAPI();

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

  // --- FETCH & MERGE LOGIC ---
  Future<void> fetchCart() async {
    _isLoading = true;
    notifyListeners();

    // 1. Always load local cache first for speed (Optimistic)
    await _loadLocalCart();
    
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('customer_token');

    if (token != null) {
      // 2. LOGGED IN? Check if we have guest items to merge
      await _mergeGuestItems(token);

      // 3. Sync with Server
      final serverItems = await _api.getCartItems();
      
      if (serverItems == null) {
        // TOKEN EXPIRED OR ERROR -> Fallback to Guest
        debugPrint("⚠️ Token Invalid/Expired. Reverting to Guest Mode.");
        await prefs.remove('customer_token');
        await prefs.remove('cached_user_data');
        MagentoAPI.cachedUser = null;
        
        // We already loaded local cart in step 1, so just notify and stop
      } else {
        // 4. Merge Server Items with Local Images
        final mergedList = _mergeServerWithLocalImages(serverItems, _items);
        _items = mergedList;
        
        // 5. Save the authoritative list locally for next time
        await _saveLocalCart();
      }
    } 
    
    _isLoading = false;
    notifyListeners();
  }

  // --- MERGE HELPER ---
  Future<void> _mergeGuestItems(String token) async {
    if (_items.isNotEmpty) {
      final guestItems = _items.where((i) => i.quoteId == 'guest_local').toList();
      if (guestItems.isNotEmpty) {
        debugPrint("🔄 Merging ${guestItems.length} Guest Items to Server...");
        for (var item in guestItems) {
          await _api.addToCart(item.sku, item.qty);
        }
      }
    }
  }

  // --- IMAGE PRESERVATION HELPER ---
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

  // --- ADD TO CART ---
  Future<void> addToCart(Product product, {int qty = 1}) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('customer_token');

    // 1. Optimistic Local Update
    int index = _items.indexWhere((i) => i.sku == product.sku);
    if (index >= 0) {
      _items[index] = _items[index].copyWith(qty: _items[index].qty + qty);
    } else {
      _items.add(CartItem.fromProduct(product, qty));
    }
    notifyListeners();
    _saveLocalCart();

    // 2. Server Sync (if logged in)
    if (token != null) {
      _api.addToCart(product.sku, qty).then((success) {
        if (success) {
          _api.getCartItems().then((serverItems) {
             if (serverItems != null) {
               _items = _mergeServerWithLocalImages(serverItems, _items);
               _saveLocalCart();
               notifyListeners();
             }
          });
        }
      });
    }
  }

  // --- REMOVE ---
  Future<void> removeFromCart(CartItem item) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('customer_token');

    _items.removeWhere((i) => i.sku == item.sku); 
    notifyListeners();
    _saveLocalCart();

    if (token != null && item.itemId != 0) {
      _api.removeCartItem(item.itemId);
    }
  }

  // --- UPDATE QTY ---
  Future<void> updateQty(CartItem item, int newQty) async {
    if (newQty < 1) return;
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('customer_token');

    int index = _items.indexWhere((i) => i.sku == item.sku);
    if (index >= 0) {
      _items[index] = _items[index].copyWith(qty: newQty);
      notifyListeners();
      _saveLocalCart();
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

  Future<void> _saveLocalCart() async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded = jsonEncode(_items.map((e) => e.toJson()).toList());
    await prefs.setString('cart_items_local', encoded);
  }
}