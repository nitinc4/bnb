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
    // Helper to find custom attributes like 'image'
    String getAttribute(String code) {
      final attributes = json['custom_attributes'] as List;
      final attr = attributes.firstWhere(
        (element) => element['attribute_code'] == code,
        orElse: () => {'value': null},
      );
      return attr['value']?.toString() ?? '';
    }

    String imagePath = getAttribute('image'); // or 'small_image'
    // Magento API returns relative paths like /w/e/weapon.jpg
    String fullImageUrl = imagePath.isNotEmpty
        ? "https://buynutbolts.com/media/catalog/product$imagePath"
        : "https://buynutbolts.com/media/catalog/product/placeholder.jpg"; // Fallback

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

  Category({
    required this.id,
    required this.name,
    this.imageUrl,
    required this.isActive,
  });

  factory Category.fromJson(Map<String, dynamic> json) {
    // Note: Category images in Magento often require a specific custom attribute or extension to fetch via API cleanly.
    // For now, we will try to grab standard 'image' custom attribute if available.
    
    // Recursive parsing is usually needed for the category tree, 
    // but here we just map the simple fields.
    return Category(
      id: json['id'],
      name: json['name'],
      isActive: json['is_active'] ?? true,
      imageUrl: "https://buynutbolts.com/media/catalog/category/bolt_icon.png", // Placeholder/Logic needed based on your specific attribute
    );
  }
}