// lib/api/magento_api.dart
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/magento_models.dart';

class MagentoAPI {
  final Dio _dio = Dio();
  final String baseUrl = dotenv.env['MAGENTO_BASE_URL'] ?? "https://buynutbolts.com";
  
  String? _accessToken;

  MagentoAPI() {
    _dio.options.baseUrl = "$baseUrl/rest/V1";
    _dio.options.headers = {
      "Content-Type": "application/json",
      "Accept": "application/json",
    };
  }

  // --- AUTOMATIC AUTHENTICATION ---
  Future<void> _ensureToken() async {
    if (_accessToken != null) {
      _dio.options.headers["Authorization"] = "Bearer $_accessToken";
      return;
    }

    try {
      final username = dotenv.env['MAGENTO_ADMIN_USERNAME'];
      final password = dotenv.env['MAGENTO_ADMIN_PASSWORD'];

      if (username == null || password == null) {
        print("AUTH ERROR: Admin credentials missing in .env");
        return;
      }

      final response = await _dio.post(
        "/integration/admin/token",
        data: {
          "username": username,
          "password": password,
        },
      );

      _accessToken = response.data;
      _dio.options.headers["Authorization"] = "Bearer $_accessToken";
    } catch (e) {
      print("AUTH ERROR: Failed to fetch token. $e");
    }
  }

  // --- CATEGORIES (The Hybrid Fix) ---
  Future<List<Category>> fetchCategories() async {
    await _ensureToken();

    try {
      // 1. Fetch the Tree (Contains structure/children, but often missing images)
      final response = await _dio.get("/categories");
      final children = response.data['children_data'] as List? ?? [];

      // 2. Fetch Details for each top-level category to get the 'custom_attributes' (Image)
      // We use Future.wait to do this in parallel for speed.
      List<Future<Category>> tasks = children.map((childData) async {
        try {
          final id = childData['id'];
          
          // Call the specific endpoint you mentioned: /categories/{id}
          final detailResponse = await _dio.get("/categories/$id");
          final detailJson = detailResponse.data as Map<String, dynamic>;

          // IMPORTANT: The detail call has the Image, but usually MISSES the subcategories (children_data).
          // The tree call (childData) has the subcategories but MISSES the Image.
          // WE MUST MERGE THEM.
          if (childData['children_data'] != null) {
            detailJson['children_data'] = childData['children_data'];
          }

          return Category.fromJson(detailJson);
        } catch (e) {
          print("Error fetching details for ID ${childData['id']}: $e");
          // If detail fetch fails, fall back to the basic tree data
          return Category.fromJson(childData);
        }
      }).toList();

      final fullCategories = await Future.wait(tasks);

      return fullCategories
          .where((c) => c.isActive)
          .toList();

    } on DioException catch (e) {
      print("CATEGORIES ERROR: ${e.response?.statusCode} - ${e.response?.data}");
      return [];
    }
  }

  // --- PRODUCTS ---
  Future<List<Product>> fetchProducts({int? categoryId}) async {
    await _ensureToken();

    try {
      final queryParams = {
        "searchCriteria[pageSize]": "20",
      };

      if (categoryId != null) {
        queryParams["searchCriteria[filter_groups][0][filters][0][field]"] = "category_id";
        queryParams["searchCriteria[filter_groups][0][filters][0][value]"] = "$categoryId";
        queryParams["searchCriteria[filter_groups][0][filters][0][condition_type]"] = "eq";
      }

      final response = await _dio.get(
        "/products",
        queryParameters: queryParams,
      );

      final items = response.data["items"] as List? ?? [];
      return items.map((json) => Product.fromJson(json)).toList();

    } on DioException catch (e) {
      print("PRODUCT ERROR: ${e.response?.statusCode} - ${e.response?.data}");
      return [];
    }
  }
}