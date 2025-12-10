// lib/api/magento_api.dart
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/magento_models.dart';

class MagentoAPI {
  final Dio _dio = Dio();
  final String baseUrl = dotenv.env['MAGENTO_BASE_URL'] ?? "https://buynutbolts.com";
  
  String? _accessToken;
  
  // We keep the cache, but the full restart will clear it
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

  // --- 1. INITIAL FETCH (For Home Screen) ---
  Future<List<Category>> fetchCategories() async {
    // If cache exists, return it. (RESTART APP TO CLEAR THIS IF IMAGES ARE STUCK)
    if (cachedCategories.isNotEmpty) return cachedCategories;

    await _ensureToken();
    try {
      final response = await _dio.get("/categories");
      // The tree response contains the structure (children) but lacks images.
      final childrenData = response.data['children_data'] as List? ?? [];
      
      // Convert raw JSON to objects first
      final basicCategories = childrenData.map((e) => Category.fromJson(e)).toList();

      // Now "Enrich" them (fetch images for each)
      final fullCategories = await enrichCategories(basicCategories);
      
      cachedCategories = fullCategories;
      return cachedCategories;

    } on DioException catch (e) {
      print("CATEGORIES ERROR: ${e.response?.statusCode}");
      return [];
    }
  }

  // --- 2. ENRICH CATEGORIES (The "Cleaner" Merge Fix) ---
  // This takes a category (which has children but no image)
  // and merges it with the detail (which has image but no children).
  Future<List<Category>> enrichCategories(List<Category> categories) async {
    await _ensureToken();

    List<Future<Category>> tasks = categories.map((cat) async {
      try {
        // Fetch details (to get the thumbnail/image)
        final detailResponse = await _dio.get("/categories/${cat.id}");
        final detailJson = detailResponse.data as Map<String, dynamic>;

        // Parse the "Detail" category to get the correct Image URL
        Category detailCat = Category.fromJson(detailJson);
        
        // --- THE FIX: MERGE OBJECTS ---
        // We create a new Category that has:
        // 1. The Image from the Detail call
        // 2. The Children from the Original Tree call (preserving the hierarchy)
        return Category(
          id: detailCat.id,
          name: detailCat.name,
          isActive: detailCat.isActive,
          imageUrl: detailCat.imageUrl, // Use the fetched image
          children: cat.children,       // Keep original subcategories
        );

      } catch (e) {
        // If detail fetch fails, just return the original (no image, but data exists)
        print("Failed to enrich category ${cat.name}: $e");
        return cat;
      }
    }).toList();

    final results = await Future.wait(tasks);
    return results.where((c) => c.isActive).toList();
  }

  Future<List<Product>> fetchProducts({int? categoryId}) async {
    if (categoryId == null && cachedProducts.isNotEmpty) return cachedProducts;

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

      if (categoryId == null) cachedProducts = products;
      
      return products;
    } on DioException catch (e) {
      print("PRODUCT ERROR: ${e.response?.statusCode}");
      return [];
    }
  }
}