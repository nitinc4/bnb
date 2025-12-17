// lib/screens/all_products_screen.dart
import 'package:flutter/material.dart';
import '../api/magento_api.dart';
import '../models/magento_models.dart';
import '../widgets/product_card.dart';
import 'product_detail_screen.dart';

class AllProductsScreen extends StatefulWidget {
  const AllProductsScreen({super.key});

  @override
  State<AllProductsScreen> createState() => _AllProductsScreenState();
}

class _AllProductsScreenState extends State<AllProductsScreen> {
  final List<Product> _products = [];
  bool _isLoading = false;
  bool _hasMore = true;
  int _page = 1;
  final ScrollController _scrollController = ScrollController();
  
  // Filter & Sort State
  final MagentoAPI _api = MagentoAPI();
  List<ProductAttribute> _filterAttributes = [];
  final Map<String, dynamic> _activeFilters = {};
  
  // Sorting State
  String? _sortField; 
  String? _sortDirection; 
  String _sortLabel = 'Relevance'; 

  @override
  void initState() {
    super.initState();
    _fetchGlobalAttributes();
    _fetchProducts();
    _scrollController.addListener(_onScroll);
  }

  Future<void> _fetchGlobalAttributes() async {
    final attrs = await _api.fetchGlobalFilterableAttributes();
    if (mounted) {
      setState(() {
        _filterAttributes = attrs;
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      _fetchProducts();
    }
  }

  Future<void> _fetchProducts() async {
    if (_isLoading || !_hasMore) return;

    setState(() {
      _isLoading = true;
    });

    final newProducts = await _api.fetchProducts(
      page: _page, 
      filters: _activeFilters.isNotEmpty ? _activeFilters : null,
      sortField: _sortField,
      sortDirection: _sortDirection,
    );

    if (mounted) {
      setState(() {
        if (newProducts.isEmpty) {
          _hasMore = false;
        } else {
          _products.addAll(newProducts);
          _page++;
        }
        _isLoading = false;
      });
    }
  }

  void _resetAndFetch() {
    setState(() {
      _products.clear();
      _page = 1;
      _hasMore = true;
    });
    _fetchProducts();
  }

  void _applyFilters() {
    _resetAndFetch();
    Navigator.pop(context);
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
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("Filter Products", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          TextButton(
                            onPressed: () {
                              setState(() => _activeFilters.clear());
                              setModalState((){});
                            },
                            child: const Text("Clear All"),
                          )
                        ],
                      ),
                    ),
                    Expanded(
                      child: _filterAttributes.isEmpty 
                      ? const Center(child: Text("No filters available"))
                      : ListView.builder(
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
                                onChanged: (val) {
                                  setState(() {
                                    if (val != null) _activeFilters[attr.code] = val;
                                  });
                                  setModalState(() {});
                                },
                                activeColor: const Color(0xFF00599c),
                              );
                            }).toList(),
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00599c)),
                          onPressed: _applyFilters,
                          child: const Text("Apply Filters", style: TextStyle(color: Colors.white)),
                        ),
                      ),
                    )
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
              padding: EdgeInsets.all(16.0),
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
    bool isSelected = _sortLabel == label;
    return ListTile(
      leading: Icon(isSelected ? Icons.check_circle : Icons.radio_button_unchecked, color: isSelected ? const Color(0xFF00599c) : Colors.grey),
      title: Text(label, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
      onTap: () {
        setState(() {
          _sortField = field;
          _sortDirection = dir;
          _sortLabel = label;
        });
        Navigator.pop(context); 
        _resetAndFetch(); 
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("All Products", style: TextStyle(color: Color(0xFF00599c), fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF00599c)),
        actions: [
           IconButton(
             icon: const Icon(Icons.sort),
             onPressed: _showSortDialog,
             tooltip: "Sort",
           ),
           IconButton(
              icon: Stack(
                children: [
                  const Icon(Icons.filter_list),
                  if (_activeFilters.isNotEmpty)
                    Positioned(
                      right: 0, top: 0,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                        constraints: const BoxConstraints(minWidth: 8, minHeight: 8),
                      ),
                    )
                ],
              ),
              onPressed: _showFilterDialog,
              tooltip: "Filter",
            )
        ],
      ),
      body: _products.isEmpty && _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00599c)))
          : GridView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _products.length + (_hasMore ? 1 : 0),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.7,
              ),
              itemBuilder: (context, index) {
                if (index == _products.length) {
                  return const Center(
                    child: CircularProgressIndicator(color: Color(0xFF00599c)),
                  );
                }
                
                final product = _products[index];
                return GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => ProductDetailScreen(product: product)),
                    );
                  },
                  child: ProductCard(
                    name: product.name,
                    price: product.price.toStringAsFixed(2),
                    imageUrl: product.imageUrl,
                  ),
                );
              },
            ),
    );
  }
}