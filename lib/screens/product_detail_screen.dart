// lib/screens/product_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../models/magento_models.dart';
import '../providers/cart_provider.dart';
import '../api/magento_api.dart';
import 'website_webview_screen.dart'; 
import 'search_screen.dart'; 

class ProductDetailScreen extends StatefulWidget {
  final Product product;
  const ProductDetailScreen({super.key, required this.product});

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  late Product _currentProduct;
  bool _isLoadingDetails = false;
  
  Map<String, String> _specs = {};
  bool _isLoadingSpecs = false;

  final TextEditingController _qtyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _currentProduct = widget.product;
    _fetchFullDetails();
  }

  @override
  void dispose() {
    _qtyController.dispose();
    super.dispose();
  }

  Future<void> _fetchFullDetails() async {
    setState(() => _isLoadingDetails = true);
    final api = MagentoAPI();
    
    final fullProduct = await api.fetchProductBySku(_currentProduct.sku);
    final tierPrices = await api.fetchTierPrices(_currentProduct.sku);

    if (mounted) {
      setState(() {
        List<TierPrice> finalTiers = [];

        if (tierPrices.isNotEmpty) {
          finalTiers = tierPrices;
        } else if (fullProduct != null && fullProduct.tierPrices.isNotEmpty) {
          finalTiers = fullProduct.tierPrices;
        } else {
          finalTiers = _currentProduct.tierPrices;
        }

        if (fullProduct != null) {
          _currentProduct = fullProduct.copyWith(tierPrices: finalTiers);
        } else {
          _currentProduct = _currentProduct.copyWith(tierPrices: finalTiers);
        }
        
        _isLoadingDetails = false;
      });
      
      api.updateProductCache(_currentProduct);

      if (_currentProduct.attributeSetId > 0) {
        _fetchSpecifications(api, _currentProduct.attributeSetId);
      }
    }
  }

  Future<void> _fetchSpecifications(MagentoAPI api, int attributeSetId) async {
    setState(() => _isLoadingSpecs = true);
    
    final attributes = await api.fetchAttributesBySet(attributeSetId);
    
    Map<String, String> newSpecs = {};
    
    _currentProduct.customAttributes.forEach((code, value) {
      try {
        final attrDef = attributes.firstWhere((a) => a.code == code);
        
        String displayValue = value.toString();
        
        if (attrDef.frontendInput == 'select') {
          final option = attrDef.options.firstWhere(
            (o) => o.value == value.toString(), 
            orElse: () => AttributeOption(label: value.toString(), value: value.toString())
          );
          displayValue = option.label;
        } else if (attrDef.frontendInput == 'boolean') {
           displayValue = (value == '1' || value == 1) ? "Yes" : "No";
        }
        
        newSpecs[attrDef.label] = displayValue;
      } catch (e) {
      }
    });

    if (mounted) {
      setState(() {
        _specs = newSpecs;
        _isLoadingSpecs = false;
      });
    }
  }

  Future<void> _onRefresh() async {
    await _fetchFullDetails();
  }

  void _openRFQ() {
    final String rfqUrl = "https://rfq.buynutbolts.com/rfq.php"
        "?sku=${Uri.encodeComponent(_currentProduct.sku)}"
        "&name=${Uri.encodeComponent(_currentProduct.name)}"
        "&part=${Uri.encodeComponent(_currentProduct.sku)}"
        "&qty=1"
        "&url=${Uri.encodeComponent('https://buynutbolts.com')}";

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => WebsiteWebViewScreen(
          url: rfqUrl,
          title: "Request Quote",
        ),
      ),
    );
  }

  void _confirmRemove(BuildContext context, CartProvider cart, CartItem item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Remove Item"),
        content: Text("Remove ${_currentProduct.name} from cart?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              cart.removeFromCart(item);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text("Remove"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: true, 
      appBar: AppBar(
        title: Text(_currentProduct.name, style: const TextStyle(fontSize: 16)),
        actions: [
          Consumer<CartProvider>(
            builder: (_, cart, ch) => Stack(
              children: [
                IconButton(
                  icon: const Icon(Icons.shopping_cart_outlined),
                  onPressed: () => Navigator.pushNamed(context, '/cart'),
                ),
                if (cart.itemCount > 0)
                  Positioned(right: 8, top: 8, child: Container(padding: const EdgeInsets.all(4), decoration: const BoxDecoration(color: Color(0xFFF54336), shape: BoxShape.circle), child: Text('${cart.itemCount}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)))),
              ],
            ),
          )
        ],
      ),
      body: Column(
        children: [
          // Scrollable Content
          Expanded(
            child: RefreshIndicator(
              onRefresh: _onRefresh,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Search Bar added here
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

                    SizedBox(
                      height: 300, width: double.infinity,
                      child: _currentProduct.imageUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: _currentProduct.imageUrl,
                            fit: BoxFit.contain,
                            placeholder: (context, url) => Container(color: Colors.grey.shade100),
                            errorWidget: (context, url, error) => const Icon(Icons.broken_image),
                          )
                        : Container(color: Colors.grey.shade100, child: const Icon(Icons.image, size: 50, color: Colors.grey)),
                    ),
      
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_currentProduct.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Text("SKU: ${_currentProduct.sku}", style: TextStyle(color: Colors.grey.shade600)),
                          
                          const SizedBox(height: 16),
                          const Divider(),
                          const SizedBox(height: 16),
      
                          const Text("Description", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 8),
                          if (_isLoadingDetails) 
                            const LinearProgressIndicator(color: Color(0xFF00599c))
                          else
                            Text(_currentProduct.description.isNotEmpty ? _currentProduct.description : "No description available.", style: const TextStyle(color: Colors.black54, height: 1.5)),
      
                          const SizedBox(height: 24),
                          const Divider(),
                          const SizedBox(height: 16),
      
                          if (_currentProduct.tierPrices.isNotEmpty) ...[
                            const Text("Buy More, Save More", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF00599c))),
                            const SizedBox(height: 8),
                            Container(
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade300),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                                    color: Colors.grey.shade100,
                                    child: const Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text("Quantity", style: TextStyle(fontWeight: FontWeight.bold)),
                                        Text("Price Per Item", style: TextStyle(fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                  ),
                                  const Divider(height: 1),
                                  ..._currentProduct.tierPrices.map((tier) {
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text("Buy ${tier.qty}+"),
                                          Text("₹${tier.price.toStringAsFixed(2)}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                                        ],
                                      ),
                                    );
                                  }),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],
      
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _openRFQ,
                              icon: const Icon(Icons.request_quote, color: Color(0xFF00599c)),
                              label: const Text("Request for Quote (Bulk Order)", style: TextStyle(color: Color(0xFF00599c), fontWeight: FontWeight.bold)),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                side: const BorderSide(color: Color(0xFF00599c)),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ),
                          
                          const SizedBox(height: 24),
                          const Divider(),
                          const SizedBox(height: 16),
      
                          const Text("More Information", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 8),
                          if (_isLoadingSpecs)
                            const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator()))
                          else if (_specs.isNotEmpty)
                            Table(
                              border: TableBorder.all(color: Colors.grey.shade200),
                              columnWidths: const {0: FlexColumnWidth(1), 1: FlexColumnWidth(1.5)},
                              children: _specs.entries.map((entry) {
                                return TableRow(
                                  decoration: BoxDecoration(color: Colors.white),
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.all(10),
                                      child: Text(entry.key, style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.w500)),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(10),
                                      child: Text(entry.value, style: const TextStyle(fontWeight: FontWeight.w500)),
                                    ),
                                  ],
                                );
                              }).toList(),
                            )
                          else 
                            const Text("No additional specifications available.", style: TextStyle(color: Colors.grey)),
      
                          const SizedBox(height: 80), 
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          // Bottom Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
            decoration: BoxDecoration(
              color: Colors.white, 
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: const Offset(0, -2))]
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Price", style: TextStyle(fontSize: 12, color: Colors.grey)),
                        Text("₹${_currentProduct.price.toStringAsFixed(2)}", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF00599c))),
                      ],
                    ),
                  ),
                  
                  Expanded(
                    flex: 3,
                    child: Consumer<CartProvider>(
                      builder: (context, cart, child) {
                        final cartItemIndex = cart.items.indexWhere((i) => i.sku == _currentProduct.sku);
                        final isInCart = cartItemIndex >= 0;
                        final qty = isInCart ? cart.items[cartItemIndex].qty : 0;
                        
                        // Sync controller if needed
                        if (isInCart && !_qtyController.selection.isValid) {
                          _qtyController.text = qty.toString();
                        }

                        if (!isInCart) {
                          return ElevatedButton(
                            onPressed: () {
                              cart.addToCart(_currentProduct);
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${_currentProduct.name} added to cart!"), duration: const Duration(seconds: 1)));
                            },
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00599c), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                            child: const Text("Add to Cart", style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold)),
                          );
                        } else {
                          return Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(color: const Color(0xFF00599c), borderRadius: BorderRadius.circular(12)),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                InkWell(
                                  onTap: () {
                                    if (qty > 1) {
                                      cart.updateQty(cart.items[cartItemIndex], qty - 1);
                                    } else {
                                      _confirmRemove(context, cart, cart.items[cartItemIndex]);
                                    }
                                  },
                                  child: const Icon(Icons.remove, color: Colors.white),
                                ),
                                
                                SizedBox(
                                  width: 50,
                                  child: TextField(
                                    controller: _qtyController,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      border: InputBorder.none,
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                    onSubmitted: (val) {
                                      int? newQty = int.tryParse(val);
                                      if (newQty != null) {
                                        if (newQty <= 0) {
                                          _confirmRemove(context, cart, cart.items[cartItemIndex]);
                                        } else {
                                          cart.updateQty(cart.items[cartItemIndex], newQty);
                                        }
                                      } else {
                                        _qtyController.text = qty.toString();
                                      }
                                    },
                                  ),
                                ),

                                InkWell(
                                  onTap: () {
                                    cart.updateQty(cart.items[cartItemIndex], qty + 1);
                                  },
                                  child: const Icon(Icons.add, color: Colors.white),
                                ),
                              ],
                            ),
                          );
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}