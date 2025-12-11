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
  
  // 1. In-memory cache for the Tree Structure
  static List<Category> cachedCategories = [];
  static List<Product> cachedProducts = [];

  // 2. In-memory cache for Individual Category Details (ID -> Category)
  // This stores the images for subcategories so we don't fetch them twice.
  static Map<String, Category> _detailsCache = {};

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

  // --- FETCH CATEGORIES (ROOT TREE) ---
  Future<List<Category>> fetchCategories() async {
    if (cachedCategories.isNotEmpty) return cachedCategories;

    final prefs = await SharedPreferences.getInstance();

    // A. Check Disk Cache for Tree
    if (prefs.containsKey('cached_categories_data')) {
      try {
        final String jsonStr = prefs.getString('cached_categories_data')!;
        final List decoded = jsonDecode(jsonStr);
        cachedCategories = decoded.map((e) => Category.fromJson(e)).toList();
        if (cachedCategories.isNotEmpty) return cachedCategories; 
      } catch (e) {
        print("Error reading tree cache: $e");
      }
    }

    // B. Fetch from Network
    await _ensureToken();
    try {
      final response = await _dio.get("/categories");
      final childrenData = response.data['children_data'] as List? ?? [];
      
      final basicCategories = childrenData.map((e) => Category.fromJson(e)).toList();
      
      // Enrich (Fetch images)
      final fullCategories = await enrichCategories(basicCategories);
      
      cachedCategories = fullCategories;

      // Save Tree to Disk
      final saveStr = jsonEncode(fullCategories.map((e) => e.toJson()).toList());
      await prefs.setString('cached_categories_data', saveStr);

      return cachedCategories;

    } on DioException catch (e) {
      print("CATEGORIES ERROR: ${e.response?.statusCode}");
      return [];
    }
  }

  // --- ENRICH CATEGORIES (THE FIX FOR SUBCATEGORIES) ---
  // Now uses a persistent map (_detailsCache) to cache subcategory images
  Future<List<Category>> enrichCategories(List<Category> categories) async {
    final prefs = await SharedPreferences.getInstance();

    // 1. Load the Details Cache from Disk (if empty)
    if (_detailsCache.isEmpty && prefs.containsKey('category_details_cache')) {
      try {
        final String jsonStr = prefs.getString('category_details_cache')!;
        final Map<String, dynamic> decoded = jsonDecode(jsonStr);
        _detailsCache = decoded.map((key, value) => MapEntry(key, Category.fromJson(value)));
      } catch (e) {
        print("Error reading details cache: $e");
      }
    }

    await _ensureToken();

    List<Future<Category>> tasks = categories.map((cat) async {
      final String idStr = cat.id.toString();

      // 2. CHECK CACHE FIRST (Instant Load)
      if (_detailsCache.containsKey(idStr)) {
        final cachedCat = _detailsCache[idStr]!;
        // Merge Cached Image with Current Children (Tree Structure)
        return Category(
          id: cachedCat.id,
          name: cachedCat.name,
          isActive: cachedCat.isActive,
          imageUrl: cachedCat.imageUrl, 
          children: cat.children, // Keep original children structure
        );
      }

      // 3. FETCH FROM NETWORK (If not in cache)
      try {
        final detailResponse = await _dio.get("/categories/${cat.id}");
        final detailJson = detailResponse.data as Map<String, dynamic>;
        
        // This object contains the Image
        Category detailCat = Category.fromJson(detailJson);
        
        // Save to Memory Cache
        _detailsCache[idStr] = detailCat;

        return Category(
          id: detailCat.id,
          name: detailCat.name,
          isActive: detailCat.isActive,
          imageUrl: detailCat.imageUrl, 
          children: cat.children, // Keep original children structure
        );
      } catch (e) {
        // Fetch failed? Return original without image
        return cat;
      }
    }).toList();

    final results = await Future.wait(tasks);

    // 4. SAVE CACHE TO DISK (So next restart is fast)
    // We save the flat map of IDs -> Categories with Images
    try {
      final saveMap = _detailsCache.map((key, value) => MapEntry(key, value.toJson()));
      await prefs.setString('category_details_cache', jsonEncode(saveMap));
    } catch (e) {
      print("Error saving details cache: $e");
    }

    return results.where((c) => c.isActive).toList();
  }

  // --- PRODUCTS ---
  Future<List<Product>> fetchProducts({int? categoryId}) async {
    // Only cache "All Products" (Home Screen)
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