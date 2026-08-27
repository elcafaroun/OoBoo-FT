import 'dart:io';
import 'package:fada/screens/home_screen.dart';
import 'package:fada/screens/notifications_screen.dart';
import 'package:fada/screens/scanner_screen.dart';
import 'package:fada/services/network_checker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/category_service.dart';
import '../services/product_service.dart';
import '../services/command_service.dart';
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

  const CategoriesScreen({
    super.key,
    required this.structureId,
    required this.structureName,
  });

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> with WidgetsBindingObserver {
  int _alertCount = 0;

  final CategoryService _categoryService = CategoryService();
  final ProductService _productService = ProductService();
  final CommandService _commandService = CommandService();
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final TextEditingController _searchController = TextEditingController();

  List<dynamic> categories = [];
  List<dynamic> allProducts = [];
  List<dynamic> filteredProducts = [];
  List<dynamic> allOrders = [];

  String selectedCategoryId = "TOUS";
  bool isLoading = true;
  bool isOfflineMode = false;
  String? userProfile;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadData();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    super.dispose();
  }

  /// 🔄 Rafraîchit les commandes dès que l'application repasse au premier plan
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshOrdersOnly();
    }
  }

  /// 🔢 Calcul dynamique du nombre de commandes avec le statut PENDING
  int get _pendingOrdersCount {
    return allOrders.where((order) {
      String status = (order['status'] ?? 'PENDING').toString().toUpperCase();
      return status == 'PENDING';
    }).length;
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    userProfile = prefs.getString('userProfile');

    // 1. CHARGEMENT IMMÉDIAT DE LA BASE LOCALE (SQLite)
    await _loadFromLocalDatabase();

    // 2. SYNCHRONISATION ARRIÈRE-PLAN
    await _syncWithBackendIfOnline();
  }

  /// Chargement des données locales
  Future<void> _loadFromLocalDatabase() async {
    try {
      final localCats = await _dbHelper.getCategoriesByStructureLocal(widget.structureId);
      final localProds = await _dbHelper.getProductsByStructureLocal(widget.structureId);
      final localAlerts = await _dbHelper.getProductsInAlert(widget.structureId);
      final localOrders = await _dbHelper.getLocalCommands(widget.structureId);

      if (mounted) {
        setState(() {
          categories = localCats;
          allProducts = localProds;
          _applyFilters();
          _alertCount = localAlerts.length;
          allOrders = localOrders;
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("⚠️ Erreur lors de la lecture SQLite locale : $e");
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  /// Synchronisation silencieuse avec le backend si le réseau est dispo
  Future<void> _syncWithBackendIfOnline() async {
    bool hasConnection = await NetworkChecker.isBackendAccessible();

    if (!mounted) return;

    setState(() {
      isOfflineMode = !hasConnection;
    });

    if (hasConnection) {
      try {
        final remoteCats = await _categoryService
            .getCategoriesByStructure(widget.structureId)
            .timeout(const Duration(seconds: 8));
        final remoteProds = await _productService
            .getProductsByStructure(widget.structureId)
            .timeout(const Duration(seconds: 8));
        final remoteOrders = await _commandService
            .getCommandsByStructure(widget.structureId)
            .timeout(const Duration(seconds: 8));

        await _dbHelper.syncCategoriesLocal(remoteCats);
        await _dbHelper.syncProductsLocal(remoteProds);
        await _dbHelper.syncCommandsLocal(remoteOrders);

        // Rechargement des données fraîches depuis SQLite après synchro
        await _loadFromLocalDatabase();
      } catch (e) {
        debugPrint("⚠️ Synchronisation échouée, passage en mode hors-ligne : $e");
        if (mounted) {
          setState(() {
            isOfflineMode = true;
          });
        }
      }
    }
  }

  Future<void> _refreshOrdersOnly() async {
    final localOrders = await _dbHelper.getLocalCommands(widget.structureId);
    if (mounted) {
      setState(() {
        allOrders = localOrders;
      });
    }
  }

  void _onSearchChanged() {
    setState(() {
      _applyFilters();
    });
  }

  void _applyFilters() {
    final query = _searchController.text.toLowerCase().trim();
    filteredProducts = allProducts.where((p) {
      final matchesQuery = p['productName'].toString().toLowerCase().contains(query);
      final matchesCategory = (selectedCategoryId == "TOUS") ||
          (p['categoryId']?.toString() == selectedCategoryId);
      return matchesQuery && matchesCategory;
    }).toList();
  }

  Future<void> _scanAndFindProduct() async {
    final String? codeScanne = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const ScannerScreen()),
    );

    if (codeScanne != null && codeScanne.isNotEmpty) {
      final String cleanCode = codeScanne.toLowerCase().trim();
      final product = allProducts.firstWhereOrNull(
              (p) => p['productQrCode']?.toString().toLowerCase().trim() == cleanCode);

      if (product != null) {
        final String imageUrl = product['photo'] ?? product['productPhotoUrl'] ?? '';
        Provider.of<CartProvider>(context, listen: false).addItem(
          product['id'].toString(),
          product['productName'],
          (product['productPrice'] as num).toDouble(),
          imageUrl,
          1,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Ajouté : ${product['productName']}"),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Aucun produit trouvé."),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  Widget _buildActionButton(IconData icon, VoidCallback onPressed) {
    return IconButton(
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      icon: Icon(icon, size: 26),
      color: Colors.black,
      onPressed: onPressed,
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isTrulyEmpty = !isLoading && categories.isEmpty && allProducts.isEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFF9F7F2),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black87, size: 22),
          onPressed: () => Navigator.of(context).pop(),
        ),
        titleSpacing: 0,
        title: isTrulyEmpty
            ? Text(
          widget.structureName.isNotEmpty ? widget.structureName : "Catalogue",
          style: const TextStyle(color: Colors.black87, fontSize: 18, fontWeight: FontWeight.bold),
        )
            : Padding(
          padding: const EdgeInsets.only(right: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildActionButton(Icons.qr_code_scanner, _scanAndFindProduct),
              Badge(
                isLabelVisible: _pendingOrdersCount > 0,
                label: Text("$_pendingOrdersCount",
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                backgroundColor: Colors.orange,
                child: _buildActionButton(
                  Icons.receipt_long_outlined,
                      () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const OrdersScreen()),
                    );
                    await _refreshOrdersOnly();
                  },
                ),
              ),
              _buildCartBadge(),
              IconButton(
                icon: const Icon(Icons.home_rounded, color: Color(0xFFFF9800), size: 26),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const HomeScreen()),
                        (route) => false,
                  );
                },
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        child: isLoading
            ? const Center(child: CircularProgressIndicator(color: Colors.orange))
            : isTrulyEmpty
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
                const Text(
                  "Aucune donnée disponible",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                ),
                const SizedBox(height: 8),
                const Text(
                  "Connectez-vous à Internet au moins une fois pour télécharger le catalogue de cette structure.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF64748B), fontSize: 14, height: 1.4),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        side: BorderSide(color: Colors.grey.shade400),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back, size: 18, color: Colors.black87),
                      label: const Text("Retour", style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF9800),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      onPressed: () {
                        setState(() {
                          isLoading = true;
                        });
                        _loadData();
                      },
                      icon: const Icon(Icons.refresh_rounded, color: Colors.white, size: 18),
                      label: const Text("Réessayer", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        )
            : Column(
          children: [
            if (isOfflineMode) _buildOfflineBanner(),
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

  Widget _buildOfflineBanner() {
    return Container(
      width: double.infinity,
      color: Colors.amber.shade800,
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.wifi_off_rounded, color: Colors.white, size: 14),
          SizedBox(width: 6),
          Text(
            "Mode Hors-Ligne (Données locales)",
            style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ],
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
                    builder: (_) => NotificationsScreen(structureId: widget.structureId),
                  ),
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
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide.none,
          ),
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
          final cat = isAll ? null : categories[index - 1];
          final catId = isAll ? "TOUS" : cat['id'].toString();
          final isSelected = selectedCategoryId == catId;

          String networkUrl = "";
          if (!isAll && cat != null) {
            final photoCat = cat['photoCat'];
            if (photoCat != null && photoCat.toString() != "null" && photoCat.toString().isNotEmpty) {
              networkUrl = "$baseUrl/category/image/$photoCat";
            }
          }

          return GestureDetector(
            onTap: () {
              setState(() {
                selectedCategoryId = catId;
                _applyFilters();
              });
            },
            child: Container(
              width: 75,
              margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: Column(
                children: [
                  Container(
                    height: 60,
                    width: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSelected ? Colors.orange : Colors.white,
                      border: Border.all(
                        color: isSelected ? Colors.orange : Colors.grey.shade200,
                        width: 2,
                      ),
                    ),
                    child: Center(
                      child: isAll
                          ? Icon(Icons.apps, color: isSelected ? Colors.white : Colors.grey)
                          : ClipOval(
                        child: ProductImageWidget(
                          key: ValueKey("cat_${cat['id']}"),
                          localPath: cat['photoPath'] ?? '',
                          networkUrl: networkUrl,
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isAll ? "Tout" : (cat['nameCat'] ?? ''),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildProductGrid() {
    if (filteredProducts.isEmpty) {
      return const Center(
        child: Text(
          "Aucun produit trouvé",
          style: TextStyle(color: Colors.grey, fontSize: 14),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.75,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
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
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10),
              ],
            ),
            child: Column(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                    child: ProductImageWidget(
                      key: ValueKey("prod_${p['id']}"),
                      localPath: p['photoPath'],
                      networkUrl: imageUrl,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Text(
                        p['productName'] ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "${p['productPrice']} FCFA",
                        style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showFullDetails(dynamic p, String imageUrl) {
    int quantity = 1;
    final String rawDescription = p['productDescription'] ?? '';

    final List<String> detailsList = rawDescription
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        child: StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.88,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
              ),
              child: Column(
                children: [
                  ProductImageWidget(
                    key: ValueKey("detail_${p['id']}"),
                    localPath: p['photoPath'],
                    networkUrl: imageUrl,
                    height: 260,
                    width: double.infinity,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(25),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  p['productName'] ?? '',
                                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                                ),
                              ),
                              Text(
                                "${p['productPrice']} FCFA",
                                style: const TextStyle(
                                  fontSize: 18,
                                  color: Colors.orange,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline, size: 28),
                                onPressed: () =>
                                quantity > 1 ? setModalState(() => quantity--) : null,
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 20),
                                child: Text(
                                  "$quantity",
                                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.add_circle_outline, color: Colors.orange, size: 28),
                                onPressed: () => setModalState(() => quantity++),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              minimumSize: const Size(double.infinity, 55),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                              elevation: 0,
                            ),
                            onPressed: () {
                              Provider.of<CartProvider>(context, listen: false).addItem(
                                p['id'].toString(),
                                p['productName'],
                                (p['productPrice'] as num).toDouble(),
                                imageUrl,
                                quantity,
                              );
                              Navigator.pop(context);
                            },
                            child: const Text(
                              "AJOUTER AU PANIER",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          if (detailsList.isNotEmpty) ...[
                            const SizedBox(height: 25),
                            const Divider(height: 1, color: Color(0xFFF1F5F9)),
                            const SizedBox(height: 20),
                            const Text(
                              "Caractéristiques",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1E293B),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Column(
                              children: detailsList.map((detail) {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 10.0),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(2),
                                        decoration: const BoxDecoration(
                                          color: Color(0xFFDCFCE7),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.check_rounded,
                                          size: 16,
                                          color: Color(0xFF16A34A),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          detail,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                            color: Color(0xFF334155),
                                            height: 1.3,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildCartBadge() {
    return Consumer<CartProvider>(
      builder: (context, cart, _) => Badge(
        label: Text("${cart.items.length}",
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        isLabelVisible: cart.items.isNotEmpty,
        backgroundColor: Colors.orange,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          icon: const Icon(Icons.shopping_cart_outlined, size: 26),
          color: Colors.black,
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CartScreen()),
          ),
        ),
      ),
    );
  }
}