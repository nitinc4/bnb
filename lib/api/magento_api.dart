import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/magento_models.dart';

class MagentoAPI {
  late final Dio _dio;

  final String baseUrl = dotenv.env['MAGENTO_BASE_URL'] ?? "https://buynutbolts.com";
  final String token = dotenv.env['MAGENTO_BEARER_TOKEN'] ?? "";

  MagentoAPI() {
    _dio = Dio(
      BaseOptions(
        baseUrl: "$baseUrl/rest/V1",
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $token",
        },
      ),
    );
  }

  // CATEGORIES
  Future<List<Category>> fetchCategories() async {
    try {
      final response = await _dio.get("/categories");

      final children = response.data['children_data'] as List? ?? [];
      return children.map((e) => Category.fromJson(e)).toList();

    } on DioException catch (e) {
      print("CATEGORIES ERROR: ${e.response?.data}");
      return [];
    }
  }

  // PRODUCTS
  Future<List<Product>> fetchProducts({int? categoryId}) async {
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
      print("PRODUCT ERROR: ${e.response?.data}");
      return [];
    }
  }
}
