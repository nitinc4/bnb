import 'package:flutter/material.dart';

class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final List<Map<String, String>> categories = [
      {
        "name": "Hex Bolts",
        "image":
            "https://buynutbolts.com/media/catalog/category/hexbolt_Custom_.jpg"
      },
      {
        "name": "Nuts",
        "image":
            "https://buynutbolts.com/media/catalog/category/Nut_Custom_.jpg"
      },
      {
        "name": "Washers",
        "image":
            "https://buynutbolts.com/media/catalog/category/washer2_Custom_.jpg"
      },
      {
        "name": "Screws",
        "image":
            "https://buynutbolts.com/media/catalog/category/Screw_Custom_.png"
      },
      {
        "name": "Studs",
        "image":
            "https://buynutbolts.com/media/catalog/category/self_clintch_fastner_Custom_.jpg"
      },
      {
        "name": "Bolts",
        "image":
            "https://buynutbolts.com/media/catalog/category/allen_screw_Custom_.jpg"
      },
      {
        "name": "Bolts",
        "image":
            "https://buynutbolts.com/media/catalog/category/hexbolt_Custom_.jpg"
      },
      {
        "name": "Bolts",
        "image":
            "https://buynutbolts.com/media/catalog/category/hexbolt_Custom_.jpg"
      },
    ];

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          "Categories",
          style: TextStyle(
            color: Color(0xFF00599c),
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 1,
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 1,
        ),
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final cat = categories[index];
          return GestureDetector(
            onTap: () {
              Navigator.pushNamed(
                context,
                '/categoryDetail',
                arguments: cat['name'],
              );
            },
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.network(
                    cat["image"]!,
                    height: 80,
                    width: 80,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    cat["name"]!,
                    style: const TextStyle(
                      color: Color(0xFF00599c),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
