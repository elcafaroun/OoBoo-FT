import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/category_service.dart';
import '../services/product_service.dart';
import '../providers/cart_provider.dart';
import '../utils/constants.dart';
import 'cart_screen.dart';
import 'orders_screen.dart';

class CategoriesScreen extends StatefulWidget {
  final String structureId;
  final String structureName;

  const CategoriesScreen({super.key, required this.structureId, required this.structureName});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  final CategoryService _categoryService = CategoryService();
  final ProductService _productService = ProductService();
  final TextEditingController _searchController = TextEditingController();

  List<dynamic> categories = [];
  List<dynamic> allProducts = [];
  List<dynamic> filteredProducts = [];

  String selectedCategoryId = "TOUS";
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => isLoading = true);
    try {
      final cats = await _categoryService.getCategoriesByStructure(widget.structureId);
      final prods = await _productService.getProductsByStructure(widget.structureId);

      // Filtrage : On ne garde que les éléments où 'active' ou 'isActive' est true
      // Si le champ est null, on considère qu'il est true (actif) par défaut
      final activeCategories = (cats as List).where((c) {
        final status = c['active'] ?? c['isActive'] ?? true;
        return status == true;
      }).toList();

      final activeProducts = (prods as List).where((p) {
        final status = p['active'] ?? p['isActive'] ?? true;
        return status == true;
      }).toList();

      setState(() {
        categories = activeCategories;
        allProducts = activeProducts;
        filteredProducts = activeProducts; // Initialisation de la vue filtrée
        isLoading = false;
      });
    } catch (e) {
      setState(() => isLoading = false);
      debugPrint("Erreur chargement : $e");
    }
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      filteredProducts = allProducts.where((p) {
        final matchesQuery = p['productName'].toString().toLowerCase().contains(query);
        final matchesCategory = (selectedCategoryId == "TOUS") ||
            (p['categoryId']?.toString() == selectedCategoryId);
        return matchesQuery && matchesCategory;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F7F2), // Fond crème léger
      appBar: AppBar(
        title: Text(widget.structureName, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          IconButton(
            icon: const Icon(Icons.receipt_long_outlined),
            tooltip: "Mes factures",
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OrdersScreen())),
          ),
          _buildCartBadge(),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          _buildCategoryList(),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator(color: Colors.orange))
                : _buildProductGrid(),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: "Rechercher un produit...",
          prefixIcon: const Icon(Icons.search, color: Colors.grey),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide(color: Colors.grey.shade200)),
        ),
      ),
    );
  }

  Widget _buildCategoryList() {
    return SizedBox(
      height: 110,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        itemCount: categories.length + 1,
        itemBuilder: (context, index) {
          final isAll = index == 0;
          final String catId = isAll ? "TOUS" : categories[index - 1]['id'].toString();
          final String catName = isAll ? "Tout" : categories[index - 1]['nameCat'];
          final String? catPhoto = isAll ? null : categories[index - 1]['photoCat'];
          final isSelected = selectedCategoryId == catId;

          return GestureDetector(
            onTap: () {
              setState(() => selectedCategoryId = catId);
              _onSearchChanged();
            },
            child: Container(
              width: 75,
              margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: Column(
                children: [
                  Container(
                    height: 60, width: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSelected ? Colors.orange : Colors.white,
                      border: Border.all(color: isSelected ? Colors.orange : Colors.grey.shade200, width: 2),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6, offset: const Offset(0, 3))],
                    ),
                    child: Center(
                      child: isAll
                          ? Icon(Icons.apps, color: isSelected ? Colors.white : Colors.grey)
                          : ClipOval(
                        child: Image.network("$baseUrl/category/image/$catPhoto", fit: BoxFit.cover, width: 60, height: 60,
                            errorBuilder: (_, __, ___) => const Icon(Icons.category, color: Colors.orange)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(catName, style: TextStyle(fontSize: 11, fontWeight: isSelected ? FontWeight.bold : FontWeight.w500), textAlign: TextAlign.center, maxLines: 1),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildProductGrid() {
    if (filteredProducts.isEmpty) return const Center(child: Text("Aucun produit trouvé", style: TextStyle(color: Colors.grey)));

    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: 0.75, crossAxisSpacing: 16, mainAxisSpacing: 16),
      itemCount: filteredProducts.length,
      itemBuilder: (context, index) {
        final p = filteredProducts[index];
        final String imageUrl = p['photo'] ?? p['productPhotoUrl'] ?? '';

        return GestureDetector(
          onTap: () => _showFullDetails(p, imageUrl),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                    child: Image.network(imageUrl, fit: BoxFit.cover, width: double.infinity,
                        errorBuilder: (_, __, ___) => Container(color: Colors.grey[50], child: const Icon(Icons.image_outlined, color: Colors.grey))),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p['productName'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Text("${p['productPrice']} FCFA", style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.w900, fontSize: 14)),
                    ],
                  ),
                )
              ],
            ),
          ),
        );
      },
    );
  }

  void _showFullDetails(dynamic p, String imageUrl) {
    int quantity = 1;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(builder: (context, setModalState) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
          child: Column(
            children: [
              Stack(
                children: [
                  ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                      child: Image.network(imageUrl, height: 300, width: double.infinity, fit: BoxFit.cover)),
                  Positioned(top: 20, right: 20, child: IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.white, size: 30))),
                ],
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(25),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(child: Text(p['productName'] ?? '', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold))),
                        Text("${p['productPrice']} FCFA", style: const TextStyle(fontSize: 20, color: Colors.orange, fontWeight: FontWeight.w900)),
                      ]),
                      const SizedBox(height: 20),
                      Text(p['productDescription'] ?? "Pas de description.", style: TextStyle(color: Colors.grey[600], height: 1.5)),
                      const Spacer(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: () => quantity > 1 ? setModalState(() => quantity--) : null),
                          Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Text("$quantity", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold))),
                          IconButton(icon: const Icon(Icons.add_circle_outline, color: Colors.orange), onPressed: () => setModalState(() => quantity++)),
                        ],
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 55,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange, // <-- Bouton Orange
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
                          ),
                          onPressed: () {
                            Provider.of<CartProvider>(context, listen: false).addItem(p['id'].toString(), p['productName'], (p['productPrice'] as num).toDouble(), imageUrl, quantity);
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Ajouté au panier !"), backgroundColor: Colors.orange));
                          },
                          child: const Text("AJOUTER AU PANIER", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildCartBadge() {
    return Consumer<CartProvider>(
      builder: (context, cart, _) => Badge(
        label: Text("${cart.items.length}"),
        isLabelVisible: cart.items.isNotEmpty,
        backgroundColor: Colors.orange,
        child: IconButton(icon: const Icon(Icons.shopping_cart_outlined), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CartScreen()))),
      ),
    );
  }
}