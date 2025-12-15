// lib/models/magento_models.dart

class Product {
  final String name;
  final String sku;
  final double price;
  final String imageUrl;
  final String description;

  Product({
    required this.name,
    required this.sku,
    required this.price,
    required this.imageUrl,
    required this.description,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'sku': sku,
      'price': price,
      'imageUrl': imageUrl,
      'description': description,
    };
  }

  factory Product.fromStorage(Map<String, dynamic> json) {
    return Product(
      name: json['name'] ?? '',
      sku: json['sku'] ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      imageUrl: json['imageUrl'] ?? '',
      description: json['description'] ?? '',
    );
  }

  factory Product.fromJson(Map<String, dynamic> json) {
    if (json.containsKey('imageUrl') && json.containsKey('description')) {
      return Product.fromStorage(json);
    }

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

    String desc = getAttribute('description');
    if (desc.isEmpty) desc = getAttribute('short_description');
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

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'imageUrl': imageUrl,
      'is_active': isActive,
      'children_data': children.map((c) => c.toJson()).toList(),
    };
  }

  factory Category.fromJson(Map<String, dynamic> json) {
    String name = json['name'] ?? 'Unknown';
    bool isActive = json['is_active'] ?? true;
    String? finalImageUrl;

    if (json.containsKey('imageUrl')) {
      finalImageUrl = json['imageUrl'];
    } else {
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

// --- ORDER MODELS ---

class OrderItem {
  final String name;
  final String sku;
  final double price;
  final int qty;

  OrderItem({
    required this.name,
    required this.sku,
    required this.price,
    required this.qty,
  });

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    return OrderItem(
      name: json['name'] ?? 'Unknown Item',
      sku: json['sku'] ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      qty: (json['qty_ordered'] as num?)?.toInt() ?? 1,
    );
  }
}

class Order {
  final String incrementId;
  final String status;
  final double grandTotal;
  final String createdAt;
  final String shippingName;
  final List<OrderItem> items; // Added
  final String billingName;    // Added

  Order({
    required this.incrementId,
    required this.status,
    required this.grandTotal,
    required this.createdAt,
    required this.shippingName,
    required this.items,
    required this.billingName,
  });

  factory Order.fromJson(Map<String, dynamic> json) {
    // 1. Shipping Name
    String sName = "N/A";
    if (json['extension_attributes'] != null && 
        json['extension_attributes']['shipping_assignments'] != null) {
      final assignments = json['extension_attributes']['shipping_assignments'] as List;
      if (assignments.isNotEmpty) {
        final addr = assignments[0]['shipping']['address'];
        sName = "${addr['firstname'] ?? ''} ${addr['lastname'] ?? ''}".trim();
      }
    }

    // 2. Billing Name
    String bName = "N/A";
    if (json['billing_address'] != null) {
        bName = "${json['billing_address']['firstname'] ?? ''} ${json['billing_address']['lastname'] ?? ''}".trim();
    }

    // 3. Items
    List<OrderItem> orderItems = [];
    if (json['items'] != null) {
      orderItems = (json['items'] as List)
          .map((i) => OrderItem.fromJson(i))
          .toList();
    }

    return Order(
      incrementId: json['increment_id'] ?? 'N/A',
      status: json['status'] ?? 'unknown',
      grandTotal: (json['grand_total'] as num?)?.toDouble() ?? 0.0,
      createdAt: json['created_at'] ?? '',
      shippingName: sName,
      billingName: bName,
      items: orderItems,
    );
  }
}