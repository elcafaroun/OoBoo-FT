import 'package:flutter/material.dart';
import 'package:fada/screens/user_list_screen.dart';
import 'stock_alert_screen.dart'; // Assurez-vous que ce fichier est au même niveau
import '../services/depense_service.dart';
import 'dashboard_screen.dart';
import 'add_category_screen.dart';

class StructureAdminScreen extends StatelessWidget {
  final String structureId;
  final String structureName;
  final DepenseService _depenseService = DepenseService();

  StructureAdminScreen({
    super.key,
    required this.structureId,
    required this.structureName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F7F2), // Fond très clair
      appBar: AppBar(
        title: Text(
          structureName,
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(color: Colors.grey.withOpacity(0.2), height: 1.0),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 25),
        child: Column(
          children: [
            _buildWelcomeCard(),
            const SizedBox(height: 30),

            // Menu Items
            _buildMenuTile(
              context,
              icon: Icons.bar_chart_rounded,
              color: const Color(0xFF546E7A),
              title: "Tableau de bord",
              subtitle: "Analyse et rapports",
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DashboardScreen(structureId: structureId))),
            ),
            _buildMenuTile(
              context,
              icon: Icons.payments_rounded,
              color: const Color(0xFFE53935),
              title: "Dépenses",
              subtitle: "Enregistrer une sortie",
              onTap: () => _showAddExpenseDialog(context),
            ),
            _buildMenuTile(
              context,
              icon: Icons.category_rounded,
              color: const Color(0xFFFB8C00),
              title: "Catégories",
              subtitle: "Gestion des rubriques",
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AddCategoryScreen(structureId: structureId))),
            ),
            // Ajout du module Stock
            _buildMenuTile(
              context,
              icon: Icons.inventory_2_rounded,
              color: const Color(0xFF4CAF50),
              title: "Stock & Inventaire",
              subtitle: "Alertes et ajustements",
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StockAlertScreen())),
            ),
            _buildMenuTile(
              context,
              icon: Icons.people_alt_rounded,
              color: const Color(0xFF3949AB),
              title: "Utilisateurs",
              subtitle: "Administration personnel",
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UserListScreen())),
            ),
          ],
        ),
      ),
    );
  }

  // Header Style
  Widget _buildWelcomeCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))
        ],
      ),
      child: Column(
        children: [
          const Icon(Icons.admin_panel_settings_rounded, size: 60, color: Color(0xFFFF9800)),
          const SizedBox(height: 15),
          const Text("Espace Administration", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 5),
          Text("Gérez les opérations de $structureName", style: TextStyle(color: Colors.grey[600])),
        ],
      ),
    );
  }

  // Menu Tile Style
  Widget _buildMenuTile(BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey.withOpacity(0.1)),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12)
          ),
          child: Icon(icon, color: color, size: 28),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        subtitle: Text(subtitle, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
        trailing: Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.grey[400]),
      ),
    );
  }

  // Dialogue Logique
  Future<void> _showAddExpenseDialog(BuildContext context) async {
    final amountController = TextEditingController();
    final titleController = TextEditingController();
    DateTime selectedDate = DateTime.now();

    return showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
          title: const Text("Nouvelle Dépense", style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: InputDecoration(
                    labelText: "Intitulé",
                    prefixIcon: const Icon(Icons.description),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))
                ),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: amountController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                    labelText: "Montant (FCFA)",
                    prefixIcon: const Icon(Icons.payments),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))
                ),
              ),
              const SizedBox(height: 15),
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: selectedDate,
                    firstDate: DateTime(2024),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) setDialogState(() => selectedDate = picked);
                },
                icon: const Icon(Icons.calendar_today),
                label: Text("${selectedDate.day}/${selectedDate.month}/${selectedDate.year}"),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Annuler")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF9800),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
              ),
              onPressed: () async {
                if (amountController.text.isNotEmpty && titleController.text.isNotEmpty) {
                  final depenseData = {
                    "codeStructure": structureId,
                    "amount": amountController.text,
                    "intitule": titleController.text,
                    "dateDepense": selectedDate.toIso8601String().split('T')[0],
                    "createdBy": "Admin",
                  };
                  bool success = await _depenseService.createDepense(depenseData);
                  if (success && context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Dépense enregistrée !"), backgroundColor: Colors.green)
                    );
                  }
                }
              },
              child: const Text("Enregistrer"),
            ),
          ],
        ),
      ),
    );
  }
}