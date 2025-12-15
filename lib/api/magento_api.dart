// lib/api/magento_api.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/magento_models.dart';
import 'magento_oauth_client.dart'; // Import the new client

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

  Future<void> clearCache() async {
    cachedCategories.clear();
    cachedProducts.clear();
    _detailsCache.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('cached_categories_data');
    await prefs.remove('cached_products_data');
    await prefs.remove('category_details_cache');
  }

  // ======================================================
  // 1. PUBLIC / SYSTEM DATA (Using OAuth)
  // ======================================================

  Future<List<Category>> fetchCategories() async {
    if (cachedCategories.isNotEmpty) return cachedCategories;
    
    // Check Disk Cache
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey('cached_categories_data')) {
      try {
        final decoded = jsonDecode(prefs.getString('cached_categories_data')!);
        cachedCategories = (decoded as List).map((e) => Category.fromJson(e)).toList();
        if (cachedCategories.isNotEmpty) return cachedCategories;
      } catch (e) {}
    }

    // Fetch from Network via OAuth
    try {
      final response = await _oauthClient.get("/categories");
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final childrenData = data['children_data'] as List? ?? [];
        final basicCategories = childrenData.map((e) => Category.fromJson(e)).toList();
        
        final fullCategories = await enrichCategories(basicCategories);
        cachedCategories = fullCategories;

        // Save
        prefs.setString('cached_categories_data', jsonEncode(fullCategories.map((e) => e.toJson()).toList()));
        return cachedCategories;
      }
    } catch (e) {
      print("Categories Error: $e");
    }
    return [];
  }

  Future<List<Category>> enrichCategories(List<Category> categories) async {
    final prefs = await SharedPreferences.getInstance();
    // Load existing details cache
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
    
    // Save details cache
    try {
      final saveMap = _detailsCache.map((key, value) => MapEntry(key, value.toJson()));
      await prefs.setString('category_details_cache', jsonEncode(saveMap));
    } catch (e) {}

    return results.where((c) => c.isActive).toList();
  }

  Future<List<Product>> fetchProducts({int? categoryId}) async {
    // Cache check for "All Products"
    if (categoryId == null) {
      if (cachedProducts.isNotEmpty) return cachedProducts;
      final prefs = await SharedPreferences.getInstance();
      if (prefs.containsKey('cached_products_data')) {
        try {
          final decoded = jsonDecode(prefs.getString('cached_products_data')!);
          cachedProducts = (decoded as List).map((e) => Product.fromJson(e)).toList();
          if (cachedProducts.isNotEmpty) return cachedProducts;
        } catch (e) {}
      }
    }

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

        if (categoryId == null) {
          cachedProducts = products;
          final prefs = await SharedPreferences.getInstance();
          prefs.setString('cached_products_data', jsonEncode(products.map((e) => e.toJson()).toList()));
        }
        return products;
      }
    } catch (e) {
      print("Product Error: $e");
    }
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

  // --- Orders via Admin/Integration Search ---
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
    } catch (e) {
      print("Fetch Orders Error: $e");
    }
    return [];
  }

  // ======================================================
  // 2. CUSTOMER DATA (Standard Bearer Token / No OAuth)
  // ======================================================

  Future<String?> loginCustomer(String email, String password) async {
    try {
      final response = await http.post(
        Uri.parse("$baseUrl/rest/V1/integration/customer/token"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"username": email, "password": password}),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body); // Returns token string
      }
    } catch (e) {
      print("Login Error: $e");
    }
    return null;
  }

  Future<bool> createCustomer(String firstName, String lastName, String email, String password) async {
    try {
      final response = await http.post(
        Uri.parse("$baseUrl/rest/V1/customers"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "customer": {"email": email, "firstname": firstName, "lastname": lastName},
          "password": password
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      print("Signup Error: $e");
      return false;
    }
  }

  Future<Map<String, dynamic>?> fetchCustomerDetails(String customerToken) async {
    try {
      final response = await http.get(
        Uri.parse("$baseUrl/rest/V1/customers/me"),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $customerToken"
        },
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      print("Fetch User Error: $e");
    }
    return null;
  }

  // --- CHECKOUT & CART (Using Bearer Token) ---

  Future<String?> createCart() async {
    final token = await _getCustomerToken();
    if (token == null) return null;
    try {
      final response = await http.post(
        Uri.parse("$baseUrl/rest/V1/carts/mine"),
        headers: {"Authorization": "Bearer $token", "Content-Type": "application/json"},
      );
      if (response.statusCode == 200) return jsonDecode(response.body).toString();
    } catch (e) {}
    return null;
  }

  Future<bool> addItemToCart(String quoteId, Product product, int qty) async {
    final token = await _getCustomerToken();
    if (token == null) return false;
    try {
      final response = await http.post(
        Uri.parse("$baseUrl/rest/V1/carts/mine/items"),
        headers: {"Authorization": "Bearer $token", "Content-Type": "application/json"},
        body: jsonEncode({
          "cartItem": {"sku": product.sku, "qty": qty, "quote_id": quoteId}
        }),
      );
      return response.statusCode == 200;
    } catch (e) { return false; }
  }

  Future<bool> setShippingInformation(Map<String, dynamic> address) async {
    final token = await _getCustomerToken();
    if (token == null) return false;
    try {
      final payload = {
        "region": address["region"] ?? {"region_code": "KA", "region": "Karnataka", "region_id": 0},
        "country_id": "IN",
        "street": address["street"],
        "telephone": address["telephone"],
        "postcode": address["postcode"],
        "city": address["city"],
        "firstname": address["firstname"],
        "lastname": address["lastname"],
        "email": address["email"] ?? "user@example.com",
        "same_as_billing": 1
      };

      final response = await http.post(
        Uri.parse("$baseUrl/rest/V1/carts/mine/shipping-information"),
        headers: {"Authorization": "Bearer $token", "Content-Type": "application/json"},
        body: jsonEncode({
          "addressInformation": {
            "shipping_address": payload,
            "billing_address": payload,
            "shipping_carrier_code": "flatrate",
            "shipping_method_code": "flatrate"
          }
        }),
      );
      return response.statusCode == 200;
    } catch (e) { return false; }
  }

  Future<String?> placeOrder(String paymentId) async {
    final token = await _getCustomerToken();
    if (token == null) return null;
    try {
      final response = await http.post(
        Uri.parse("$baseUrl/rest/V1/carts/mine/payment-information"),
        headers: {"Authorization": "Bearer $token", "Content-Type": "application/json"},
        body: jsonEncode({
          "paymentMethod": {
            "method": "razorpay", 
            "additional_data": {"razorpay_payment_id": paymentId}
          }
        }),
      );
      if (response.statusCode == 200) return jsonDecode(response.body).toString();
    } catch (e) {}
    return null;
  }

  Future<bool> saveAddress(Map<String, dynamic> addressData) async {
    final token = await _getCustomerToken();
    if (token == null) return false;
    try {
      final currentUser = await fetchCustomerDetails(token);
      if (currentUser == null) return false;

      List<dynamic> addresses = currentUser['addresses'] ?? [];
      if (addressData['id'] != null) addresses.removeWhere((a) => a['id'] == addressData['id']);
      
      addressData['region_id'] = 0;
      addressData['customer_id'] = currentUser['id'];
      addresses.add(addressData);

      final response = await http.put(
        Uri.parse("$baseUrl/rest/V1/customers/me"),
        headers: {"Authorization": "Bearer $token", "Content-Type": "application/json"},
        body: jsonEncode({
          "customer": {
            "email": currentUser['email'],
            "firstname": currentUser['firstname'],
            "lastname": currentUser['lastname'],
            "website_id": currentUser['website_id'],
            "addresses": addresses,
          }
        }),
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
        body: jsonEncode({
          "customer": {
            "id": current['id'],
            "email": customerData['email'] ?? current['email'],
            "firstname": customerData['firstname'] ?? current['firstname'],
            "lastname": customerData['lastname'] ?? current['lastname'],
            "website_id": current['website_id'],
          }
        }),
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