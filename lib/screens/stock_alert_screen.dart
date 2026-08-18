import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/product_service.dart';
import 'scanner_screen.dart'; // 🔹 Importation de votre écran de scan

class StockAlertScreen extends StatefulWidget {
  const StockAlertScreen({super.key});

  @override
  State<StockAlertScreen> createState() => _StockAlertScreenState();
}

class _StockAlertScreenState extends State<StockAlertScreen> {
  // Contrôleur de recherche
  final TextEditingController _searchController = TextEditingController();

  // Listes pour gérer le filtrage
  List<Map<String, dynamic>> _allProducts = [];
  List<Map<String, dynamic>> _alertProducts = [];
  List<Map<String, dynamic>> _filteredAll = [];
  List<Map<String, dynamic>> _filteredAlerts = [];

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
    // Écoute les changements de texte pour filtrer
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    final String? profile = prefs.getString('selected_structure_id');
    if (profile == null) return;

    // Récupération des données
    final alerts = await ProductService().fetchStockAlerts(profile);
    final all = await ProductService().getProductsByStructure(profile);

    setState(() {
      _alertProducts = alerts;
      _allProducts = all;
      _filteredAlerts = alerts;
      _filteredAll = all;
      _isLoading = false;
    });
  }

  // 🔹 Filtrage multi-critères : Nom du produit OU Code QR
  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      _filteredAll = _allProducts.where((p) {
        final name = (p['productName'] ?? "").toString().toLowerCase();
        final qr = (p['productQrCode'] ?? "").toString().toLowerCase();
        return name.contains(query) || qr.contains(query);
      }).toList();

      _filteredAlerts = _alertProducts.where((p) {
        final name = (p['productName'] ?? "").toString().toLowerCase();
        final qr = (p['productQrCode'] ?? "").toString().toLowerCase();
        return name.contains(query) || qr.contains(query);
      }).toList();
    });
  }

  // 📸 Scanner un code QR / Barres pour chercher et réapprovisionner
  Future<void> _scanQrCode() async {
    final String? codeScanne = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const ScannerScreen()),
    );

    if (codeScanne != null && codeScanne.isNotEmpty) {
      final String cleanCode = codeScanne.trim();
      _searchController.text = cleanCode;

      // Chercher si le produit scanné existe dans la liste globale
      final matchingProduct = _allProducts.firstWhere(
            (p) => (p['productQrCode'] ?? "").toString().trim().toLowerCase() == cleanCode.toLowerCase(),
        orElse: () => {},
      );

      if (matchingProduct.isNotEmpty) {
        // Ouvrir directement le dialogue de mise à jour si trouvé
        if (mounted) {
          _showUpdateDialog(matchingProduct);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Aucun produit trouvé avec le code : $cleanCode"),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    }
  }

  // --- Dialogue de mise à jour ---
  void _showUpdateDialog(Map<String, dynamic> product) {
    final TextEditingController qteController = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          top: 20,
          left: 20,
          right: 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Réapprovisionnement",
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 5),
            Text(
              "${product['productName'] ?? 'Produit'} (Stock actuel : ${product['productQte'] ?? 0})",
              style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: qteController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
              decoration: InputDecoration(
                labelText: "Quantité à ajouter",
                prefixIcon: const Icon(Icons.add_box, color: Color(0xFFFF9800)),
                filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF9800),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () async {
                  if (qteController.text.isNotEmpty) {
                    final double qtyToAdd = double.tryParse(qteController.text) ?? 0;
                    if (qtyToAdd > 0) {
                      // Appel du service pour mettre à jour le stock
                      bool success = await ProductService().updateProductStock(product['id'], -qtyToAdd.toInt());
                      if (success && mounted) {
                        Navigator.pop(context);
                        _loadData(); // Rafraîchir les données
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("Stock réapprovisionné avec succès ! ✅"),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    }
                  }
                },
                child: const Text("VALIDER", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFFF9F7F2),
        appBar: AppBar(
          title: const Text("Gestion des Stocks", style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
          bottom: const TabBar(
            indicatorColor: Color(0xFFFF9800),
            labelColor: Color(0xFFFF9800),
            unselectedLabelColor: Colors.grey,
            tabs: [Tab(text: "Alertes"), Tab(text: "Tous les produits")],
          ),
          actions: [
            IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData),
          ],
        ),
        body: Column(
          children: [
            // Zone de recherche avec bouton Scanner QR
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: "Rechercher par nom ou code QR...",
                  prefixIcon: const Icon(Icons.search, color: Color(0xFFFF9800)),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_searchController.text.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.clear, color: Colors.grey),
                          onPressed: () {
                            _searchController.clear();
                          },
                        ),
                      IconButton(
                        icon: const Icon(Icons.qr_code_scanner_rounded, color: Colors.blue),
                        tooltip: "Scanner pour rechercher",
                        onPressed: _scanQrCode,
                      ),
                    ],
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                ),
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF9800)))
                  : TabBarView(
                children: [
                  _buildList(_filteredAlerts, isAlert: true),
                  _buildList(_filteredAll, isAlert: false),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(List<Map<String, dynamic>> products, {required bool isAlert}) {
    if (products.isEmpty) {
      return Center(
        child: Text(
          isAlert ? "Tout est en règle" : "Aucun produit trouvé",
          style: TextStyle(color: Colors.grey.shade600),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: products.length,
      itemBuilder: (context, i) {
        final item = products[i];
        final String qrCode = item['productQrCode'] ?? "";

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.grey.withOpacity(0.1)),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4)),
            ],
          ),
          child: ListTile(
            onTap: () => _showUpdateDialog(item),
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: (isAlert ? Colors.red : Colors.blue).withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isAlert ? Icons.warning_amber_rounded : Icons.inventory_2_rounded,
                color: isAlert ? Colors.red : Colors.blue,
              ),
            ),
            title: Text(item['productName'] ?? "Produit", style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Stock : ${item['productQte'] ?? 0}"),
                if (qrCode.isNotEmpty)
                  Text(
                    "QR : $qrCode",
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
              ],
            ),
            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
          ),
        );
      },
    );
  }
}