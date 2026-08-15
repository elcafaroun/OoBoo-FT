import 'package:fada/screens/notifications_screen.dart';
import 'package:fada/screens/scanner_screen.dart';
import 'package:fada/services/network_checker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/category_service.dart';
import '../services/product_service.dart';
import '../services/database/database_helper.dart';
import '../providers/cart_provider.dart';
import '../utils/constants.dart';
import 'cart_screen.dart';
import 'orders_screen.dart';
import 'package:collection/collection.dart';
import '../widgets/product_image_widget.dart';

class CategoriesScreen extends StatefulWidget {
  final String structureId;
  final String structureName;
  const CategoriesScreen({super.key, required this.structureId, required this.structureName});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  int _alertCount = 0;

  final CategoryService _categoryService = CategoryService();
  final ProductService _productService = ProductService();
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final TextEditingController _searchController = TextEditingController();

  List<dynamic> categories = [];
  List<dynamic> allProducts = [];
  List<dynamic> filteredProducts = [];

  String selectedCategoryId = "TOUS";
  bool isLoading = true;
  String? userProfile;

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
    final prefs = await SharedPreferences.getInstance();
    userProfile = prefs.getString('userProfile');
    final String profileLower = userProfile?.toLowerCase() ?? '';
    bool isAdminOrSuperAdmin = profileLower.contains("admin") || profileLower.contains("super_admin") || profileLower.contains("super admin");

    if (isAdminOrSuperAdmin) {
      debugPrint("👑 Profil Admin/Super Admin : Vérification de la connexion requise.");

      bool isOnline = false;
      try {
        isOnline = await NetworkChecker.isBackendAccessible();
      } catch (e) {
        debugPrint("❌ Erreur de vérification réseau : $e");
      }

      if (!isOnline) {
        if (mounted) {
          setState(() {
            isLoading = false;
            categories = [];
            allProducts = [];
            filteredProducts = [];
            _alertCount = 0;
          });
        }
        return;
      }

      try {
        final remoteCats = await _categoryService.getCategoriesByStructure(widget.structureId);
        final remoteProds = await _productService.getProductsByStructure(widget.structureId);

        // Pour les admins en ligne, on peut synchroniser temporairement ou calculer directement sur les produits distants
        // Si _dbHelper gère l'enregistrement, ou si vous préférez utiliser getProductsInAlert après sync :
        await _dbHelper.syncCategoriesLocal(remoteCats);
        await _dbHelper.syncProductsLocal(remoteProds);
        final adminAlerts = await _dbHelper.getProductsInAlert(widget.structureId);

        if (mounted) {
          setState(() {
            categories = remoteCats;
            allProducts = remoteProds;
            filteredProducts = remoteProds;
            _alertCount = adminAlerts.length;
            isLoading = false;
          });
        }
        return;
      } catch (e) {
        debugPrint("❌ Erreur chargement online admin/super admin : $e");
        if (mounted) {
          setState(() {
            isLoading = false;
            categories = [];
            allProducts = [];
            filteredProducts = [];
            _alertCount = 0;
          });
        }
        return;
      }
    }

    // Comportement standard (Non-admin) : Chargement local d'abord puis tentative de synchro
    final localCats = await _dbHelper.getCategoriesByStructureLocal(widget.structureId);
    final localProds = await _dbHelper.getProductsByStructureLocal(widget.structureId);
    final localAlerts = await _dbHelper.getProductsInAlert(widget.structureId);

    if (mounted) {
      setState(() {
        categories = localCats;
        allProducts = localProds;
        filteredProducts = localProds;
        _alertCount = localAlerts.length;
        isLoading = false;
      });
    }

