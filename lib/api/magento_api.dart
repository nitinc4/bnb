// lib/api/magento_api.dart
// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/magento_models.dart';
import 'magento_oauth_client.dart'; 

class MagentoAPI {
  final String baseUrl = dotenv.env['MAGENTO_BASE_URL'] ?? "https://buynutbolts.com";
  late final MagentoOAuthClient _oauthClient;

  static List<Category> cachedCategories = [];
  static List<Product> cachedProducts = []; // Caches "Default Sort" + "No Filter" only
  static Map<String, Category> _detailsCache = {};
  static Map<String, dynamic>? cachedUser; 

  // 1. Exclude by strict Attribute Code (Technical IDs)
  static const List<String> _excludedAttributeCodes = [
    "ship_bundle_items",
    "page_layout",
    "gift_message_available",
    "tax_class_id",
    "options_container",
    "custom_layout_update",
    "custom_design",
    "msrp_display_actual_price_type",
    "custom_layout",
    "price_view",
    "status",
    "quantity_and_stock_status",
    "visibility",
    "country_of_manufacture",
    "gst_rate",
    "layout",
    "enable_product"
  ];

  // 2. Exclude by Label (User provided list)
  static const List<String> _excludedAttributeLabels = [
    "ship bundle items", 
    "layout", 
    "allow gift message", 
    "gst rate", 
    "display product option in", 
    "custom layout update", 
    "new theme", 
    "to apply on products below minimum set price", 
    "new layout", 
    "display price", 
    "price view", 
    "enable product", 
    "tax class", 
    "quantity", 
    "visibility", 
    "country of manufacture"
  ];

  MagentoAPI() {
    _oauthClient = MagentoOAuthClient(
      baseUrl: "$baseUrl/rest/V1",
      consumerKey: dotenv.env['CONSUMER_KEY'] ?? '',
      consumerSecret: dotenv.env['CONSUMER_SECRET'] ?? '',
      token: dotenv.env['ACCESS_TOKEN'] ?? '',
      tokenSecret: dotenv.env['ACCESS_TOKEN_SECRET'] ?? '',
    );
  }

