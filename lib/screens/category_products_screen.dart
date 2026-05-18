import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/product_service.dart';
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
  List<dynamic> products = [];

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    try {
      final result = await _productService.getProductsByCategory(widget.categoryId);
      if (mounted) {
        setState(() {
          products = result;
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => isLoading = false);
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
      _loadProducts();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Erreur mise à jour")));
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

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("Modifier le produit"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () async {
                    final XFile? pickedFile = await picker.pickImage(source: ImageSource.gallery);
                    if (pickedFile != null) {
                      setDialogState(() => selectedImage = File(pickedFile.path));
                    }
                  },
                  child: Container(
                    height: 100, width: 100,
                    color: Colors.grey[200],
                    child: selectedImage != null
                        ? Image.file(selectedImage!, fit: BoxFit.cover)
                        : (product['productPhotoUrl'] != null
                        ? Image.network(product['productPhotoUrl'], fit: BoxFit.cover)
                        : const Icon(Icons.camera_alt, size: 40, color: Colors.grey)),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(controller: nameController, decoration: const InputDecoration(labelText: "Nom")),
                TextField(controller: descController, decoration: const InputDecoration(labelText: "Description")),
                TextField(controller: buyPriceController, decoration: const InputDecoration(labelText: "Prix Achat"), keyboardType: TextInputType.number),
                TextField(controller: sellPriceController, decoration: const InputDecoration(labelText: "Prix Vente"), keyboardType: TextInputType.number),
                TextField(controller: stockController, decoration: const InputDecoration(labelText: "Stock Actuel"), keyboardType: TextInputType.number),
                TextField(controller: alertStockController, decoration: const InputDecoration(labelText: "Stock Alerte"), keyboardType: TextInputType.number),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Annuler")),
            ElevatedButton(
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

                  Navigator.pop(context);
                  _loadProducts();
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Produit mis à jour")));
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erreur : $e")));
                }
              },
              child: const Text("Enregistrer"),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F7F2),
      appBar: AppBar(
        title: Text(
          "Produits ➔ ${widget.categoryName}",
          style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF9800)))
          : products.isEmpty
          ? const Center(child: Text("Aucun produit trouvé"))
          : ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: products.length,
        itemBuilder: (_, i) {
          final p = products[i];
          final bool isActive = p['active'] ?? true;

          return Opacity(
            opacity: isActive ? 1.0 : 0.6,
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.grey.withOpacity(0.2)),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                leading: _productImage(p),
                title: Text(p['productName'] ?? 'Sans nom', style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(child: Text("Vente: ${p['productPrice'] ?? '0'} FCFA", style: const TextStyle(fontSize: 12))),
                        Expanded(child: Text("Achat: ${p['prixAchat'] ?? '0'} FCFA", style: const TextStyle(fontSize: 12))),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            "Stock: ${p['productQte'] ?? '0'}",
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFFF9800)),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            "Alerte: ${p['stockAlert'] ?? '0'}",
                            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red[400]),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                trailing: PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Colors.orange),
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
                        Icon(isActive ? Icons.block : Icons.check_circle, size: 18, color: isActive ? Colors.red : Colors.green),
                        const SizedBox(width: 8),
                        Text(isActive ? "Désactiver" : "Activer"),
                      ]),
                    ),
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(children: [
                        Icon(Icons.edit, color: Colors.blue, size: 18),
                        const SizedBox(width: 8),
                        Text("Modifier"),
                      ]),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFFFF9800),
        foregroundColor: Colors.white,
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => AddProductScreen(categoryId: widget.categoryId)),
          );
          _loadProducts();
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _productImage(dynamic product) {
    final imageUrl = product['productPhotoUrl'] ?? product['image'] ?? product['imageName'];

    // On ajoute un timestamp pour forcer le rafraîchissement si l'URL existe
    final String? urlWithCacheBuster = imageUrl != null
        ? "$imageUrl?t=${DateTime.now().millisecondsSinceEpoch}"
        : null;

    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: (urlWithCacheBuster != null && urlWithCacheBuster.toString().isNotEmpty)
            ? Image.network(
          urlWithCacheBuster,
          fit: BoxFit.cover,
          // key: ValueKey(urlWithCacheBuster), // Optionnel: force la reconstruction du widget
          errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.grey),
        )
            : const Icon(Icons.inventory_2_rounded, color: Colors.grey),
      ),
    );
  }
}