import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class ProductCard extends StatelessWidget {
  final String name;
  final String price;
  final String imageUrl;

  const ProductCard({
    super.key,
    required this.name,
    required this.price,
    required this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    // REMOVED InkWell here. 
    // Now the GestureDetector in HomeScreen/CategoryDetailScreen will receive the tap.
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                width: double.infinity,
                // Added a consistent error widget just in case
                placeholder: (context, url) => Container(color: Colors.grey.shade100),
                errorWidget: (context, url, error) => Container(
                  color: Colors.grey.shade200,
                  child: const Icon(Icons.broken_image, color: Colors.grey),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(
              "₹$price",
              style: const TextStyle(
                  color: Color(0xFF00599c), fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}