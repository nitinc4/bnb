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

  MagentoAPI() {
    _oauthClient = MagentoOAuthClient(
      baseUrl: "$baseUrl/rest/V1",
      consumerKey: dotenv.env['CONSUMER_KEY'] ?? '',
      consumerSecret: dotenv.env['CONSUMER_SECRET'] ?? '',
      token: dotenv.env['ACCESS_TOKEN'] ?? '',
      tokenSecret: dotenv.env['ACCESS_TOKEN_SECRET'] ?? '',
    );
  }

  // --- SEARCH METHODS ---

  // 1. Full Search (for Grid)
  Future<List<Product>> searchProducts(String query) async {
    return _performSearch(query, pageSize: 20);
  }

  // 2. Suggestions (for Auto-complete)
  Future<List<Product>> getSearchSuggestions(String query) async {
    return _performSearch(query, pageSize: 4);
  }

  // Shared Search Logic
  Future<List<Product>> _performSearch(String query, {required int pageSize}) async {
    if (query.trim().isEmpty) return [];
    
    // Clean query to avoid breaking API
    final cleanQuery = query.trim();

    try {
      final response = await _oauthClient.get("/products", params: {
        // Condition: (Name LIKE %q% OR SKU LIKE %q%)
        
        // Filter 1: Name
        "searchCriteria[filter_groups][0][filters][0][field]": "name",
        "searchCriteria[filter_groups][0][filters][0][value]": "%$cleanQuery%",
        "searchCriteria[filter_groups][0][filters][0][condition_type]": "like",
        
        // Filter 2: SKU (Same group = OR logic)
        "searchCriteria[filter_groups][0][filters][1][field]": "sku",
        "searchCriteria[filter_groups][0][filters][1][value]": "%$cleanQuery%",
        "searchCriteria[filter_groups][0][filters][1][condition_type]": "like",
        
        // Settings
        "searchCriteria[pageSize]": pageSize.toString(),
        "searchCriteria[currentPage]": "1",
      });

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final items = data["items"] as List? ?? [];
        return items.map((json) => Product.fromJson(json)).toList();
      }
    } catch (e) {
      print("Search Error: $e");
    }
    return [];
  }

  // --- CART METHODS (Existing) ---

  Future<List<CartItem>> getCartItems() async {
    final token = await _getCustomerToken();
    if (token == null) return [];

    try {
      final response = await http.get(
        Uri.parse("$baseUrl/rest/V1/carts/mine/items"),
        headers: {"Authorization": "Bearer $token", "Content-Type": "application/json"},
      );
      
      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        List<CartItem> items = data.map((e) => CartItem.fromJson(e)).toList();

        // Enrich Items with Images from Cache or Fetch
        if (cachedProducts.isEmpty) {
          final prefs = await SharedPreferences.getInstance();
          if (prefs.containsKey('cached_products_data')) {
            try {
              final decoded = jsonDecode(prefs.getString('cached_products_data')!);
              cachedProducts = (decoded as List).map((e) => Product.fromJson(e)).toList();
            } catch (e) {}
          }
        }

        for (int i = 0; i < items.length; i++) {
          final cached = cachedProducts.firstWhere(
            (p) => p.sku == items[i].sku, 
            orElse: () => Product(name: '', sku: '', price: 0, imageUrl: '', description: '')
          );

          if (cached.imageUrl.isNotEmpty) {
            items[i] = items[i].copyWith(imageUrl: cached.imageUrl);
          } else {
             try {
              final product = await fetchProductBySku(items[i].sku);
              if (product != null && product.imageUrl.isNotEmpty) {
                items[i] = items[i].copyWith(imageUrl: product.imageUrl);
              }
            } catch (e) {}
          }
        }
        return items;
      }
    } catch (e) {
      print("Get Cart Error: $e");
    }
    return [];
  }

  Future<bool> addToCart(String sku, int qty) async {
    final token = await _getCustomerToken();
    if (token == null) return false;

    try {
      final cartRes = await http.post(
        Uri.parse("$baseUrl/rest/V1/carts/mine"),
        headers: {"Authorization": "Bearer $token", "Content-Type": "application/json"},
      );
      if (cartRes.statusCode != 200) return false;
      String quoteId = jsonDecode(cartRes.body).toString();

      final response = await http.post(
        Uri.parse("$baseUrl/rest/V1/carts/mine/items"),
        headers: {"Authorization": "Bearer $token", "Content-Type": "application/json"},
        body: jsonEncode({
          "cartItem": {
            "sku": sku,
            "qty": qty,
            "quote_id": quoteId
          }
        }),
      );
      return response.statusCode == 200;
    } catch (e) { return false; }
  }

  Future<bool> removeCartItem(int itemId) async {
    final token = await _getCustomerToken();
    if (token == null) return false;

    try {
      final response = await http.delete(
        Uri.parse("$baseUrl/rest/V1/carts/mine/items/$itemId"),
        headers: {"Authorization": "Bearer $token", "Content-Type": "application/json"},
      );
      return response.statusCode == 200;
    } catch (e) { return false; }
  }

  Future<bool> updateCartItemQty(int itemId, int qty, String quoteId) async {
    final token = await _getCustomerToken();
    if (token == null) return false;

    try {
      final response = await http.put(
        Uri.parse("$baseUrl/rest/V1/carts/mine/items/$itemId"),
        headers: {"Authorization": "Bearer $token", "Content-Type": "application/json"},
        body: jsonEncode({
          "cartItem": {"item_id": itemId, "qty": qty, "quote_id": quoteId}
        }),
      );
      return response.statusCode == 200;
    } catch (e) { return false; }
  }

  // --- OAUTH DATA FETCHING ---

  Future<void> clearCache() async {
    cachedCategories.clear();
    cachedProducts.clear();
    _detailsCache.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('cached_categories_data');
    await prefs.remove('cached_products_data');
    await prefs.remove('category_details_cache');
  }

  Future<List<Category>> fetchCategories() async {
    if (cachedCategories.isNotEmpty) return cachedCategories;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey('cached_categories_data')) {
      try {
        final decoded = jsonDecode(prefs.getString('cached_categories_data')!);
        cachedCategories = (decoded as List).map((e) => Category.fromJson(e)).toList();
        if (cachedCategories.isNotEmpty) return cachedCategories;
      } catch (e) {}
    }

    try {
      final response = await _oauthClient.get("/categories");
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final childrenData = data['children_data'] as List? ?? [];
        final basic = childrenData.map((e) => Category.fromJson(e)).toList();
        final full = await enrichCategories(basic);
        cachedCategories = full;
        prefs.setString('cached_categories_data', jsonEncode(full.map((e) => e.toJson()).toList()));
        return cachedCategories;
      }
    } catch (e) {}
    return [];
  }

  Future<List<Category>> enrichCategories(List<Category> categories) async {
    final prefs = await SharedPreferences.getInstance();
    if (_detailsCache.isEmpty && prefs.containsKey('category_details_cache')) {
      try {
        final decoded = jsonDecode(prefs.getString('category_details_cache')!) as Map<String, dynamic>;
        _detailsCache = decoded.map((key, value) => MapEntry(key, Category.fromJson(value)));
      } catch (e) {}
    }

    List<Future<Category>> tasks = categories.map((cat) async {
      final idStr = cat.id.toString();
      if (_detailsCache.containsKey(idStr)) {
        final cached = _detailsCache[idStr]!;
        return Category(id: cached.id, name: cached.name, isActive: cached.isActive, imageUrl: cached.imageUrl, children: cat.children);
      }
      try {
        final response = await _oauthClient.get("/categories/${cat.id}");
        if (response.statusCode == 200) {
          final detailCat = Category.fromJson(jsonDecode(response.body));
          _detailsCache[idStr] = detailCat;
          return Category(id: detailCat.id, name: detailCat.name, isActive: detailCat.isActive, imageUrl: detailCat.imageUrl, children: cat.children);
        }
      } catch (e) {}
      return cat;
    }).toList();

    final results = await Future.wait(tasks);
    try {
      final saveMap = _detailsCache.map((key, value) => MapEntry(key, value.toJson()));
      await prefs.setString('category_details_cache', jsonEncode(saveMap));
    } catch (e) {}
    return results.where((c) => c.isActive).toList();
  }

  Future<List<Product>> fetchProducts({int? categoryId}) async {
    if (categoryId == null && cachedProducts.isNotEmpty) return cachedProducts;
    try {
      final Map<String, String> queryParams = {"searchCriteria[pageSize]": "20"};
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
        if (categoryId == null) cachedProducts = products;
        return products;
      }
    } catch (e) {}
    return [];
  }

  Future<Product?> fetchProductBySku(String sku) async {
    try {
      final response = await _oauthClient.get("/products", params: {
        "searchCriteria[filter_groups][0][filters][0][field]": "sku",
        "searchCriteria[filter_groups][0][filters][0][value]": sku,
        "searchCriteria[filter_groups][0][filters][0][condition_type]": "eq",
      });
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final items = data["items"] as List? ?? [];
        if (items.isNotEmpty) return Product.fromJson(items.first);
      }
    } catch (e) {}
    return null;
  }

  Future<List<Order>> fetchOrders(String email, {int pageSize = 5}) async {
    try {
      final response = await _oauthClient.get("/orders", params: {
        "searchCriteria[filter_groups][0][filters][0][field]": "customer_email",
        "searchCriteria[filter_groups][0][filters][0][value]": email,
        "searchCriteria[filter_groups][0][filters][0][condition_type]": "eq",
        "searchCriteria[sortOrders][0][field]": "created_at",
        "searchCriteria[sortOrders][0][direction]": "DESC",
        "searchCriteria[pageSize]": pageSize.toString(),
      });
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final items = data["items"] as List? ?? [];
        return items.map((e) => Order.fromJson(e)).toList();
      }
    } catch (e) {}
    return [];
  }

  // --- AUTH & PROFILE ---
  Future<String?> loginCustomer(String email, String password) async {
    try {
      final response = await http.post(
        Uri.parse("$baseUrl/rest/V1/integration/customer/token"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"username": email, "password": password}),
      );
      if (response.statusCode == 200) return jsonDecode(response.body);
    } catch (e) {}
    return null;
  }

  Future<bool> createCustomer(String fName, String lName, String email, String password) async {
    try {
      final response = await http.post(
        Uri.parse("$baseUrl/rest/V1/customers"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"customer": {"email": email, "firstname": fName, "lastname": lName}, "password": password}),
      );
      return response.statusCode == 200;
    } catch (e) { return false; }
  }

  Future<Map<String, dynamic>?> fetchCustomerDetails(String token) async {
    try {
      final response = await http.get(Uri.parse("$baseUrl/rest/V1/customers/me"), headers: {"Authorization": "Bearer $token"});
      if (response.statusCode == 200) return jsonDecode(response.body);
    } catch (e) { return null; }
  }

  Future<bool> saveAddress(Map<String, dynamic> addressData) async {
    final token = await _getCustomerToken();
    if (token == null) return false;
    try {
      final user = await fetchCustomerDetails(token);
      if (user == null) return false;
      List<dynamic> addresses = user['addresses'] ?? [];
      if (addressData['id'] != null) addresses.removeWhere((a) => a['id'] == addressData['id']);
      addressData['region_id'] = 0;
      addressData['customer_id'] = user['id'];
      addresses.add(addressData);
      
      final response = await http.put(
        Uri.parse("$baseUrl/rest/V1/customers/me"),
        headers: {"Authorization": "Bearer $token", "Content-Type": "application/json"},
        body: jsonEncode({"customer": {...user, "addresses": addresses}}),
      );
      return response.statusCode == 200;
    } catch (e) { return false; }
  }

  Future<bool> updateCustomerProfile(Map<String, dynamic> customerData) async {
    final token = await _getCustomerToken();
    if (token == null) return false;
    try {
      final current = await fetchCustomerDetails(token);
      if (current == null) return false;
      final response = await http.put(
        Uri.parse("$baseUrl/rest/V1/customers/me"),
        headers: {"Authorization": "Bearer $token", "Content-Type": "application/json"},
        body: jsonEncode({"customer": {...current, ...customerData}}),
      );
      return response.statusCode == 200;
    } catch (e) { return false; }
  }

  Future<bool> changePassword(String currentPass, String newPass) async {
    final token = await _getCustomerToken();
    if (token == null) return false;
    try {
      final response = await http.put(
        Uri.parse("$baseUrl/rest/V1/customers/me/password"),
        headers: {"Authorization": "Bearer $token", "Content-Type": "application/json"},
        body: jsonEncode({"currentPassword": currentPass, "newPassword": newPass}),
      );
      return response.statusCode == 200;
    } catch (e) { return false; }
  }

  Future<String?> _getCustomerToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('customer_token');
  }
}