import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/structure_service.dart';
import '../models/subscription_plan.dart';
import 'structure_categories_screen.dart';
import 'subscription_screen.dart';

class MonEspaceScreen extends StatefulWidget {
  const MonEspaceScreen({super.key});

  @override
  State<MonEspaceScreen> createState() => _MonEspaceScreenState();
}

class _MonEspaceScreenState extends State<MonEspaceScreen> {
  final StructureService _structureService = StructureService();
  bool isLoading = true;
  List<dynamic> userStructures = [];

  @override
  void initState() {
    super.initState();
    _loadStructures();
  }

  Future<void> _loadStructures() async {
    if (!mounted) return;
    setState(() => isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    final String? userId = prefs.getString('userId');
    final String? codeStructure = prefs.getString('codeStructure');

    if (userId != null) {
      if ((codeStructure ?? '').isEmpty) {
        final result = await _structureService.getStructuresByUser(userId);
        if (mounted)
          setState(() {
            userStructures = result;
            isLoading = false;
          });
      } else {
        if ((codeStructure ?? '').isNotEmpty) {
          final result = await _structureService.getStructuresByCode(codeStructure!);
          if (mounted)
            setState(() {
              userStructures = result;
              isLoading = false;
            });
        }
      }
    } else {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _handleSubscriptionAction(dynamic s, bool isExpired) async {
    final String structureId =
        (s['id'] ?? s['structureId'] ?? s['idStructure']).toString();
    final int currentPriorite =
        int.tryParse(s['priorite']?.toString() ?? '0') ?? 0;

    final SubscriptionPlan? selectedPlan = await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => SubscriptionScreen(filterPriorite: currentPriorite)),
    );

    if (selectedPlan != null) {
      setState(() => isLoading = true);
      try {
        await _structureService.updateStructurePlan(
            structureId, selectedPlan.name);
        _loadStructures();
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("✅ Mise à jour effectuée !")));
      } catch (e) {
        if (mounted)
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text("Erreur : $e")));
      } finally {
        if (mounted) setState(() => isLoading = false);
      }
    }
  }

  bool _isExpired(dynamic s) {
    if (s['cout'] != null && (s['cout'] == 0.0 || s['cout'] == 0)) return false;
    if (s['endSub'] == null) return true;
    try {
      DateTime endDate = DateTime.parse(s['endSub'].toString());
      return DateTime.now().isAfter(endDate);
    } catch (e) {
      return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F4F4),
      appBar: AppBar(
        title: const Text("ADMINISTRATION",
            style: TextStyle(fontWeight: FontWeight.w900)),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFFFF9800),
        onPressed: () async {
          await Navigator.push(context,
              MaterialPageRoute(builder: (_) => const SubscriptionScreen()));
          _loadStructures();
        },
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF9800)))
          : Column(
              children: [
                _buildHeaderStats(),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: userStructures.length,
                    itemBuilder: (context, index) =>
                        _buildProCard(userStructures[index]),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildHeaderStats() {
    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: const Color(0xFFFF9800),
          borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text("TOTAL STRUCTURES",
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          Text("${userStructures.length}",
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  Widget _buildProCard(dynamic s) {
    final id = (s['id'] ?? s['structureId'] ?? s['idStructure']).toString();
    final name = s['nomStructure'] ?? 'Structure';
    final bool expired = _isExpired(s);
    final bool isFree =
        s['cout'] != null && (s['cout'] == 0.0 || s['cout'] == 0);

    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: isFree
                ? Colors.green
                : (expired ? Colors.red.shade200 : Colors.blue.shade200)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        children: [
          // InkWell encapsule uniquement le haut pour la navigation
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
              onTap: () async {
                // <--- Ajout de async ici
                // 1. Extraire les variables nécessaires depuis l'objet 's'
                final SharedPreferences prefs =
                    await SharedPreferences.getInstance();
                final String id =
                    (s['id'] ?? s['structureId'] ?? s['idStructure'])
                        .toString();
                final String name = s['nomStructure'] ?? 'Structure';
                await prefs.setString('selected_structure_id', id);

                // 2. Vérification de sécurité (bonne pratique Flutter)
                if (!context.mounted) return;

                // 3. Passer les variables séparément
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => StructureCategoriesScreen(
                      structureId: id,
                      structureName: name,
                    ),
                  ),
                );
              },
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: isFree
                      ? Colors.green.shade50
                      : (expired ? Colors.red.shade50 : Colors.blue.shade50),
                  child: Icon(isFree ? Icons.star : Icons.business,
                      color: isFree
                          ? Colors.green
                          : (expired ? Colors.red : Colors.blue)),
                ),
                title: Text(name.toUpperCase(),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(expired ? "EXPIRÉ" : "ACTIF",
                    style: TextStyle(
                        color: expired ? Colors.red : Colors.green,
                        fontWeight: FontWeight.w600)),
                trailing: const Icon(Icons.chevron_right, color: Colors.grey),
              ),
            ),
          ),
          const Divider(height: 1),
          // Boutons du bas inchangés
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: () => _handleSubscriptionAction(s, expired),
                  icon: const Icon(Icons.autorenew, size: 16),
                  label: const Text("GÉRER"),
                ),
                TextButton.icon(
                  onPressed: () {/* Action edit */},
                  icon: const Icon(Icons.edit, size: 16),
                  label: const Text("EDIT"),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => _structureService
                      .deleteStructure(id)
                      .then((_) => _loadStructures()),
                  icon: const Icon(Icons.delete_outline,
                      color: Colors.red, size: 20),
                )
              ],
            ),
          )
        ],
      ),
    );
  }
}
