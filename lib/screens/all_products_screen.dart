// lib/screens/all_products_screen.dart
import 'package:flutter/material.dart';
import '../api/magento_api.dart';
import '../models/magento_models.dart';
import '../widgets/product_card.dart';
import '../widgets/bnb_shimmer.dart'; 

class AllProductsScreen extends StatefulWidget {
  const AllProductsScreen({super.key});

  @override
  State<AllProductsScreen> createState() => _AllProductsScreenState();
}

class _AllProductsScreenState extends State<AllProductsScreen> {
  final MagentoAPI _api = MagentoAPI();
  List<Product> _products = [];
  
  bool _isLoading = false;
  int _currentPage = 1;
  bool _hasMore = true;
  // [FIX] Increased pageSize to 50 for robust scrolling on larger screens
  final int _pageSize = 50; 
  
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
    _fetchProducts();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    // [FIX] Increased threshold to 200
    if (_scrollController.hasClients && 
        _scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoading && _hasMore) {
        _fetchProducts();
      }
    }
  }

  Future<void> _fetchProducts({bool refresh = false}) async {
    if (_isLoading && !refresh) return;
    
    if (refresh) {
      // Don't clear list to avoid flicker
    } else {
      setState(() => _isLoading = true);
    }

    try {
      final int pageToFetch = refresh ? 1 : _currentPage;

      final newProducts = await _api.fetchProducts(
        page: pageToFetch,
        pageSize: _pageSize,
        filters: _activeFilters.isNotEmpty ? _activeFilters : null,
        sortField: _sortField,
        sortDirection: _sortDirection,
        refresh: refresh, 
      );

      if (mounted) {
        setState(() {
          if (refresh) {
            _products = newProducts;
            _currentPage = 2;
            _hasMore = newProducts.length >= _pageSize;
          } else {
            if (newProducts.isEmpty) {
              _hasMore = false;
            } else {
              _products.addAll(newProducts);
              _currentPage++;
              if (newProducts.length < _pageSize) {
                _hasMore = false;
              }
            }
          }
        });

        if (_filterAttributes.isEmpty && _products.isNotEmpty) {
           final attributeSetId = _products.first.attributeSetId;
           if (attributeSetId > 0) {
             _fetchAndFilterAttributes(attributeSetId, _products);
           }
        }
      }
    } catch (e) {
      debugPrint("Error fetching all products: $e");
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
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("All Products", style: TextStyle(color: Color(0xFF00599c))),
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Color(0xFF00599c)),
        elevation: 1,
        actions: [
          IconButton(icon: const Icon(Icons.sort), onPressed: _showSortDialog),
          if (_filterAttributes.isNotEmpty)
            IconButton(icon: const Icon(Icons.filter_list), onPressed: _showFilterDialog),
        ],
      ),
      body: _products.isEmpty && _isLoading
          ? BNBShimmer.productGrid()
          : RefreshIndicator(
              onRefresh: () => _fetchProducts(refresh: true),
              child: GridView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                controller: _scrollController,
                padding: const EdgeInsets.all(8),
                itemCount: _products.length + (_hasMore ? 1 : 0),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 135,
                  crossAxisSpacing: 8, 
                  mainAxisSpacing: 8, 
                  childAspectRatio: 0.65, 
                ),
                itemBuilder: (context, index) {
                  if (index == _products.length) {
                    return const Center(child: Padding(
                      padding: EdgeInsets.all(8.0),
                      child: CircularProgressIndicator(),
                    ));
                  }
                  final product = _products[index];
                  return GestureDetector(
                    onTap: () {
                      Navigator.pushNamed(context, '/productDetail', arguments: product);
                    },
                    child: ProductCard(
                      name: product.name,
                      price: product.price.toStringAsFixed(2),
                      imageUrl: product.imageUrl,
                    ),
                  );
                },
              ),
            ),
    );
  }
}