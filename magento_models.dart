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

  Category({
    required this.id,
    required this.name,
    this.imageUrl,
    required this.isActive,
  });

  // --- MANUAL IMAGE MAPPING ---
  // Key = Exact Category Name from Magento
  // Value = The specific URL you provided
  static final Map<String, String> _manualImageMap = {

    "Hex Bolts": "https://buynutbolts.com/media/catalog/category/hexbolt_Custom_.jpg",
    "Socket Head Screws": "https://buynutbolts.com/media/catalog/category/allen_screw_Custom_.jpg",
    "Screws": "https://buynutbolts.com/media/catalog/category/Screw_Custom_.jpg",
    "Anchor Bolts": "https://buynutbolts.com/media/catalog/category/Anchor_Boltnew.jpg",
    "Self Clinch": "https://buynutbolts.com/media/catalog/category/self_clintch_fastner_Custom_.jpg",
    "Nuts": "https://buynutbolts.com/media/catalog/category/Nut_Custom_.jpg",
    "Washers": "https://buynutbolts.com/media/catalog/category/washer2_Custom_.jpg",
    "Rivets": "https://buynutbolts.com/media/catalog/category/rivets_Custom_.jpg",
    "Spacers and Standoffs": "https://buynutbolts.com/media/catalog/category/spacer_Custom_.jpg",
    "Rods and Studs": "https://buynutbolts.com/media/catalog/category/rod_Custom_.jpg",
    "Circlips": "https://buynutbolts.com/media/catalog/category/circlip_Custom_.jpg",
    "Tools": "https://buynutbolts.com/media/catalog/category/tools_Custom_.jpg",
    "Fasteners New Machineries": "https://buynutbolts.com/media/catalog/category/fasteners_machine.jpg",
    "Fasteners Refurbished Machineries": "https://buynutbolts.com/media/catalog/category/refurbished_machine.jpg",
    "Surplus Stock": "https://buynutbolts.com/media/catalog/category/surplus_stock.jpg",
    "Dies and Punches": "https://buynutbolts.com/media/catalog/category/die_and_punch_Custom_.jpg",
  };

  factory Category.fromJson(Map<String, dynamic> json) {
    String name = json['name'] ?? 'Unknown';

    // 1. Try to get image from API first
    String getAttribute(String code) {
      if (json['custom_attributes'] == null) return '';
      final attributes = json['custom_attributes'] as List;
      final attr = attributes.firstWhere(
        (element) => element['attribute_code'] == code,
        orElse: () => {'value': null},
      );
      return attr['value']?.toString() ?? '';
    }

    String apiImageName = getAttribute('image');
    String? finalImageUrl;

    // 2. Logic: API Image > Manual Map (Exact Name) > Placeholder
    if (apiImageName.isNotEmpty) {
      if (apiImageName.startsWith('http')) {
        finalImageUrl = apiImageName;
      } else {
        finalImageUrl = "https://buynutbolts.com/media/catalog/category/$apiImageName";
      }
    } else {
      // Direct lookup by Name
      if (_manualImageMap.containsKey(name)) {
        finalImageUrl = _manualImageMap[name];
      } else {
        // Optional: Try trimming extra spaces just in case
        finalImageUrl = _manualImageMap[name.trim()];
      }
    }

    return Category(
      id: json['id'],
      name: name,
      isActive: json['is_active'] ?? true,
      imageUrl: finalImageUrl, 
    );
  }
}