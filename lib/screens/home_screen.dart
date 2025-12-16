// lib/screens/home_screen.dart
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
import 'search_screen.dart'; // Import SearchScreen

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  
  late Future<List<Category>> _categoriesFuture;
  late Future<List<Product>> _productsFuture;
  
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    final api = MagentoAPI();
    _categoriesFuture = api.fetchCategories();
    _productsFuture = api.fetchProducts();
  }

  Future<void> _onRefresh() async {
    await MagentoAPI().clearCache();
    setState(() {
      _loadData();
    });
    await Future.wait([_categoriesFuture, _productsFuture]);
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
        title: const Text("BNB Store", style: TextStyle(color: Color(0xFF00599c), fontWeight: FontWeight.bold)),
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
                child: AbsorbPointer( // Prevents keyboard from opening here
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

            // Categories List
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

            // Featured Products Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Featured Products', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF00599c))),
                  TextButton(
                    onPressed: () => setState(() => _selectedIndex = 1),
                    child: const Text('See all', style: TextStyle(color: Color(0xFFF54336))),
                  )
                ],
              ),
            ),

            // Products Grid
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: FutureBuilder<List<Product>>(
                future: _productsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  } else if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
                    return const Center(child: Text("No Products Found"));
                  }
                  final products = snapshot.data!;
                  return GridView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    shrinkWrap: true,
                    itemCount: products.length,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 0.7,
                    ),
                    itemBuilder: (context, index) {
                      final product = products[index];
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
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}