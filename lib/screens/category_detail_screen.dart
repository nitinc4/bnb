// lib/screens/category_detail_screen.dart
import 'package:flutter/material.dart';
import '../models/magento_models.dart';
import '../api/magento_api.dart';
import '../widgets/product_card.dart';

class CategoryDetailScreen extends StatefulWidget {
  final Category category;

  const CategoryDetailScreen({super.key, required this.category});

  @override
  State<CategoryDetailScreen> createState() => _CategoryDetailScreenState();
}

class _CategoryDetailScreenState extends State<CategoryDetailScreen> {
  late Future<List<Product>> _productsFuture;
  final MagentoAPI _api = MagentoAPI();
  late List<Category> _subCategories;
  bool _isLoadingSubCats = false;

  @override
  void initState() {
    super.initState();
    _subCategories = widget.category.children;
    if (_subCategories.isNotEmpty) {
      _enrichSubCategories();
    } else {
      _productsFuture = _api.fetchProducts(categoryId: widget.category.id);
    }
  }

  Future<void> _enrichSubCategories() async {
    setState(() => _isLoadingSubCats = true);
    if (_subCategories.isNotEmpty && _subCategories[0].imageUrl == null) {
       try {
         final enriched = await _api.enrichCategories(_subCategories);
         if (mounted) setState(() => _subCategories = enriched);
       } catch (e) {}
    }
    if (mounted) setState(() => _isLoadingSubCats = false);
  }

  Future<void> _onRefresh() async {
    // Re-fetch products or re-enrich subcats
    if (_subCategories.isEmpty) {
      setState(() {
        _productsFuture = _api.fetchProducts(categoryId: widget.category.id);
      });
    } else {
      // Force enrich again (maybe images changed)
      setState(() => _isLoadingSubCats = true);
      try {
         final enriched = await _api.enrichCategories(_subCategories);
         if (mounted) setState(() => _subCategories = enriched);
      } catch (e) {}
      if (mounted) setState(() => _isLoadingSubCats = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    bool hasSubCategories = widget.category.children.isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(widget.category.name),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF00599c)),
      ),
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        child: hasSubCategories ? _buildSubCategoryGrid() : _buildProductGrid(),
      ),
    );
  }

  Widget _buildSubCategoryGrid() {
    if (_isLoadingSubCats) return const Center(child: CircularProgressIndicator());

    return GridView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 16, mainAxisSpacing: 16, childAspectRatio: 0.85),
      itemCount: _subCategories.length,
      itemBuilder: (context, index) {
        final cat = _subCategories[index];
        return GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => CategoryDetailScreen(category: cat))),
          child: Container(
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5, offset: const Offset(0, 3))]),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(child: Padding(padding: const EdgeInsets.all(16.0), child: cat.imageUrl != null ? Image.network(cat.imageUrl!, fit: BoxFit.contain) : Image.asset("assets/icons/placeholder.png", fit: BoxFit.contain))),
                Padding(padding: const EdgeInsets.all(8.0), child: Text(cat.name, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), maxLines: 2)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildProductGrid() {
    return FutureBuilder<List<Product>>(
      future: _productsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Text("No products found"));

        final products = snapshot.data!;
        return GridView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(12),
          itemCount: products.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 0.7),
          itemBuilder: (context, index) {
            final product = products[index];
            return GestureDetector(
              onTap: () => Navigator.pushNamed(context, '/productDetail', arguments: product),
              child: ProductCard(name: product.name, price: product.price.toStringAsFixed(2), imageUrl: product.imageUrl),
            );
          },
        );
      },
    );
  }
}