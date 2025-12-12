// lib/api/magento_api.dart
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/magento_models.dart';

class MagentoAPI {
  final Dio _dio = Dio();
  final String baseUrl = dotenv.env['MAGENTO_BASE_URL'] ?? "https://buynutbolts.com";
  
  String? _accessToken;
  
  static List<Category> cachedCategories = [];
  static List<Product> cachedProducts = [];
  static Map<String, Category> _detailsCache = {};

  MagentoAPI() {
    _dio.options.baseUrl = "$baseUrl/rest/V1";
    _dio.options.headers = {
      "Content-Type": "application/json",
      "Accept": "application/json",
    };
  }

  // --- NEW: FORCE REFRESH LOGIC ---
  Future<void> clearCache() async {
    cachedCategories.clear();
    cachedProducts.clear();
    _detailsCache.clear();
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('cached_categories_data');
    await prefs.remove('cached_products_data');
    await prefs.remove('category_details_cache');
    
    print("🧹 Cache Cleared");
  }

  // --- NEW: FETCH SINGLE PRODUCT (For Refreshing Product Page) ---
  Future<Product?> fetchProductBySku(String sku) async {
    await _ensureToken();
    try {
      final response = await _dio.get(
        "/products",
        queryParameters: {
          "searchCriteria[filter_groups][0][filters][0][field]": "sku",
          "searchCriteria[filter_groups][0][filters][0][value]": sku,
          "searchCriteria[filter_groups][0][filters][0][condition_type]": "eq",
        },
      );
      final items = response.data["items"] as List? ?? [];
      if (items.isNotEmpty) {
        return Product.fromJson(items.first);
      }
      return null;
    } catch (e) {
      print("Error fetching product by SKU: $e");
      return null;
    }
  }

  Future<void> _ensureToken() async {
    if (_accessToken != null) {
      _dio.options.headers["Authorization"] = "Bearer $_accessToken";
      return;
    }
    try {
      final username = dotenv.env['MAGENTO_ADMIN_USERNAME'];
      final password = dotenv.env['MAGENTO_ADMIN_PASSWORD'];
      if (username == null || password == null) return;

      final response = await _dio.post(
        "/integration/admin/token",
        data: {"username": username, "password": password},
      );
      _accessToken = response.data;
      _dio.options.headers["Authorization"] = "Bearer $_accessToken";
    } catch (e) {
      print("AUTH ERROR: $e");
    }
  }

  // --- CUSTOMER AUTH ---
  Future<String?> loginCustomer(String email, String password) async {
    try {
      final response = await _dio.post(
        "/integration/customer/token",
        data: {"username": email, "password": password},
      );
      return response.data;
    } on DioException catch (e) {
      print("Login Error: ${e.response?.data}");
      return null;
    }
  }

  Future<bool> createCustomer(String firstName, String lastName, String email, String password) async {
    try {
      await _dio.post(
        "/customers",
        data: {
          "customer": {"email": email, "firstname": firstName, "lastname": lastName},
          "password": password
        },
      );
      return true;
    } on DioException catch (e) {
      print("Signup Error: ${e.response?.data}");
      return false;
    }
  }

  Future<Map<String, dynamic>?> fetchCustomerDetails(String customerToken) async {
    try {
      final response = await _dio.get(
        "/customers/me",
        options: Options(headers: {"Authorization": "Bearer $customerToken"}),
      );
      return response.data;
    } catch (e) {
      return null;
    }
  }

  // --- CATEGORIES ---
  Future<List<Category>> fetchCategories() async {
    if (cachedCategories.isNotEmpty) return cachedCategories;

    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey('cached_categories_data')) {
      try {
        final String jsonStr = prefs.getString('cached_categories_data')!;
        final List decoded = jsonDecode(jsonStr);
        cachedCategories = decoded.map((e) => Category.fromJson(e)).toList();
        if (cachedCategories.isNotEmpty) return cachedCategories; 
      } catch (e) {}
    }