    if (await NetworkChecker.isBackendAccessible()) {
      try {
        final remoteCats = await _categoryService.getCategoriesByStructure(widget.structureId);
        final remoteProds = await _productService.getProductsByStructure(widget.structureId);
        await _dbHelper.syncCategoriesLocal(remoteCats);
        await _dbHelper.syncProductsLocal(remoteProds);

        final updatedCats = await _dbHelper.getCategoriesByStructureLocal(widget.structureId);
        final updatedProds = await _dbHelper.getProductsByStructureLocal(widget.structureId);
        final updatedAlerts = await _dbHelper.getProductsInAlert(widget.structureId);

        if (mounted && updatedCats.isNotEmpty) {
          setState(() {
            categories = updatedCats;
            allProducts = updatedProds;
            _alertCount = updatedAlerts.length;
            _onSearchChanged();
          });
        }
      } catch (e) {
        debugPrint("Erreur synchro : $e");
      }
    }
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      filteredProducts = allProducts.where((p) {
        final matchesQuery = p['productName'].toString().toLowerCase().contains(query);
        final matchesCategory = (selectedCategoryId == "TOUS") || (p['categoryId']?.toString() == selectedCategoryId);
        return matchesQuery && matchesCategory;
      }).toList();
    });
  }

  Future<void> _scanAndFindProduct() async {
    final String? codeScanne = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const ScannerScreen()),
    );

    if (codeScanne != null && codeScanne.isNotEmpty) {
      final String cleanCode = codeScanne.toLowerCase().trim();
      final product = allProducts.firstWhereOrNull((p) => p['productQrCode']?.toString().toLowerCase().trim() == cleanCode);

      if (product != null) {
        final String imageUrl = product['photo'] ?? product['productPhotoUrl'] ?? '';
        Provider.of<CartProvider>(context, listen: false).addItem(product['id'].toString(), product['productName'], (product['productPrice'] as num).toDouble(), imageUrl, 1);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Ajouté : ${product['productName']}"), backgroundColor: Colors.green, behavior: SnackBarBehavior.floating));
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Aucun produit trouvé."), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating));
      }
    }
  }

  Widget _buildActionButton(IconData icon, VoidCallback onPressed) {
    return IconButton(
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      icon: Icon(icon, size: 28),
      color: Colors.black,
      onPressed: onPressed,
    );
  }

  @override
  Widget build(BuildContext context) {
    final String profileLower = userProfile?.toLowerCase() ?? '';
    bool isAdminOrSuperAdmin = profileLower.contains("admin") || profileLower.contains("super_admin") || profileLower.contains("super admin");

    bool isOfflineAdmin = isAdminOrSuperAdmin && !isLoading && categories.isEmpty && allProducts.isEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFF9F7F2),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Color(0xFF1E293B)),
        title: const Text(
          "Articles",
          style: TextStyle(
            color: Color(0xFF1E293B),
            fontWeight: FontWeight.bold,
            letterSpacing: 0.3,
          ),
        ),
        actions: isOfflineAdmin
            ? null
            : [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildActionButton(Icons.qr_code_scanner, _scanAndFindProduct),
                const SizedBox(width: 16),
                _buildActionButton(Icons.receipt_long_outlined, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OrdersScreen()))),
                const SizedBox(width: 16),
                _buildCartBadge(),
                const SizedBox(width: 16),
                IconButton(
                  icon: const Icon(Icons.home_rounded, color: Color(0xFFFF9800), size: 26),
                  onPressed: () => Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const OrdersScreen()),
                        (r) => false,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: isLoading
            ? const Center(child: CircularProgressIndicator(color: Colors.orange))
            : isOfflineAdmin
            ? Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: Colors.grey.shade100, shape: BoxShape.circle),
                  child: Icon(Icons.cloud_off_rounded, size: 64, color: Colors.grey.shade400),
                ),
                const SizedBox(height: 24),
                const Text("Connexion requise", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                const SizedBox(height: 8),
                const Text("En tant qu'administrateur, veuillez vérifier votre connexion internet pour accéder à cet espace.", textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF64748B), fontSize: 14, height: 1.4)),
                const SizedBox(height: 24),
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      isLoading = true;
                    });
                    _loadData();
                  },
                  icon: const Icon(Icons.refresh_rounded, color: Color(0xFFFF9800)),
                  label: const Text("Réessayer", style: TextStyle(color: Color(0xFFFF9800), fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        )
            : Column(
          children: [
            _buildStructureHeader(),
            _buildSearchBar(),
            _buildCategoryList(),
            Expanded(
              child: _buildProductGrid(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStructureHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      width: double.infinity,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.orange.withOpacity(0.2)),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 5, offset: const Offset(0, 2))
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.storefront, color: Colors.orange, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.structureName,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: Badge(
                isLabelVisible: _alertCount > 0,
                label: Text("$_alertCount"),
                backgroundColor: Colors.red,
                child: const Icon(Icons.notifications_outlined, color: Colors.black54, size: 22),
              ),
              onPressed: () {
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => NotificationsScreen(structureId: widget.structureId)
                    )
                );
              },
            ),
            const SizedBox(width: 15),
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: const Icon(Icons.chat_bubble_outline, color: Colors.black54, size: 22),
              onPressed: () {},
            ),
          ],
        ),
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
          filled: true, fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
        ),
      ),
    );
  }

  Widget _buildCategoryList() {
    return SizedBox(
      height: 110,
      child: ListView.builder(
        key: const ValueKey("category_list_view"),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        itemCount: categories.length + 1,
        itemBuilder: (context, index) {
          final isAll = index == 0;
          final catId = isAll ? "TOUS" : categories[index - 1]['id'].toString();
          final isSelected = selectedCategoryId == catId;
          String networkUrl = "";
          if (!isAll) {
            final photoCat = categories[index - 1]['photoCat'];
            if (photoCat != null && photoCat.toString() != "null" && photoCat.toString().isNotEmpty) {
              networkUrl = "$baseUrl/category/image/$photoCat";
            }
          }

          return GestureDetector(
            onTap: () { setState(() => selectedCategoryId = catId); _onSearchChanged(); },
            child: Container(
              width: 75,
              margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: Column(
                children: [
                  Container(
                    height: 60, width: 60,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: isSelected ? Colors.orange : Colors.white, border: Border.all(color: isSelected ? Colors.orange : Colors.grey.shade200, width: 2)),
                    child: Center(
                      child: isAll
                          ? Icon(Icons.apps, color: isSelected ? Colors.white : Colors.grey)
                          : ClipOval(
                        child: ProductImageWidget(
                          key: ValueKey("cat_${categories[index - 1]['id']}_${categories[index - 1]['photoPath'] ?? 'no_path'}"),
                          localPath: categories[index - 1]['photoPath'] ?? '',
                          networkUrl: networkUrl,
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                    ),
                  ),
                  Text(isAll ? "Tout" : categories[index - 1]['nameCat'] ?? '', style: TextStyle(fontSize: 11, fontWeight: isSelected ? FontWeight.bold : FontWeight.w500), textAlign: TextAlign.center, maxLines: 1),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildProductGrid() {
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
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10)]),
            child: Column(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                    child: ProductImageWidget(key: ValueKey("${p['id']}_${p['photoPath'] ?? 'no_path'}"), localPath: p['photoPath'], networkUrl: imageUrl),
                  ),
                ),
                Padding(padding: const EdgeInsets.all(12), child: Column(children: [Text(p['productName'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)), Text("${p['productPrice']} FCFA", style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.w900))])),
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
      builder: (context) => SafeArea(
        child: StatefulBuilder(builder: (context, setModalState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.85,
            decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
            child: Column(
              children: [
                ProductImageWidget(localPath: p['photoPath'], networkUrl: imageUrl, height: 300, width: double.infinity, borderRadius: const BorderRadius.vertical(top: Radius.circular(30))),
                Padding(
                    padding: const EdgeInsets.all(25),
                    child: Column(
                        children: [
                          Row(children: [Expanded(child: Text(p['productName'] ?? '', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold))), Text("${p['productPrice']} FCFA", style: const TextStyle(fontSize: 20, color: Colors.orange, fontWeight: FontWeight.w900))]),
                          const SizedBox(height: 20),
                          Row(mainAxisAlignment: MainAxisAlignment.center, children: [IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: () => quantity > 1 ? setModalState(() => quantity--) : null), Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Text("$quantity", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold))), IconButton(icon: const Icon(Icons.add_circle_outline, color: Colors.orange), onPressed: () => setModalState(() => quantity++))]),
                          const SizedBox(height: 20),
                          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, minimumSize: const Size(double.infinity, 55)), onPressed: () { Provider.of<CartProvider>(context, listen: false).addItem(p['id'].toString(), p['productName'], (p['productPrice'] as num).toDouble(), imageUrl, quantity); Navigator.pop(context); }, child: const Text("AJOUTER", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                        ]
                    )
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildCartBadge() {
    return Consumer<CartProvider>(
      builder: (context, cart, _) => Badge(
        label: Text("${cart.items.length}", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        isLabelVisible: cart.items.isNotEmpty,
        backgroundColor: Colors.orange,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          icon: const Icon(Icons.shopping_cart_outlined, size: 28),
          color: Colors.black,
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CartScreen())),
        ),
      ),
    );
  }
}