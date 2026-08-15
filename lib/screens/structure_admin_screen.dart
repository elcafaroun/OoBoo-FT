import 'package:flutter/material.dart';
import 'package:fada/screens/user_list_screen.dart';
import 'package:shared_preferences/shared_preferences.dart'; // 👈 AJOUTÉ pour accéder aux SharedPreferences
import 'stock_alert_screen.dart';
import '../services/depense_service.dart';
import 'dashboard_screen.dart';
import 'add_category_screen.dart';

class StructureAdminScreen extends StatefulWidget {
  final String structureId;
  final String structureName;

  const StructureAdminScreen({
    super.key,
    required this.structureId,
    required this.structureName,
  });

  @override
  State<StructureAdminScreen> createState() => _StructureAdminScreenState();
}

class _StructureAdminScreenState extends State<StructureAdminScreen> {
  final DepenseService _depenseService = DepenseService();

  // 👈 AJOUTÉ : Informations de l'utilisateur connecté
  String _currentUserId = "admin_inconnu";
  String _currentUserName = "Administrateur";
  bool _isLoadingUser = true;

  @override
  void initState() {
    super.initState();
    _loadUserInfo(); // 👈 AJOUTÉ : Charger les informations au démarrage
  }

  // 👈 AJOUTÉ : Charger l'ID et le Nom depuis SharedPreferences
  Future<void> _loadUserInfo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _currentUserId = prefs.getString('userId') ?? 'admin_inconnu';
          _currentUserName = prefs.getString('userName') ?? 'Administrateur';
          _isLoadingUser = false;
        });
      }
    } catch (e) {
      debugPrint("⚠️ Erreur lors du chargement des infos de l'admin : $e");
      if (mounted) {
        setState(() => _isLoadingUser = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F7F2), // Fond très clair
      appBar: AppBar(
        title: Text(
          widget.structureName,
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
      body: _isLoadingUser
          ? const Center(child: CircularProgressIndicator(color: Colors.orange))
          : SingleChildScrollView(
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
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DashboardScreen(structureId: widget.structureId))),
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
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AddCategoryScreen(structureId: widget.structureId))),
            ),
            // Module Stock
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
          Text("Gérez les opérations de ${widget.structureName}", style: TextStyle(color: Colors.grey[600])),
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
                  // 👈 CONFIGURATION DU PAYLOAD AVEC LES INFOS DE L'AGENT CONNECTÉ
                  final depenseData = {
                    "codeStructure": widget.structureId,
                    "amount": amountController.text.trim(),
                    "intitule": titleController.text.trim(),
                    "dateDepense": selectedDate.toIso8601String().split('T')[0],
                    "userId": _currentUserId,       // ID unique
                    "userName": _currentUserName,   // Nom d'affichage
                    "createdBy": _currentUserId,     // 👈 Stocke bien l'ID de l'admin connecté
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