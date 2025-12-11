// lib/models/magento_models.dart

class Product {
  final String name;
  final String sku;
  final double price;
  final String imageUrl;
  final String description; // Added

  Product({
    required this.name,
    required this.sku,
    required this.price,
    required this.imageUrl,
    required this.description, // Added
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

    // Parse Description
    String desc = getAttribute('description');
    if (desc.isEmpty) desc = getAttribute('short_description');
    // Simple HTML strip (optional)
    desc = desc.replaceAll(RegExp(r'<[^>]*>'), '');
    if (desc.isEmpty) desc = "No description available.";

    return Product(
      name: json['name'] ?? 'Unknown',
      sku: json['sku'] ?? '',
      price: (json['price'] ?? 0).toDouble(),
      imageUrl: fullImageUrl,
      description: desc,
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

    String? finalImageUrl;
    String getAttribute(String code) {
      if (json['custom_attributes'] == null) return '';
      final attributes = json['custom_attributes'] as List;
      final attr = attributes.firstWhere(
        (element) => element['attribute_code'] == code,
        orElse: () => {'value': null},
      );
      return attr['value']?.toString() ?? '';
    }

    String apiImageValue = getAttribute('thumbnail');
    if (apiImageValue.isEmpty) apiImageValue = getAttribute('image');

    if (apiImageValue.isNotEmpty) {
      if (apiImageValue.startsWith('http')) {
        finalImageUrl = apiImageValue;
      } else if (apiImageValue.startsWith('/media/')) {
        finalImageUrl = "https://buynutbolts.com$apiImageValue";
      } else {
        finalImageUrl = "https://buynutbolts.com/media/catalog/category/$apiImageValue";
      }
    }

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