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

  // Product List State
  final List<Product> _products = [];
  bool _isLoading = false; // Unified loading state
  
  // Pagination State
  int _currentPage = 1;
  bool _hasMore = true;
  final int _pageSize = 20;
  final ScrollController _scrollController = ScrollController();

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
    _scrollController.addListener(_onScroll);

    if (_subCategories.isNotEmpty) {
      _enrichSubCategories();
    } else {
      _fetchProducts();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    // Trigger load more when user is 200 pixels from bottom
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoading && _hasMore) {
        _fetchProducts();
      }
    }
  }

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

  Future<void> _fetchProducts({bool refresh = false}) async {
    if (_isLoading) return;

    // Reset logic if this is a refresh (filter/sort change or pull-to-refresh)
    if (refresh) {
      setState(() {
        _products.clear();
        _currentPage = 1;
        _hasMore = true;
      });
    }

    setState(() => _isLoading = true);

    try {
      final newProducts = await _api.fetchProducts(
        categoryId: widget.category.id,
        filters: _activeFilters.isNotEmpty ? _activeFilters : null,
        sortField: _sortField,
        sortDirection: _sortDirection,
        page: _currentPage,
        pageSize: _pageSize,
      );

      if (mounted) {
        setState(() {
          if (newProducts.isEmpty) {
            _hasMore = false;
          } else {
            _products.addAll(newProducts);
            _currentPage++; // Increment page for next fetch
            
            // If less than pageSize returned, we've likely reached the end
            if (newProducts.length < _pageSize) {
              _hasMore = false;
            }
          }
        });

        // Fetch attributes for filters if this is the first batch and we haven't yet
        if (_filterAttributes.isEmpty && _products.isNotEmpty) {
          final attributeSetId = _products.first.attributeSetId;
          if (attributeSetId > 0) {
            _fetchAndFilterAttributes(attributeSetId, _products);
          }
        }
      }
    } catch (e) {
      debugPrint("Error fetching category products: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchAndFilterAttributes(
    int attributeSetId,
    List<Product> loadedProducts,
  ) async {
    try {
      final allAttrs = await _api.fetchAttributesBySet(attributeSetId);
      final relevantAttrs = allAttrs.where((attr) {
        return loadedProducts.any((product) =>
            product.customAttributes.containsKey(attr.code) &&
            product.customAttributes[attr.code] != null);
      }).toList();
      if (mounted) setState(() => _filterAttributes = relevantAttrs);
    } catch (e) {
      debugPrint("Error fetching attributes: $e");
    }
  }

  Future<void> _onRefresh() async {
    if (_subCategories.isNotEmpty) {
      await _enrichSubCategories();
    } else {
      await _fetchProducts(refresh: true);
    }
  }

  void _showFilterDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
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
                          const Text("Filter Products", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          TextButton(
                            onPressed: () {
                              setState(() => _activeFilters.clear());
                              Navigator.pop(context);
                              _fetchProducts(refresh: true);
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
                            title: Text(attr.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                            children: attr.options.map((option) {
                              return RadioListTile<String>(
                                title: Text(option.label),
                                value: option.value,
                                groupValue: _activeFilters[attr.code],
                                activeColor: const Color(0xFF00599c),
                                onChanged: (val) {
                                  setState(() { if (val != null) _activeFilters[attr.code] = val; });
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
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00599c)),
                          onPressed: () {
                            Navigator.pop(context);
                            _fetchProducts(refresh: true);
                          },
                          child: const Text("Apply Filters", style: TextStyle(color: Colors.white)),
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

  void _showSortDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text("Sort By", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
      leading: Icon(isSelected ? Icons.check_circle : Icons.radio_button_unchecked, color: isSelected ? const Color(0xFF00599c) : Colors.grey),
      title: Text(label, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
      onTap: () {
        setState(() { _sortField = field; _sortDirection = dir; _sortLabel = label; });
        Navigator.pop(context);
        _fetchProducts(refresh: true);
      },
    );
  }

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
              IconButton(icon: const Icon(Icons.filter_list), onPressed: _showFilterDialog),
          ],
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        child: hasSubCategories ? _buildSubCategoryGrid() : _buildProductGrid(),
      ),
    );
  }

  Widget _buildSubCategoryGrid() {
    if (_isLoadingSubCats) return BNBShimmer.categoryGrid();

    return GridView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 0.85
      ),
      itemCount: _subCategories.length,
      itemBuilder: (context, index) {
        final cat = _subCategories[index];
        return GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => CategoryDetailScreen(category: cat)),
          ),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                )
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: cat.imageUrl != null
                        ? Image.network(cat.imageUrl!, fit: BoxFit.contain)
                        : Image.asset("assets/icons/placeholder.png"),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12.0, left: 8, right: 8),
                  child: Text(
                    cat.name, 
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF00599c),
                      fontWeight: FontWeight.w600
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildProductGrid() {
    // Show shimmer only on initial load (when list is empty)
    if (_products.isEmpty && _isLoading) return BNBShimmer.productGrid();
    
    // Show empty state
    if (_products.isEmpty && !_isLoading) return const Center(child: Text("No products found"));

    return GridView.builder(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(12),
      // Add one to item count if we have more to load (for the spinner)
      itemCount: _products.length + (_hasMore ? 1 : 0),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3, 
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.65
      ),
      itemBuilder: (context, index) {
        // If we are at the end and have more, show spinner
        if (index == _products.length) {
          return const Center(child: Padding(
            padding: EdgeInsets.all(8.0),
            child: CircularProgressIndicator(strokeWidth: 2),
          ));
        }

        final product = _products[index];
        return GestureDetector(
          onTap: () => Navigator.pushNamed(context, '/productDetail', arguments: product),
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