import 'package:flutter/material.dart';
import '../services/database/database_helper.dart';

class NotificationsScreen extends StatefulWidget {
  final String structureId;

  const NotificationsScreen({super.key, required this.structureId});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  List<Map<String, dynamic>> _alerts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchAlerts();
  }

  Future<void> _fetchAlerts() async {
    try {
      final alertProducts = await _dbHelper.getProductsInAlert(widget.structureId);

      debugPrint('########: ${widget.structureId}');

      if (mounted) {
        setState(() {
          _alerts = alertProducts;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Erreur lors de la récupération des alertes : $e");
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      appBar: AppBar(
        title: Text(
          "Notifications (${_alerts.length})", // 👈 Optionnel : Afficher aussi le nombre dans le titre
          style: const TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.black))
          : Column(
        children: [
          if (_alerts.isNotEmpty)
            Container(
              margin: const EdgeInsets.fromLTRB(20, 10, 20, 10),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.orange, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      // 🔍 Message dynamique affichant le nombre exact de produits
                      "${_alerts.length} ${_alerts.length > 1 ? 'produits sont en alerte' : 'produit est en alerte'}. Merci de contacter le responsable.",
                      style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _alerts.isEmpty
                ? const Center(child: Text("Aucune alerte, tout est en ordre."))
                : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              itemCount: _alerts.length,
              itemBuilder: (context, index) => _buildMinimalItem(_alerts[index]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMinimalItem(Map<String, dynamic> item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(width: 4, height: 24, color: Colors.orange),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item['productName'] ?? "Produit", style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                const SizedBox(height: 4),
                Text("Stock bas : ${item['productQte']} restant", style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
              ],
            ),
          ),
          const Icon(Icons.warning_amber_rounded, size: 20, color: Colors.orange),
        ],
      ),
    );
  }
}