    await _ensureToken();
    try {
      final response = await _dio.get("/categories");
      final childrenData = response.data['children_data'] as List? ?? [];
      final basicCategories = childrenData.map((e) => Category.fromJson(e)).toList();
      final fullCategories = await enrichCategories(basicCategories);
      cachedCategories = fullCategories;

      final saveStr = jsonEncode(fullCategories.map((e) => e.toJson()).toList());
      await prefs.setString('cached_categories_data', saveStr);

      return cachedCategories;
    } on DioException catch (e) {
      return [];
    }
  }

  Future<List<Category>> enrichCategories(List<Category> categories) async {
    final prefs = await SharedPreferences.getInstance();
    if (_detailsCache.isEmpty && prefs.containsKey('category_details_cache')) {
      try {
        final String jsonStr = prefs.getString('category_details_cache')!;
        final Map<String, dynamic> decoded = jsonDecode(jsonStr);
        _detailsCache = decoded.map((key, value) => MapEntry(key, Category.fromJson(value)));
      } catch (e) {}
    }

    await _ensureToken();
    List<Future<Category>> tasks = categories.map((cat) async {
      final String idStr = cat.id.toString();
      if (_detailsCache.containsKey(idStr)) {
        final cachedCat = _detailsCache[idStr]!;
        return Category(
          id: cachedCat.id,
          name: cachedCat.name,
          isActive: cachedCat.isActive,
          imageUrl: cachedCat.imageUrl, 
          children: cat.children, 
        );
      }
      try {
        final detailResponse = await _dio.get("/categories/${cat.id}");
        final detailJson = detailResponse.data as Map<String, dynamic>;
        Category detailCat = Category.fromJson(detailJson);
        _detailsCache[idStr] = detailCat;
        return Category(
          id: detailCat.id,
          name: detailCat.name,
          isActive: detailCat.isActive,
          imageUrl: detailCat.imageUrl, 
          children: cat.children, 
        );
      } catch (e) { return cat; }
    }).toList();

    final results = await Future.wait(tasks);
    try {
      final saveMap = _detailsCache.map((key, value) => MapEntry(key, value.toJson()));
      await prefs.setString('category_details_cache', jsonEncode(saveMap));
    } catch (e) {}

    return results.where((c) => c.isActive).toList();
  }

  // --- PRODUCTS ---
  Future<List<Product>> fetchProducts({int? categoryId}) async {
    if (categoryId == null) {
      if (cachedProducts.isNotEmpty) return cachedProducts;
      final prefs = await SharedPreferences.getInstance();
      if (prefs.containsKey('cached_products_data')) {
        try {
          final String jsonStr = prefs.getString('cached_products_data')!;
          final List decoded = jsonDecode(jsonStr);
          cachedProducts = decoded.map((e) => Product.fromJson(e)).toList();
          if (cachedProducts.isNotEmpty) return cachedProducts;
        } catch (e) {}
      }
    }

    await _ensureToken();
    try {
      final queryParams = {"searchCriteria[pageSize]": "20"};
      if (categoryId != null) {
        queryParams["searchCriteria[filter_groups][0][filters][0][field]"] = "category_id";
        queryParams["searchCriteria[filter_groups][0][filters][0][value]"] = "$categoryId";
        queryParams["searchCriteria[filter_groups][0][filters][0][condition_type]"] = "eq";
      }

      final response = await _dio.get("/products", queryParameters: queryParams);
      final items = response.data["items"] as List? ?? [];
      final products = items.map((json) => Product.fromJson(json)).toList();

      if (categoryId == null) {
        cachedProducts = products;
        final prefs = await SharedPreferences.getInstance();
        final saveStr = jsonEncode(products.map((e) => e.toJson()).toList());
        await prefs.setString('cached_products_data', saveStr);
      }
      return products;
    } on DioException catch (e) {
      return [];
    }
  }
}