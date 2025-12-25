// lib/screens/category_detail_screen.dart
import 'package:flutter/material.dart' hide Category;
import '../models/magento_models.dart';
import '../api/magento_api.dart';
import '../widgets/product_card.dart';
import '../widgets/bnb_shimmer.dart';

class CategoryDetailScreen extends StatefulWidget {
  final Category category;

  const CategoryDetailScreen({super.key, required this.category});

  @override
  State<CategoryDetailScreen> createState() => _CategoryDetailScreenState();
}

class _CategoryDetailScreenState extends State<CategoryDetailScreen> {
  final MagentoAPI _api = MagentoAPI();

  late List<Category> _subCategories;
  bool _isLoadingSubCats = false;

  List<Product> _products = [];
  bool _isLoadingProducts = true;

  // Filters
  List<ProductAttribute> _filterAttributes = [];
  final Map<String, dynamic> _activeFilters = {};

  // Sorting
  String? _sortField;
  String? _sortDirection;
  String _sortLabel = 'Relevance';

  @override
  void initState() {
    super.initState();
    _subCategories = widget.category.children;

    if (_subCategories.isNotEmpty) {
      _enrichSubCategories();
    } else {
      _fetchProducts();
    }
  }

  // ─────────────────────────────────────────────
  // SUB-CATEGORY ENRICHMENT
  // ─────────────────────────────────────────────
  Future<void> _enrichSubCategories() async {
    setState(() => _isLoadingSubCats = true);

    try {
      if (_subCategories.isNotEmpty && _subCategories.first.imageUrl == null) {
        final enriched = await _api.enrichCategories(_subCategories);
        if (mounted) _subCategories = enriched;
      }
    } catch (_) {}

    if (mounted) setState(() => _isLoadingSubCats = false);
  }

  // ─────────────────────────────────────────────
  // PRODUCT FETCH
  // ─────────────────────────────────────────────
  Future<void> _fetchProducts() async {
    setState(() => _isLoadingProducts = true);

    final products = await _api.fetchProducts(
      categoryId: widget.category.id,
      filters: _activeFilters.isNotEmpty ? _activeFilters : null,
      sortField: _sortField,
      sortDirection: _sortDirection,
    );

    if (!mounted) return;

    setState(() {
      _products = products;
      _isLoadingProducts = false;
    });

    if (_filterAttributes.isEmpty && products.isNotEmpty) {
      final attributeSetId = products.first.attributeSetId;
      if (attributeSetId > 0) {
        _fetchAndFilterAttributes(attributeSetId, products);
      }
    }
  }

  Future<void> _fetchAndFilterAttributes(
    int attributeSetId,
    List<Product> loadedProducts,
  ) async {
    final allAttrs = await _api.fetchAttributesBySet(attributeSetId);

    final relevantAttrs = allAttrs.where((attr) {
      return loadedProducts.any((product) =>
          product.customAttributes.containsKey(attr.code) &&
          product.customAttributes[attr.code] != null);
    }).toList();

    if (mounted) setState(() => _filterAttributes = relevantAttrs);
  }

  // ─────────────────────────────────────────────
  // REFRESH
  // ─────────────────────────────────────────────
  Future<void> _onRefresh() async {
    if (_subCategories.isNotEmpty) {
      await _enrichSubCategories();
    } else {
      await _fetchProducts();
    }
  }

  // ─────────────────────────────────────────────
  // FILTER UI
  // ─────────────────────────────────────────────
  void _showFilterDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.6,
              maxChildSize: 0.9,
              minChildSize: 0.4,
              builder: (_, controller) {
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            "Filter Products",
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          TextButton(
                            onPressed: () {
                              setState(() => _activeFilters.clear());
                              Navigator.pop(context);
                              _fetchProducts();
                            },
                            child: const Text("Clear All"),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        controller: controller,
                        itemCount: _filterAttributes.length,
                        itemBuilder: (context, index) {
                          final attr = _filterAttributes[index];
                          return ExpansionTile(
                            title: Text(attr.label,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            children: attr.options.map((option) {
                              return RadioListTile<String>(
                                title: Text(option.label),
                                value: option.value,
                                groupValue: _activeFilters[attr.code],
                                activeColor: const Color(0xFF00599c),
                                onChanged: (val) {
                                  setState(() {
                                    if (val != null) {
                                      _activeFilters[attr.code] = val;
                                    }
                                  });
                                  setModalState(() {});
                                },
                              );
                            }).toList(),
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  const Color(0xFF00599c)),
                          onPressed: () {
                            Navigator.pop(context);
                            _fetchProducts();
                          },
                          child: const Text(
                            "Apply Filters",
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  // ─────────────────────────────────────────────
  // SORT UI
  // ─────────────────────────────────────────────
  void _showSortDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text("Sort By",
                  style:
                      TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            _buildSortOption("Relevance", null, null),
            _buildSortOption("Price: Low to High", "price", "ASC"),
            _buildSortOption("Price: High to Low", "price", "DESC"),
            _buildSortOption("Name: A to Z", "name", "ASC"),
            _buildSortOption("Name: Z to A", "name", "DESC"),
            const SizedBox(height: 20),
          ],
        );
      },
    );
  }

  Widget _buildSortOption(String label, String? field, String? dir) {
    final bool isSelected = _sortLabel == label;

    return ListTile(
      leading: Icon(
        isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
        color: isSelected ? const Color(0xFF00599c) : Colors.grey,
      ),
      title: Text(label,
          style: TextStyle(
              fontWeight:
                  isSelected ? FontWeight.bold : FontWeight.normal)),
      onTap: () {
        setState(() {
          _sortField = field;
          _sortDirection = dir;
          _sortLabel = label;
        });
        Navigator.pop(context);
        _fetchProducts();
      },
    );
  }

  // ─────────────────────────────────────────────
  // UI
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final bool hasSubCategories = widget.category.children.isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(widget.category.name),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF00599c)),
        actions: [
          if (!hasSubCategories) ...[
            IconButton(icon: const Icon(Icons.sort), onPressed: _showSortDialog),
            if (_filterAttributes.isNotEmpty)
              IconButton(
                  icon: const Icon(Icons.filter_list),
                  onPressed: _showFilterDialog),
          ],
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        child: hasSubCategories
            ? _buildSubCategoryGrid()
            : _buildProductGrid(),
      ),
    );
  }

  Widget _buildSubCategoryGrid() {
    if (_isLoadingSubCats) return BNBShimmer.categoryGrid();

    return GridView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      gridDelegate:
          const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 0.85),
      itemCount: _subCategories.length,
      itemBuilder: (context, index) {
        final cat = _subCategories[index];
        return GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => CategoryDetailScreen(category: cat)),
          ),
          child: Column(
            children: [
              Expanded(
                child: cat.imageUrl != null
                    ? Image.network(cat.imageUrl!)
                    : Image.asset("assets/icons/placeholder.png"),
              ),
              Text(cat.name, textAlign: TextAlign.center),
            ],
          ),
        );
      },
    );
  }

  Widget _buildProductGrid() {
    if (_isLoadingProducts) return BNBShimmer.productGrid();
    if (_products.isEmpty) return const Center(child: Text("No products found"));

    return GridView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(12),
      itemCount: _products.length,
      gridDelegate:
          const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.7),
      itemBuilder: (context, index) {
        final product = _products[index];
        return GestureDetector(
          onTap: () => Navigator.pushNamed(
              context, '/productDetail',
              arguments: product),
          child: ProductCard(
            name: product.name,
            price: product.price.toStringAsFixed(2),
            imageUrl: product.imageUrl,
          ),
        );
      },
    );
  }
}
