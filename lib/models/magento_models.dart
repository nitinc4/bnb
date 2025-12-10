// lib/models/magento_models.dart

class Product {
  final String name;
  final String sku;
  final double price;
  final String imageUrl;

  Product({
    required this.name,
    required this.sku,
    required this.price,
    required this.imageUrl,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    String getAttribute(String code) {
      if (json['custom_attributes'] == null) return '';
      final attributes = json['custom_attributes'] as List;
      final attr = attributes.firstWhere(
        (element) => element['attribute_code'] == code,
        orElse: () => {'value': null},
      );
      return attr['value']?.toString() ?? '';
    }

    String imagePath = getAttribute('image');
    String fullImageUrl = imagePath.isNotEmpty
        ? "https://buynutbolts.com/media/catalog/product$imagePath"
        : "https://buynutbolts.com/media/catalog/product/placeholder.jpg";

    return Product(
      name: json['name'] ?? 'Unknown',
      sku: json['sku'] ?? '',
      price: (json['price'] ?? 0).toDouble(),
      imageUrl: fullImageUrl,
    );
  }
}

class Category {
  final int id;
  final String name;
  final String? imageUrl;
  final bool isActive;
  final List<Category> children;

  Category({
    required this.id,
    required this.name,
    this.imageUrl,
    required this.isActive,
    required this.children,
  });

  factory Category.fromJson(Map<String, dynamic> json) {
    String name = json['name'] ?? 'Unknown';
    bool isActive = json['is_active'] ?? true;

    // --- IMAGE PARSING LOGIC ---
    String? finalImageUrl;
    
    // Helper to extract attribute
    String getAttribute(String code) {
      if (json['custom_attributes'] == null) return '';
      final attributes = json['custom_attributes'] as List;
      final attr = attributes.firstWhere(
        (element) => element['attribute_code'] == code,
        orElse: () => {'value': null},
      );
      return attr['value']?.toString() ?? '';
    }

    String apiImageValue = getAttribute('image');

    if (apiImageValue.isNotEmpty) {
      if (apiImageValue.startsWith('http')) {
        // Full URL
        finalImageUrl = apiImageValue;
      } else if (apiImageValue.startsWith('/media/')) {
        // Absolute path (e.g., /media/.renditions/...)
        // Matches your specific case!
        finalImageUrl = "https://buynutbolts.com$apiImageValue";
      } else {
        // Relative filename fallback
        finalImageUrl = "https://buynutbolts.com/media/catalog/category/$apiImageValue";
      }
    }

    // --- RECURSIVE CHILDREN ---
    List<Category> childrenList = [];
    if (json['children_data'] != null) {
      childrenList = (json['children_data'] as List)
          .map((childJson) => Category.fromJson(childJson))
          .where((c) => c.isActive)
          .toList();
    }

    return Category(
      id: json['id'],
      name: name,
      isActive: isActive,
      imageUrl: finalImageUrl,
      children: childrenList,
    );
  }
}