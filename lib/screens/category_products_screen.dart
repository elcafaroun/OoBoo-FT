import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/product_service.dart';
import '../services/network_checker.dart'; // ✅ Intégration de ton service réseau
import 'add_product_screen.dart';

class CategoryProductsScreen extends StatefulWidget {
  final String categoryId;
  final String categoryName;

  const CategoryProductsScreen({
    super.key,
    required this.categoryId,
    required this.categoryName,
  });

  @override
  State<CategoryProductsScreen> createState() => _CategoryProductsScreenState();
}

class _CategoryProductsScreenState extends State<CategoryProductsScreen> {
  final ProductService _productService = ProductService();

  bool isLoading = true;
  bool isCheckingNetwork = false;
  bool isBackendAccessible = true;
  List<dynamic> products = [];

  @override
  void initState() {
    super.initState();
    _checkNetworkAndLoad();
  }

  /// 🔹 Vérification réseau et chargement des produits
  Future<void> _checkNetworkAndLoad() async {
    if (!mounted) return;
    setState(() {
      if (products.isEmpty) {
        isLoading = true;
      } else {
        isCheckingNetwork = true;
      }
    });

    try {
      bool online = await NetworkChecker.isBackendAccessible();

      if (!online) {
        if (mounted) {
          setState(() {
            isBackendAccessible = false;
            isLoading = false;
            isCheckingNetwork = false;
          });
        }
        return;
      }

      if (mounted) {
        setState(() => isBackendAccessible = true);
      }
      await _loadProducts();
    } catch (e) {
      debugPrint("❌ Erreur réseau produits : $e");
      if (mounted) {
        setState(() {
          isBackendAccessible = false;
          isLoading = false;
          isCheckingNetwork = false;
        });
      }
    }
  }

