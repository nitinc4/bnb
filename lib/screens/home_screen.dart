// lib/screens/home_screen.dart
// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:provider/provider.dart'; 
import '../widgets/product_card.dart';
import '../widgets/app_drawer.dart'; 
import '../providers/cart_provider.dart'; 
import '../api/magento_api.dart';
import '../models/magento_models.dart';
import 'cart_screen.dart';
import 'profile_screen.dart';
import 'categories_screen.dart';
import 'category_detail_screen.dart';
import 'search_screen.dart'; 
import 'all_products_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  
  // Initialize with cached data immediately
  Future<List<Category>> _categoriesFuture = Future.value(MagentoAPI.cachedCategories);
  
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    // If cache is empty (e.g. restart without splash), fetch it.
    if (MagentoAPI.cachedCategories.isEmpty) {
      _categoriesFuture = MagentoAPI().fetchCategories();
    }
  }

  Future<void> _onRefresh() async {
    // 1. Clear Cache
    await MagentoAPI().clearCache();
    
    // 2. Start fetching categories
    final categoriesTask = MagentoAPI().fetchCategories();
    
    setState(() {
      _categoriesFuture = categoriesTask;
    });

    try {
      // 3. Wait for categories to arrive
      final categories = await categoriesTask;

      // 4. Pre-fetch products for the top 5 categories 
      // This ensures the Refresh Indicator stays visible until products are ready,
      // creating a "single loading circle" experience.
      final List<Category> allCategories = [];
      for (var cat in categories) {
        allCategories.add(cat);
        allCategories.addAll(cat.children);
      }

      int limit = allCategories.length > 5 ? 5 : allCategories.length;
      List<Future> productTasks = [];
      
      for (int i = 0; i < limit; i++) {
        productTasks.add(MagentoAPI().fetchProducts(
          categoryId: allCategories[i].id,
          pageSize: 10,
        ));
      }

      await Future.wait(productTasks);
    } catch (e) {
      debugPrint("Refresh Error: $e");
    }
  }

  void _onItemTapped(int index) {
    setState(() { _selectedIndex = index; });
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      KeyedSubtree(key: const ValueKey('homeTab'), child: _buildHomeTab()),
      const CategoriesScreen(key: ValueKey('categoriesTab')), 
      const CartScreen(key: ValueKey('cartTab')), 
      const ProfileScreen(key: ValueKey('profileTab')),
    ];

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Colors.white,
      drawer: const AppDrawer(),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        title: const Text("BuyNutBolts", style: TextStyle(color: Color(0xFF00599c), fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.menu, color: Color(0xFF00599c)),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        actions: [
          Consumer<CartProvider>(
            builder: (_, cart, ch) => Stack(
              children: [
                IconButton(
                  icon: const Icon(Icons.shopping_cart_outlined, color: Color(0xFF00599c)),
                  onPressed: () => setState(() => _selectedIndex = 2),
                ),
                if (cart.itemCount > 0)
                  Positioned(
                    right: 8, top: 8,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(color: Color(0xFFF54336), shape: BoxShape.circle),
                      child: Text('${cart.itemCount}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ),
              ],
            ),
          )
        ],
      ),
      body: SafeArea(child: pages[_selectedIndex]),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        selectedItemColor: const Color(0xFF00599c),
        unselectedItemColor: Colors.grey,
        onTap: _onItemTapped,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.category_outlined), label: 'Categories'),
          BottomNavigationBarItem(icon: Icon(Icons.shopping_cart_outlined), label: 'Cart'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'Profile'),
        ],
      ),
    );
  }

  Widget _buildHomeTab() {
    return RefreshIndicator(
      onRefresh: _onRefresh,
      color: const Color(0xFF00599c),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Search Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: GestureDetector(
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen()));
                },
                child: AbsorbPointer( 
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search for products...',
                      prefixIcon: const Icon(Icons.search, color: Color(0xFF00599c)),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                      filled: true, fillColor: Colors.grey.shade100,
                    ),
                  ),
                ),
              ),
            ),

            // Categories Header
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 12, bottom: 8),
              child: Text('Categories', style: TextStyle(color: Colors.grey.shade800, fontWeight: FontWeight.w600, fontSize: 16)),
            ),

            // Categories List (Circles)
            SizedBox(
              height: 170,
              child: FutureBuilder<List<Category>>(
                future: _categoriesFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  } else if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
                    return const Center(child: Text("No Categories"));
                  }
                  final categories = snapshot.data!;
                  return ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: categories.length,
                    itemBuilder: (context, index) {
                      final cat = categories[index];
                      return InkWell(
                        onTap: () {
                          Navigator.push(context, MaterialPageRoute(builder: (context) => CategoryDetailScreen(category: cat)));
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Column(
                            children: [
                              Container(
                                width: 100, height: 100,
                                decoration: BoxDecoration(
                                  color: Colors.white, shape: BoxShape.circle,
                                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 5, offset: const Offset(0, 3))],
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(20.0),
                                  child: cat.imageUrl != null 
                                      ? Image.network(cat.imageUrl!, fit: BoxFit.contain)
                                      : Image.asset("assets/icons/placeholder.png"),
                                ),
                              ),
                              const SizedBox(height: 15),
                              SizedBox(
                                width: 100,
                                child: Text(cat.name, maxLines: 3, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13)),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),

            // Horizontal Scrollable Products for each Category
            FutureBuilder<List<Category>>(
              future: _categoriesFuture,
              builder: (context, snapshot) {
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const SizedBox.shrink();
                }
                
                final categories = snapshot.data!;
                final List<Category> allCategories = [];
                for (var cat in categories) {
                  allCategories.add(cat);
                  allCategories.addAll(cat.children);
                }

                return Column(
                  children: allCategories.map((cat) => CategoryProductRow(
                    key: ValueKey(cat.id), 
                    category: cat
                  )).toList(),
                );
              },
            ),
            
            // "Show All Products" Button at the End
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00599c),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const AllProductsScreen()));
                  },
                  child: const Text("Show All Products", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
            
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

class CategoryProductRow extends StatefulWidget {
  final Category category;
  const CategoryProductRow({required this.category, super.key});

  @override
  State<CategoryProductRow> createState() => _CategoryProductRowState();
}

class _CategoryProductRowState extends State<CategoryProductRow> {
  late Future<List<Product>> _productsFuture;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(CategoryProductRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.category.id != oldWidget.category.id) {
      _load();
    }
  }

  void _load() {
    // This will hit the memory cache first
    _productsFuture = MagentoAPI().fetchProducts(
      categoryId: widget.category.id,
      pageSize: 10, 
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Product>>(
      future: _productsFuture,
      builder: (context, snapshot) {
        
        // CHANGED: No loading spinner here. 
        // We rely on the parent (RefreshIndicator or Splash) to show loading status.
        // If data is not ready, we show nothing (it will just 'pop' in).
        if (snapshot.connectionState == ConnectionState.waiting) {
           return const SizedBox.shrink();
        }

        // Hide if error or no products
        if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
          return const SizedBox.shrink();
        }

        final products = snapshot.data!;
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    widget.category.name,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF00599c)),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => CategoryDetailScreen(category: widget.category)));
                    },
                    child: const Text('See all', style: TextStyle(color: Color(0xFFF54336))),
                  )
                ],
              ),
            ),
            
            // Horizontal Product List
            SizedBox(
              height: 260, 
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: products.length,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemBuilder: (context, index) {
                  final product = products[index];
                  return Container(
                    width: 160, 
                    margin: const EdgeInsets.only(right: 12, bottom: 5),
                    child: GestureDetector(
                      onTap: () {
                        Navigator.pushNamed(context, '/productDetail', arguments: product);
                      },
                      child: ProductCard(
                        name: product.name,
                        price: product.price.toStringAsFixed(2),
                        imageUrl: product.imageUrl,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}