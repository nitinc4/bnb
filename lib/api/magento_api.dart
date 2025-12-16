// lib/api/magento_api.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/magento_models.dart';
import 'magento_oauth_client.dart'; 

class MagentoAPI {
  final String baseUrl = dotenv.env['MAGENTO_BASE_URL'] ?? "https://buynutbolts.com";
  late final MagentoOAuthClient _oauthClient;

  static List<Category> cachedCategories = [];
  static List<Product> cachedProducts = [];
  static Map<String, Category> _detailsCache = {};
  static Map<String, dynamic>? cachedUser; 

  MagentoAPI() {
    _oauthClient = MagentoOAuthClient(
      baseUrl: "$baseUrl/rest/V1",
      consumerKey: dotenv.env['CONSUMER_KEY'] ?? '',
      consumerSecret: dotenv.env['CONSUMER_SECRET'] ?? '',
      token: dotenv.env['ACCESS_TOKEN'] ?? '',
      tokenSecret: dotenv.env['ACCESS_TOKEN_SECRET'] ?? '',
    );
  }

  // --- MODIFIED: FETCH PRODUCTS WITH PAGINATION ---
  Future<List<Product>> fetchProducts({int? categoryId, int page = 1, int pageSize = 20}) async {
    // Only use cache for the very first page of "Featured Products" to keep Home fast
    if (categoryId == null && page == 1 && cachedProducts.isNotEmpty) return cachedProducts;
    
    try {
      // Base Params for Pagination
      final Map<String, String> queryParams = {
        "searchCriteria[pageSize]": pageSize.toString(),
        "searchCriteria[currentPage]": page.toString(),
      };

      // Add Category Filter if provided
      if (categoryId != null) {
        queryParams["searchCriteria[filter_groups][0][filters][0][field]"] = "category_id";
        queryParams["searchCriteria[filter_groups][0][filters][0][value]"] = "$categoryId";
        queryParams["searchCriteria[filter_groups][0][filters][0][condition_type]"] = "eq";
      }

      final response = await _oauthClient.get("/products", params: queryParams);
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final items = data["items"] as List? ?? [];
        final products = items.map((json) => Product.fromJson(json)).toList();

        // Cache only the first page of "All Products" for the Home Screen
        if (categoryId == null && page == 1) {
          cachedProducts = products;
          final prefs = await SharedPreferences.getInstance();
          prefs.setString('cached_products_data', jsonEncode(products.map((e) => e.toJson()).toList()));
        }
        return products;
      }
    } catch (e) {
      print("Fetch Products Error: $e");
    }
    return [];
  }

  // --- OTHER EXISTING METHODS (Keep as is) ---

  Future<void> clearCache() async {
    cachedCategories.clear();
    cachedProducts.clear();
    _detailsCache.clear();
    cachedUser = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('cached_categories_data');
    await prefs.remove('cached_products_data');
    await prefs.remove('category_details_cache');
    await prefs.remove('cached_user_data');
  }

  Future<List<Category>> fetchCategories() async {
    if (cachedCategories.isNotEmpty) return cachedCategories;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey('cached_categories_data')) {
      try {
        cachedCategories = (jsonDecode(prefs.getString('cached_categories_data')!) as List).map((e) => Category.fromJson(e)).toList();
        if (cachedCategories.isNotEmpty) return cachedCategories;
      } catch (e) {}
    }
    try {
      final response = await _oauthClient.get("/categories");
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final basic = (data['children_data'] as List? ?? []).map((e) => Category.fromJson(e)).toList();
        cachedCategories = await enrichCategories(basic);
        prefs.setString('cached_categories_data', jsonEncode(cachedCategories.map((e) => e.toJson()).toList()));
        return cachedCategories;
      }
    } catch (e) {}
    return [];
  }

  Future<List<Category>> enrichCategories(List<Category> categories) async {
    final prefs = await SharedPreferences.getInstance();
    if (_detailsCache.isEmpty && prefs.containsKey('category_details_cache')) {
      try {
        _detailsCache = (jsonDecode(prefs.getString('category_details_cache')!) as Map<String, dynamic>).map((k, v) => MapEntry(k, Category.fromJson(v)));
      } catch (e) {}
    }
    List<Future<Category>> tasks = categories.map((cat) async {
      final idStr = cat.id.toString();
      if (_detailsCache.containsKey(idStr)) {
        final c = _detailsCache[idStr]!;
        return Category(id: c.id, name: c.name, isActive: c.isActive, imageUrl: c.imageUrl, children: cat.children);
      }
      try {
        final response = await _oauthClient.get("/categories/${cat.id}");
        if (response.statusCode == 200) {
          final c = Category.fromJson(jsonDecode(response.body));
          _detailsCache[idStr] = c;
          return Category(id: c.id, name: c.name, isActive: c.isActive, imageUrl: c.imageUrl, children: cat.children);
        }
      } catch (e) {}
      return cat;
    }).toList();
    final results = await Future.wait(tasks);
    try {
      prefs.setString('category_details_cache', jsonEncode(_detailsCache.map((k, v) => MapEntry(k, v.toJson()))));
    } catch (e) {}
    return results.where((c) => c.isActive).toList();
  }

  Future<Product?> fetchProductBySku(String sku) async {
    try {
      final response = await _oauthClient.get("/products", params: {"searchCriteria[filter_groups][0][filters][0][field]": "sku", "searchCriteria[filter_groups][0][filters][0][value]": sku});
      final items = (jsonDecode(response.body)["items"] as List? ?? []);
      if (items.isNotEmpty) return Product.fromJson(items.first);
    } catch (e) {}
    return null;
  }

  // --- SEARCH ---
  Future<List<Product>> searchProducts(String query) async {
    return _performSearch(query, pageSize: 20);
  }

  Future<List<Product>> getSearchSuggestions(String query) async {
    return _performSearch(query, pageSize: 4);
  }

  Future<List<Product>> _performSearch(String query, {required int pageSize}) async {
    if (query.trim().isEmpty) return [];
    try {
      final response = await _oauthClient.get("/products", params: {
        "searchCriteria[filter_groups][0][filters][0][field]": "name", "searchCriteria[filter_groups][0][filters][0][value]": "%$query%", "searchCriteria[filter_groups][0][filters][0][condition_type]": "like",
        "searchCriteria[filter_groups][0][filters][1][field]": "sku", "searchCriteria[filter_groups][0][filters][1][value]": "%$query%", "searchCriteria[filter_groups][0][filters][1][condition_type]": "like",
        "searchCriteria[pageSize]": pageSize.toString()
      });
      if (response.statusCode == 200) {
        return (jsonDecode(response.body)["items"] as List? ?? []).map((e) => Product.fromJson(e)).toList();
      }
    } catch (e) {}
    return [];
  }

  // --- CART & USER (Keep previous implementation) ---
  Future<List<CartItem>?> getCartItems() async {
    final token = await _getCustomerToken();
    if (token == null) return [];
    try {
      final response = await http.get(Uri.parse("$baseUrl/rest/V1/carts/mine/items"), headers: {"Authorization": "Bearer $token", "Content-Type": "application/json"});
      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        List<CartItem> items = data.map((e) => CartItem.fromJson(e)).toList();
        // Enrich images logic...
        return items;
      } else if (response.statusCode == 401) return null;
    } catch (e) {}
    return null;
  }

  Future<bool> addToCart(String sku, int qty) async {
    final token = await _getCustomerToken();
    if (token == null) return false;
    try {
      final cartRes = await http.post(Uri.parse("$baseUrl/rest/V1/carts/mine"), headers: {"Authorization": "Bearer $token", "Content-Type": "application/json"});
      if (cartRes.statusCode != 200) return false;
      String quoteId = jsonDecode(cartRes.body).toString();
      final response = await http.post(Uri.parse("$baseUrl/rest/V1/carts/mine/items"), headers: {"Authorization": "Bearer $token", "Content-Type": "application/json"}, body: jsonEncode({"cartItem": {"sku": sku, "qty": qty, "quote_id": quoteId}}));
      return response.statusCode == 200;
    } catch (e) { return false; }
  }

  Future<bool> removeCartItem(int itemId) async {
    final token = await _getCustomerToken();
    if (token == null) return false;
    try {
      final response = await http.delete(Uri.parse("$baseUrl/rest/V1/carts/mine/items/$itemId"), headers: {"Authorization": "Bearer $token", "Content-Type": "application/json"});
      return response.statusCode == 200;
    } catch (e) { return false; }
  }

  Future<bool> updateCartItemQty(int itemId, int qty, String quoteId) async {
    final token = await _getCustomerToken();
    if (token == null) return false;
    try {
      final response = await http.put(Uri.parse("$baseUrl/rest/V1/carts/mine/items/$itemId"), headers: {"Authorization": "Bearer $token", "Content-Type": "application/json"}, body: jsonEncode({"cartItem": {"item_id": itemId, "qty": qty, "quote_id": quoteId}}));
      return response.statusCode == 200;
    } catch (e) { return false; }
  }

  Future<List<Order>> fetchOrders(String email, {int pageSize = 5}) async {
    try {
      final response = await _oauthClient.get("/orders", params: {"searchCriteria[filter_groups][0][filters][0][field]": "customer_email", "searchCriteria[filter_groups][0][filters][0][value]": email, "searchCriteria[sortOrders][0][field]": "created_at", "searchCriteria[sortOrders][0][direction]": "DESC", "searchCriteria[pageSize]": pageSize.toString()});
      if (response.statusCode == 200) return (jsonDecode(response.body)["items"] as List? ?? []).map((e) => Order.fromJson(e)).toList();
    } catch (e) {}
    return [];
  }

  Future<String?> loginCustomer(String e, String p) async {
    try {
      final r = await http.post(Uri.parse("$baseUrl/rest/V1/integration/customer/token"), headers: {"Content-Type": "application/json"}, body: jsonEncode({"username": e, "password": p}));
      if (r.statusCode == 200) return jsonDecode(r.body);
    } catch (e) {}
    return null;
  }

  Future<bool> createCustomer(String f, String l, String e, String p) async {
    try {
      final r = await http.post(Uri.parse("$baseUrl/rest/V1/customers"), headers: {"Content-Type": "application/json"}, body: jsonEncode({"customer": {"email": e, "firstname": f, "lastname": l}, "password": p}));
      return r.statusCode == 200;
    } catch (e) { return false; }
  }

  Future<Map<String, dynamic>?> fetchCustomerDetails(String token) async {
    try {
      final r = await http.get(Uri.parse("$baseUrl/rest/V1/customers/me"), headers: {"Authorization": "Bearer $token"});
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body);
        cachedUser = data;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('cached_user_data', jsonEncode(data));
        return data;
      } else if (r.statusCode == 401) return null;
    } catch (e) {}
    return null;
  }

  Future<bool> saveAddress(Map<String, dynamic> addr) async {
    final token = await _getCustomerToken();
    if (token == null) return false;
    try {
      final user = await fetchCustomerDetails(token);
      if (user == null) return false;
      List addrs = user['addresses'] ?? [];
      if (addr['id'] != null) addrs.removeWhere((a) => a['id'] == addr['id']);
      addr['region_id'] = 0; addr['customer_id'] = user['id']; addrs.add(addr);
      final r = await http.put(Uri.parse("$baseUrl/rest/V1/customers/me"), headers: {"Authorization": "Bearer $token", "Content-Type": "application/json"}, body: jsonEncode({"customer": {...user, "addresses": addrs}}));
      return r.statusCode == 200;
    } catch (e) { return false; }
  }

  Future<bool> updateCustomerProfile(Map<String, dynamic> d) async {
    final t = await _getCustomerToken(); if (t == null) return false;
    try { final c = await fetchCustomerDetails(t); if (c == null) return false; final r = await http.put(Uri.parse("$baseUrl/rest/V1/customers/me"), headers: {"Authorization": "Bearer $t", "Content-Type": "application/json"}, body: jsonEncode({"customer": {...c, ...d}})); return r.statusCode == 200; } catch (e) { return false; }
  }

  Future<bool> changePassword(String c, String n) async {
    final t = await _getCustomerToken(); if (t == null) return false;
    try { final r = await http.put(Uri.parse("$baseUrl/rest/V1/customers/me/password"), headers: {"Authorization": "Bearer $t", "Content-Type": "application/json"}, body: jsonEncode({"currentPassword": c, "newPassword": n})); return r.statusCode == 200; } catch (e) { return false; }
  }

  Future<String?> _getCustomerToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('customer_token');
  }
}