  // --- MODIFIED: FETCH PRODUCTS WITH PAGINATION, FILTERS AND SORT ---
  Future<List<Product>> fetchProducts({
    int? categoryId, 
    int page = 1, 
    int pageSize = 20,
    Map<String, dynamic>? filters,
    String? sortField,     
    String? sortDirection, 
  }) async {
    // Check if we are using the default sort (Relevance/None)
    bool isDefaultSort = sortField == null || sortField.isEmpty;
    bool hasFilters = filters != null && filters.isNotEmpty;
    bool isFirstPage = page == 1;
    bool isAllProducts = categoryId == null;

    // READ CACHE: Only for All Products, Page 1, No Filters, Default Sort
    if (isAllProducts && isFirstPage && !hasFilters && isDefaultSort && cachedProducts.isNotEmpty) {
      return cachedProducts;
    }
    
    try {
      // Base Params for Pagination
      final Map<String, String> queryParams = {
        "searchCriteria[pageSize]": pageSize.toString(),
        "searchCriteria[currentPage]": page.toString(),
      };

      int groupIndex = 0;

      // Add Category Filter if provided
      if (categoryId != null) {
        queryParams["searchCriteria[filter_groups][$groupIndex][filters][0][field]"] = "category_id";
        queryParams["searchCriteria[filter_groups][$groupIndex][filters][0][value]"] = "$categoryId";
        queryParams["searchCriteria[filter_groups][$groupIndex][filters][0][condition_type]"] = "eq";
        groupIndex++;
      }

      // Add Custom Filters
      if (hasFilters) {
        filters.forEach((key, value) {
          queryParams["searchCriteria[filter_groups][$groupIndex][filters][0][field]"] = key;
          queryParams["searchCriteria[filter_groups][$groupIndex][filters][0][value]"] = value.toString();
          queryParams["searchCriteria[filter_groups][$groupIndex][filters][0][condition_type]"] = "eq";
          groupIndex++;
        });
      }

      // Add Sorting
      if (!isDefaultSort && sortDirection != null) {
        queryParams["searchCriteria[sortOrders][0][field]"] = sortField;
        queryParams["searchCriteria[sortOrders][0][direction]"] = sortDirection;
      }

      final response = await _oauthClient.get("/products", params: queryParams);
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final items = data["items"] as List? ?? [];
        final products = items.map((json) => Product.fromJson(json)).toList();

        // WRITE CACHE: Only for All Products, Page 1, No Filters, Default Sort
        if (isAllProducts && isFirstPage && !hasFilters && isDefaultSort) {
          cachedProducts = products;
          final prefs = await SharedPreferences.getInstance();
          prefs.setString('cached_products_data', jsonEncode(products.map((e) => e.toJson()).toList()));
        }
        return products;
      }
    } catch (e) {
      debugPrint("Fetch Products Error: $e");
    }
    return [];
  }

  // --- NEW: FETCH ATTRIBUTES BY SET ID (For Sub Categories) ---
  Future<List<ProductAttribute>> fetchAttributesBySet(int attributeSetId) async {
    try {
      final response = await _oauthClient.get("/products/attribute-sets/$attributeSetId/attributes");
      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        return data
            .map((e) => ProductAttribute.fromJson(e))
            .where((attr) {
              final isSelect = attr.frontendInput == 'select' || attr.frontendInput == 'multiselect';
              final hasOptions = attr.options.isNotEmpty;
              
              final labelLower = attr.label.toLowerCase().trim();
              final codeLower = attr.code.toLowerCase().trim();
              final codeHumanized = codeLower.replaceAll('_', ' ');

              final isLabelExcluded = _excludedAttributeLabels.any((ex) => 
                  labelLower == ex.toLowerCase().trim() || 
                  codeHumanized.contains(ex.toLowerCase().trim())
              );

              final isCodeExcluded = _excludedAttributeCodes.contains(codeLower);

              return isSelect && hasOptions && !isLabelExcluded && !isCodeExcluded;
            })
            .toList();
      }
    } catch (e) {
      debugPrint("Fetch Attributes Error: $e");
    }
    return [];
  }

  // --- NEW: FETCH ALL FILTERABLE ATTRIBUTES (For All Products Page) ---
  Future<List<ProductAttribute>> fetchGlobalFilterableAttributes() async {
    try {
      final queryParams = {
        "searchCriteria[filter_groups][0][filters][0][field]": "is_filterable",
        "searchCriteria[filter_groups][0][filters][0][value]": "1",
        "searchCriteria[filter_groups][0][filters][0][condition_type]": "eq",
      };
      
      final response = await _oauthClient.get("/products/attributes", params: queryParams);
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final items = data['items'] as List? ?? [];
        return items
            .map((e) => ProductAttribute.fromJson(e))
            .where((attr) => (attr.frontendInput == 'select' || attr.frontendInput == 'multiselect') && attr.options.isNotEmpty)
            .toList();
      }
    } catch (e) {
      debugPrint("Fetch Global Attributes Error: $e");
    }
    return [];
  }

  // --- NEW: BATCH FETCH PRODUCTS BY SKUS (For Cart Images) ---
  Future<List<Product>> _fetchProductsBySkus(List<String> skus) async {
    if (skus.isEmpty) return [];
    try {
      // Join SKUs with comma for 'in' query
      final skuListStr = skus.join(",");
      final queryParams = {
        "searchCriteria[filter_groups][0][filters][0][field]": "sku",
        "searchCriteria[filter_groups][0][filters][0][value]": skuListStr,
        "searchCriteria[filter_groups][0][filters][0][condition_type]": "in",
        "searchCriteria[pageSize]": "${skus.length}" 
      };
      
      final response = await _oauthClient.get("/products", params: queryParams);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final items = data["items"] as List? ?? [];
        return items.map((json) => Product.fromJson(json)).toList();
      }
    } catch (e) {
      debugPrint("Error fetching cart product details: $e");
    }
    return [];
  }

  // --- OTHER EXISTING METHODS ---

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
      } catch (e) {
        debugPrint("Load Cached Categories Error: $e");
      }
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
    } catch (e) {
      debugPrint("Fetch Categories Error: $e");
    }
    return [];
  }

  Future<List<Category>> enrichCategories(List<Category> categories) async {
    final prefs = await SharedPreferences.getInstance();
    if (_detailsCache.isEmpty && prefs.containsKey('category_details_cache')) {
      try {
        _detailsCache = (jsonDecode(prefs.getString('category_details_cache')!) as Map<String, dynamic>).map((k, v) => MapEntry(k, Category.fromJson(v)));
      } catch (e) 
      {
        debugPrint("Load Category Details Cache Error: $e");
      }
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
      } catch (e) {
        debugPrint("Enrich Category ${cat.id} Error: $e");
      }
      return cat;
    }).toList();
    final results = await Future.wait(tasks);
    try {
      prefs.setString('category_details_cache', jsonEncode(_detailsCache.map((k, v) => MapEntry(k, v.toJson()))));
    } catch (e) {
      debugPrint("Save Category Details Cache Error: $e");
    }
    return results.where((c) => c.isActive).toList();
  }

  Future<Product?> fetchProductBySku(String sku) async {
    try {
      final response = await _oauthClient.get("/products", params: {"searchCriteria[filter_groups][0][filters][0][field]": "sku", "searchCriteria[filter_groups][0][filters][0][value]": sku});
      final items = (jsonDecode(response.body)["items"] as List? ?? []);
      if (items.isNotEmpty) return Product.fromJson(items.first);
    } catch (e) {
      debugPrint("Fetch Product by SKU Error: $e");
    }
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
    } catch (e) {
      debugPrint("Search Products Error: $e");
    }
    return [];
  }

  // --- UPDATED: GET CART ITEMS (With Image Fetch) ---
  Future<List<CartItem>?> getCartItems() async {
    final token = await _getCustomerToken();
    if (token == null) return [];
    try {
      final response = await http.get(Uri.parse("$baseUrl/rest/V1/carts/mine/items"), headers: {"Authorization": "Bearer $token", "Content-Type": "application/json"});
      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        List<CartItem> items = data.map((e) => CartItem.fromJson(e)).toList();

        // Fetch images for server items
        if (items.isNotEmpty) {
           final skus = items.map((e) => e.sku).toList();
           
           // Fetch full product details for these SKUs
           final products = await _fetchProductsBySkus(skus);
           
           // Map images back to cart items
           items = items.map((item) {
             final product = products.firstWhere(
               (p) => p.sku == item.sku, 
               orElse: () => Product(name: '', sku: '', price: 0, imageUrl: '', description: '')
             );
             
             if (product.imageUrl.isNotEmpty) {
               return item.copyWith(imageUrl: product.imageUrl);
             }
             return item;
           }).toList();
        }

        return items;
      
      } else if (response.statusCode == 401) return null;
    } catch (e) {
      debugPrint("Get Cart Error: $e");
    }
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
    } catch (e) {
      debugPrint("Fetch Orders Error: $e");
    }
    return [];
  }

  Future<String?> loginCustomer(String e, String p) async {
    try {
      final r = await http.post(Uri.parse("$baseUrl/rest/V1/integration/customer/token"), headers: {"Content-Type": "application/json"}, body: jsonEncode({"username": e, "password": p}));
      if (r.statusCode == 200) return jsonDecode(r.body);
    } catch (e) {
      debugPrint("Login Error: $e");
    }
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
    } catch (e) {
      debugPrint("Fetch Customer Details Error: $e");
    }
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