  Future<void> _loadProducts() async {
    try {
      final result = await _productService.getProductsByCategory(widget.categoryId);
      if (mounted) {
        setState(() {
          products = result ?? [];
          isLoading = false;
          isCheckingNetwork = false;
        });
      }
    } catch (e) {
      debugPrint("❌ Erreur chargement produits : $e");
      if (mounted) {
        setState(() {
          isLoading = false;
          isCheckingNetwork = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erreur: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _toggleProductStatus(dynamic product) async {
    final bool currentStatus = product['active'] ?? true;
    try {
      await _productService.updateStatus(
        categoryId: product['id'].toString(),
        isActive: !currentStatus,
      );
      _checkNetworkAndLoad();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Erreur mise à jour"), backgroundColor: Colors.red));
      }
    }
  }

  void _showEditDialog(dynamic product) {
    final TextEditingController nameController = TextEditingController(text: product['productName']);
    final TextEditingController descController = TextEditingController(text: product['productDescription'] ?? '');
    final TextEditingController buyPriceController = TextEditingController(text: product['prixAchat']?.toString() ?? '0');
    final TextEditingController sellPriceController = TextEditingController(text: product['productPrice']?.toString() ?? '0');
    final TextEditingController stockController = TextEditingController(text: product['productQte']?.toString() ?? '0');
    final TextEditingController alertStockController = TextEditingController(text: product['stockAlert']?.toString() ?? '0');

    File? selectedImage;
    final ImagePicker picker = ImagePicker();

    // 🌟 Décoration aérée et optimisée
    InputDecoration _inputStyle(String label, IconData icon, {String? suffix}) {
      return InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
        prefixIcon: Icon(icon, color: const Color(0xFFFF9800), size: 18),
        suffixText: suffix,
        suffixStyle: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 13),
        floatingLabelStyle: const TextStyle(color: Color(0xFFFF9800), fontWeight: FontWeight.bold),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        // ✅ Moins haut à l'intérieur pour un rendu plus compact et élégant
        contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200, width: 1)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFFF9800), width: 1.5)),
      );
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          titlePadding: const EdgeInsets.only(top: 24, left: 24, right: 24, bottom: 4),
          contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          actionsPadding: const EdgeInsets.only(bottom: 16, right: 16, left: 16, top: 8),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: const Color(0xFFFF9800).withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.edit_note_rounded, color: Color(0xFFFF9800)),
              ),
              const SizedBox(width: 12),
              const Text("Modifier le produit", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF1E293B))),
            ],
          ),
          content: SizedBox(
            width: MediaQuery.of(context).size.width * 0.95,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 📸 Zone Image
                  Center(
                    child: GestureDetector(
                      onTap: () async {
                        final XFile? pickedFile = await picker.pickImage(source: ImageSource.gallery);
                        if (pickedFile != null) {
                          setDialogState(() => selectedImage = File(pickedFile.path));
                        }
                      },
                      child: Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          Container(
                            height: 100,
                            width: 100,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 4))],
                              border: Border.all(color: Colors.white, width: 3),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(17),
                              child: selectedImage != null
                                  ? Image.file(selectedImage!, fit: BoxFit.cover)
                                  : (product['productPhotoUrl'] != null && product['productPhotoUrl'].toString().startsWith('http')
                                  ? Image.network(product['productPhotoUrl'], fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.camera_alt_rounded, size: 32, color: Colors.grey))
                                  : const Icon(Icons.camera_alt_rounded, size: 32, color: Color(0xFF94A3B8))),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(color: Color(0xFFFF9800), shape: BoxShape.circle),
                            child: const Icon(Icons.add_a_photo_rounded, size: 12, color: Colors.white),
                          )
                        ],
                      ),
                    ),
                  ),

                  // ✅ Marges verticales accentuées entre chaque bloc
                  const SizedBox(height: 24),

                  // 📝 Champ : Nom
                  TextField(controller: nameController, decoration: _inputStyle("Nom du produit", Icons.shopping_bag_rounded)),
                  const SizedBox(height: 16), // Espacement net

                  // 📝 Champ : Description
                  TextField(controller: descController, decoration: _inputStyle("Description", Icons.description_rounded)),
                  const SizedBox(height: 16), // Espacement net

                  // 💰 Section Prix (Grille espacée)
                  Row(
                    children: [
                      Expanded(child: TextField(controller: buyPriceController, decoration: _inputStyle("Prix Achat", Icons.arrow_downward_rounded, suffix: "F"), keyboardType: TextInputType.number)),
                      const SizedBox(width: 16), // Plus d'espace entre les colonnes
                      Expanded(child: TextField(controller: sellPriceController, decoration: _inputStyle("Prix Vente", Icons.arrow_upward_rounded, suffix: "F"), keyboardType: TextInputType.number)),
                    ],
                  ),
                  const SizedBox(height: 16), // Espacement net

                  // 📦 Section Stock (Grille espacée)
                  Row(
                    children: [
                      Expanded(child: TextField(controller: stockController, decoration: _inputStyle("Stock Actuel", Icons.inventory_rounded), keyboardType: TextInputType.number)),
                      const SizedBox(width: 16), // Plus d'espace entre les colonnes
                      Expanded(child: TextField(controller: alertStockController, decoration: _inputStyle("Stock Alerte", Icons.warning_amber_rounded), keyboardType: TextInputType.number)),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
              child: const Text("Annuler", style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold, fontSize: 14)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF9800),
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                try {
                  final Map<String, dynamic> updateData = {
                    "productName": nameController.text,
                    "productDescription": descController.text,
                    "prixAchat": double.tryParse(buyPriceController.text) ?? 0,
                    "productPrice": double.tryParse(sellPriceController.text) ?? 0,
                    "productQte": double.tryParse(stockController.text) ?? 0,
                    "stockAlert": double.tryParse(alertStockController.text) ?? 0,
                    "codeStructure": product['codeStructure'],
                    "categoryId": product['categoryId'],
                  };

                  await _productService.updateProduct(product['id'].toString(), updateData);

                  if (selectedImage != null) {
                    await _productService.uploadPhoto(product['id'].toString(), selectedImage!);
                  }

                  if (context.mounted) Navigator.pop(context);
                  _checkNetworkAndLoad();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ Produit mis à jour !"), backgroundColor: Colors.green));
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erreur : $e"), backgroundColor: Colors.red));
                  }
                }
              },
              child: const Text("Enregistrer", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
            ),
          ],
        ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: isBackendAccessible ? const Color(0xFFF8FAFC) : Colors.white,
      appBar: AppBar(
        title: Text(
          isBackendAccessible ? "Produits ➔ ${widget.categoryName}" : "",
          style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.3, fontSize: 16),
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1E293B),
        elevation: 0,
        actions: isBackendAccessible
            ? [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _checkNetworkAndLoad,
          )
        ]
            : null,
      ),
      floatingActionButton: (isBackendAccessible && !isLoading)
          ? FloatingActionButton(
        backgroundColor: const Color(0xFFFF9800),
        foregroundColor: Colors.white,
        elevation: 4,
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => AddProductScreen(categoryId: widget.categoryId)),
          );
          _checkNetworkAndLoad();
        },
        child: const Icon(Icons.add, size: 28),
      )
          : null,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: _buildCurrentState(),
      ),
    );
  }

  Widget _buildCurrentState() {
    if (isLoading) {
      return const Center(
        key: ValueKey('loading_products'),
        child: CircularProgressIndicator(color: Color(0xFFFF9800)),
      );
    }

    if (!isBackendAccessible) {
      return _buildOfflineView();
    }

    if (products.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      key: const ValueKey('content_products'),
      onRefresh: _checkNetworkAndLoad,
      color: const Color(0xFFFF9800),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        itemCount: products.length,
        itemBuilder: (_, i) => _buildProductCard(products[i]),
      ),
    );
  }

  Widget _buildOfflineView() {
    return SafeArea(
      key: const ValueKey('offline_products'),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(color: Colors.red.shade50, shape: BoxShape.circle),
                child: Icon(Icons.wifi_off_rounded, size: 72, color: Colors.red.shade400),
              ),
              const SizedBox(height: 32),
              const Text(
                "Service déconnecté",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1E293B), letterSpacing: -0.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              const Text(
                "La consultation des produits requiert une connexion en direct avec le serveur. Vérifiez votre réseau ou réessayez.",
                style: TextStyle(fontSize: 14, color: Color(0xFF64748B), height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: isCheckingNetwork ? null : _checkNetworkAndLoad,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF9800),
                    disabledBackgroundColor: Colors.orange.shade300,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  child: isCheckingNetwork
                      ? const SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                  )
                      : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.refresh_rounded, color: Colors.white),
                      SizedBox(width: 8),
                      Text("VÉRIFIER À NOUVEAU", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 0.5)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProductCard(dynamic p) {
    final bool isActive = p['active'] ?? true;

    return Opacity(
      opacity: isActive ? 1.0 : 0.6,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
          border: Border.all(color: Colors.black.withOpacity(0.03)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: _productImage(p),
            title: Text(
                p['productName'] ?? 'Sans nom',
                style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E293B), fontSize: 15)
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(child: Text("Vente: ${p['productPrice'] ?? '0'} FCFA", style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)))),
                    Expanded(child: Text("Achat: ${p['prixAchat'] ?? '0'} FCFA", style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)))),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        "Stock: ${p['productQte'] ?? '0'}",
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFFF9800), fontSize: 12),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        "Alerte: ${p['stockAlert'] ?? '0'}",
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red[400], fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            trailing: PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded, color: Color(0xFFFF9800)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              onSelected: (value) {
                if (value == 'toggle') {
                  _toggleProductStatus(p);
                } else if (value == 'edit') {
                  _showEditDialog(p);
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'toggle',
                  child: Row(children: [
                    Icon(isActive ? Icons.block_rounded : Icons.check_circle_rounded, size: 18, color: isActive ? Colors.red : Colors.green),
                    const SizedBox(width: 8),
                    Text(isActive ? "Désactiver" : "Activer"),
                  ]),
                ),
                const PopupMenuItem(
                  value: 'edit',
                  child: Row(children: [
                    Icon(Icons.edit_rounded, color: Colors.blue, size: 18),
                    const SizedBox(width: 8),
                    Text("Modifier"),
                  ]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _productImage(dynamic product) {
    final imageUrl = product['productPhotoUrl'] ?? product['image'] ?? product['imageName'];

    final String? urlWithCacheBuster = imageUrl != null && imageUrl.toString().isNotEmpty
        ? "$imageUrl?t=${DateTime.now().millisecondsSinceEpoch}"
        : null;

    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: (urlWithCacheBuster != null && urlWithCacheBuster.startsWith('http'))
            ? Image.network(
          urlWithCacheBuster,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_rounded, color: Colors.grey),
        )
            : const Icon(Icons.inventory_2_rounded, color: Colors.grey, size: 24),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      key: const ValueKey('empty_products'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.grey.shade100, shape: BoxShape.circle),
              child: Icon(Icons.inventory_2_outlined, size: 60, color: Colors.grey.shade400),
            ),
            const SizedBox(height: 24),
            const Text("Aucun produit trouvé", style: TextStyle(color: Color(0xFF1E293B), fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            const Text("Ajoutez des produits à cette catégorie pour alimenter votre stock.", textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF64748B), fontSize: 13)),
          ],
        ),
      ),
    );
  }
}