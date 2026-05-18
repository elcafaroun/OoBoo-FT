import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/product_service.dart';

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

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredAll = _allProducts.where((p) =>
          (p['productName'] ?? "").toString().toLowerCase().contains(query)).toList();
      _filteredAlerts = _alertProducts.where((p) =>
          (p['productName'] ?? "").toString().toLowerCase().contains(query)).toList();
    });
  }

  // --- Dialogue de mise à jour ---
  void _showUpdateDialog(Map<String, dynamic> product) {
    final TextEditingController qteController = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, top: 20, left: 20, right: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Réapprovisionnement", style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            TextField(
              controller: qteController,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: InputDecoration(
                labelText: "Quantité à ajouter",
                filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF9800), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                onPressed: () async {
                  if (qteController.text.isNotEmpty) {
                    int qtyToAdd = int.parse(qteController.text);
                    bool success = await ProductService().updateProductStock(product['id'], -qtyToAdd);
                    if (success && mounted) {
                      Navigator.pop(context);
                      _loadData(); // Rafraîchir tout
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
          actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData)],
        ),
        body: Column(
          children: [
            // Zone de recherche PRO
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: "Rechercher un produit...",
                  prefixIcon: const Icon(Icons.search, color: Color(0xFFFF9800)),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide(color: Colors.grey.shade200)),
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
      return Center(child: Text(isAlert ? "Tout est en règle" : "Aucun produit trouvé"));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: products.length,
      itemBuilder: (context, i) {
        final item = products[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.grey.withOpacity(0.1)),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: ListTile(
            onTap: () => _showUpdateDialog(item),
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: (isAlert ? Colors.red : Colors.blue).withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(isAlert ? Icons.warning_amber_rounded : Icons.inventory_2_rounded, color: isAlert ? Colors.red : Colors.blue),
            ),
            title: Text(item['productName'] ?? "Produit", style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text("Stock : ${item['productQte'] ?? 0}"),
            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
          ),
        );
      },
    );
  }
}