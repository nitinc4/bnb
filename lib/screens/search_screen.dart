// lib/screens/search_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../api/magento_api.dart';
import '../models/magento_models.dart';
import '../widgets/product_card.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final MagentoAPI _api = MagentoAPI();
  
  List<Product> _suggestions = [];
  List<Product> _results = [];
  
  bool _isLoading = false;
  bool _isSubmitted = false;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    
    // Clear suggestions if empty
    if (query.trim().isEmpty) {
      setState(() {
        _suggestions = [];
        _isSubmitted = false;
      });
      return;
    }

    // Debounce to avoid API spam 
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      final suggestions = await _api.getSearchSuggestions(query);
      if (mounted) {
        setState(() {
          _suggestions = suggestions;
          _isSubmitted = false; // Show suggestions list, not grid
        });
      }
    });
  }

  Future<void> _performFullSearch(String query) async {
    if (query.trim().isEmpty) return;
    _debounce?.cancel();

    setState(() {
      _isLoading = true;
      _isSubmitted = true;
    });

    final results = await _api.searchProducts(query);

    if (mounted) {
      setState(() {
        _results = results;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF00599c)),
        title: TextField(
          controller: _searchController,
          autofocus: true,
          decoration: InputDecoration(
            hintText: "Search Name or SKU...",
            border: InputBorder.none,
            hintStyle: TextStyle(color: Colors.grey.shade400),
          ),
          textInputAction: TextInputAction.search,
          onChanged: _onSearchChanged,
          onSubmitted: _performFullSearch,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => _performFullSearch(_searchController.text),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF00599c)));
    }

    // Show Suggestions 
    if (!_isSubmitted && _suggestions.isNotEmpty) {
      return ListView.builder(
        itemCount: _suggestions.length,
        itemBuilder: (context, index) {
          final product = _suggestions[index];
          return ListTile(
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: CachedNetworkImage(
                imageUrl: product.imageUrl,
                width: 40, height: 40, fit: BoxFit.cover,
                placeholder: (_, __) => Container(color: Colors.grey.shade200),
                errorWidget: (_, __, ___) => const Icon(Icons.broken_image, size: 20),
              ),
            ),
            title: Text(product.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(product.sku, style: const TextStyle(fontSize: 12)),
            onTap: () {
              Navigator.pushNamed(context, '/productDetail', arguments: product);
            },
          );
        },
      );
    }

    // Show Full Results (Grid)
    if (_isSubmitted) {
      if (_results.isEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.search_off, size: 64, color: Colors.grey.shade300),
              const SizedBox(height: 16),
              const Text("No products found", style: TextStyle(fontSize: 16, color: Colors.grey)),
            ],
          ),
        );
      }
      return GridView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _results.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 0.7,
        ),
        itemBuilder: (context, index) {
          final product = _results[index];
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

    return Center(child: Text("Type to search...", style: TextStyle(color: Colors.grey.shade400)));
  }
}