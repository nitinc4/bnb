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

  MagentoAPI() {
    _dio.options.baseUrl = "$baseUrl/rest/V1";
    _dio.options.headers = {
      "Content-Type": "application/json",
      "Accept": "application/json",
    };
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

  Future<List<Category>> fetchCategories() async {
    if (cachedCategories.isNotEmpty) return cachedCategories;

    final prefs = await SharedPreferences.getInstance();

    // 1. Check Disk Cache
    if (prefs.containsKey('cached_categories_data')) {
      try {
        final String jsonStr = prefs.getString('cached_categories_data')!;
        final List decoded = jsonDecode(jsonStr);
        cachedCategories = decoded.map((e) => Category.fromJson(e)).toList();
        if (cachedCategories.isNotEmpty) return cachedCategories; 
      } catch (e) {
        print("Error reading cache: $e");
      }
    }

    // 2. Fetch from Network
    await _ensureToken();
    try {
      final response = await _dio.get("/categories");
      final childrenData = response.data['children_data'] as List? ?? [];
      
      final basicCategories = childrenData.map((e) => Category.fromJson(e)).toList();
      final fullCategories = await enrichCategories(basicCategories);
      
      cachedCategories = fullCategories;

      // 3. Save to Disk
      final saveStr = jsonEncode(fullCategories.map((e) => e.toJson()).toList());
      await prefs.setString('cached_categories_data', saveStr);

      return cachedCategories;

    } on DioException catch (e) {
      print("CATEGORIES ERROR: ${e.response?.statusCode}");
      return [];
    }
  }

  Future<List<Category>> enrichCategories(List<Category> categories) async {
    await _ensureToken();
    List<Future<Category>> tasks = categories.map((cat) async {
      try {
        final detailResponse = await _dio.get("/categories/${cat.id}");
        final detailJson = detailResponse.data as Map<String, dynamic>;
        Category detailCat = Category.fromJson(detailJson);
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
    return results.where((c) => c.isActive).toList();
  }

  Future<List<Product>> fetchProducts({int? categoryId}) async {
    // Only cache "All Products"
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
      print("PRODUCT ERROR: ${e.response?.statusCode}");
      return [];
    }
  }
}