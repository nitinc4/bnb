// lib/screens/home_screen.dart
import 'package:flutter/material.dart' hide Category; 
import 'package:provider/provider.dart'; 
import '../widgets/product_card.dart';
import '../widgets/app_drawer.dart'; 
import '../widgets/bnb_shimmer.dart'; 
import '../providers/cart_provider.dart'; 
import '../api/magento_api.dart';
import '../models/magento_models.dart';
import 'cart_screen.dart';
import 'profile_screen.dart';
import 'categories_screen.dart';
import 'category_detail_screen.dart';
import 'search_screen.dart'; 
import 'all_products_screen.dart';
import 'support_screen.dart'; 

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  DateTime? _lastPressedAt; 

  void _onItemTapped(int index) {
    setState(() { _selectedIndex = index; });
  }

  Future<bool> _onWillPop() async {
    if (_selectedIndex != 0) {
      setState(() { _selectedIndex = 0; });
      return false; 
    }

    final now = DateTime.now();
    if (_lastPressedAt == null || now.difference(_lastPressedAt!) > const Duration(seconds: 2)) {
      _lastPressedAt = now;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Press back again to exit'), duration: Duration(seconds: 2)),
      );
      return false; 
    }
    return true; 
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      const HomeTab(),
      const CategoriesScreen(),
      const CartScreen(),
      const ProfileScreen(),
      const SupportScreen(isEmbedded: true),
    ];

    return WillPopScope( 
      onWillPop: _onWillPop,
      child: Scaffold(
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
        body: SafeArea(
          child: IndexedStack(
            index: _selectedIndex,
            children: pages,
          ),
        ),
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
            BottomNavigationBarItem(icon: Icon(Icons.support_agent), label: 'Support'),
          ],
        ),
      ),
    );
  }
}

class HomeTab extends StatefulWidget {
  const HomeTab({super.key});
  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> with AutomaticKeepAliveClientMixin {
  List<Category>? _categories;

  @override
  bool get wantKeepAlive => true; 

  @override
  void initState() {
    super.initState();
    // Load from cache initially
    if (MagentoAPI.cachedCategories.isNotEmpty) {
      _categories = MagentoAPI.cachedCategories;
    } else {
      _fetchInitialData();
    }
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<CartProvider>(context, listen: false).fetchCart();
    });
  }

  Future<void> _fetchInitialData() async {
    final cats = await MagentoAPI().fetchCategories();
    if (mounted) setState(() => _categories = cats);
  }

  Future<void> _onRefresh() async {
    // [FIX] Don't clear cache globally. Fetch fresh data and replace.
    final categories = await MagentoAPI().fetchCategories(refresh: true);
    
    // Warm up home products
    final List<Category> allCategories = [];
    for (var cat in categories) {
      allCategories.add(cat);
      allCategories.addAll(cat.children);
    }
    int limit = allCategories.length > 5 ? 5 : allCategories.length;
    List<Future> productTasks = [];
    for (int i = 0; i < limit; i++) {
      productTasks.add(MagentoAPI().fetchProducts(categoryId: allCategories[i].id, pageSize: 10, refresh: true));
    }
    await Future.wait(productTasks);

    if (mounted) setState(() {
      _categories = categories;
    }); 
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); 
    
    return RefreshIndicator(
      onRefresh: _onRefresh,
      color: const Color(0xFF00599c),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchScreen())),
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

            Padding(
              padding: const EdgeInsets.only(left: 16, top: 12, bottom: 8),
              child: Text('Categories', style: TextStyle(color: Colors.grey.shade800, fontWeight: FontWeight.w600, fontSize: 16)),
            ),

            SizedBox(
              height: 170,
              child: _categories == null
                ? BNBShimmer.categoryCircles()
                : ListView.builder(
                    scrollDirection: Axis.horizontal, 
                    itemCount: _categories!.length,
                    itemBuilder: (context, index) {
                      final cat = _categories![index];
                      return InkWell(
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => CategoryDetailScreen(category: cat))),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Column(
                            children: [
                              Container(
                                width: 100, height: 100,
                                decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 5, offset: const Offset(0, 3))]),
                                child: Padding(
                                  padding: const EdgeInsets.all(20.0),
                                  child: cat.imageUrl != null ? Image.network(cat.imageUrl!, fit: BoxFit.contain) : Image.asset("assets/icons/placeholder.png"),
                                ),
                              ),
                              const SizedBox(height: 15),
                              SizedBox(width: 100, child: Text(cat.name, maxLines: 3, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13))),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
            ),

            if (_categories != null)
              Builder(
                builder: (context) {
                  final List<Category> allCategories = [];
                  for (var cat in _categories!) {
                    allCategories.add(cat);
                    allCategories.addAll(cat.children);
                  }
                  return Column(children: allCategories.map((cat) => CategoryProductRow(key: ValueKey(cat.id), category: cat)).toList());
                },
              ),
            
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
              child: SizedBox(
                width: double.infinity, height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00599c), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AllProductsScreen())),
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
  
  void _load() { 
    _productsFuture = MagentoAPI().fetchProducts(categoryId: widget.category.id, pageSize: 10); 
  }

  @override
  Widget build(BuildContext context) {
    final cachedProducts = MagentoAPI.categoryProductsCache[widget.category.id];
    
    return FutureBuilder<List<Product>>(
      future: _productsFuture, 
      initialData: cachedProducts,
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data!.isNotEmpty) {
          final products = snapshot.data!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(widget.category.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF00599c))),
                    TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CategoryDetailScreen(category: widget.category))), child: const Text('See all', style: TextStyle(color: Color(0xFFF54336))))
                  ],
                ),
              ),
              SizedBox(
                height: 260, 
                child: ListView.builder(
                  scrollDirection: Axis.horizontal, itemCount: products.length, padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemBuilder: (context, index) {
                    final product = products[index];
                    return Container(
                      width: 160, margin: const EdgeInsets.only(right: 12, bottom: 5),
                      child: GestureDetector(
                        onTap: () => Navigator.pushNamed(context, '/productDetail', arguments: product),
                        child: ProductCard(name: product.name, price: product.price.toStringAsFixed(2), imageUrl: product.imageUrl),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) return Column(children: [Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Container(width: 120, height: 16, color: Colors.grey.shade200)])), SizedBox(height: 260, child: BNBShimmer.productRow())]);
        return const SizedBox.shrink();
      },
    );
  }
}