import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/structure_service.dart';
import '../services/database/database_helper.dart';
import '../utils/constants.dart';
import 'categories_screen.dart';
import 'mon_espace_screen.dart';
import 'home_screen.dart';

class StructuresScreen extends StatefulWidget {
  const StructuresScreen({super.key});

  @override
  State<StructuresScreen> createState() => _StructuresScreenState();
}

class _StructuresScreenState extends State<StructuresScreen> {
  final StructureService _structureService = StructureService();
  final DatabaseHelper _dbHelper = DatabaseHelper();

  List<dynamic> allStructures = [];
  bool isLoading = true;
  String? userProfile;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => userProfile = prefs.getString('userProfile'));
    }
    await fetchStructures();
  }

  /// 🔹 Récupère les structures via l'API et synchronise en local
  Future<void> fetchStructures() async {
    if (!mounted) return;
    setState(() => isLoading = true);

    List<dynamic> rawData = [];

    try {
      final prefs = await SharedPreferences.getInstance();
      final String? userId = prefs.getString('userId');

      if (userId == null) {
        debugPrint("⚠️ Aucun userId trouvé.");
        if (mounted) setState(() => isLoading = false);
        return;
      }

      // 1️⃣ Tentative API (Endpoint sécurisé par userId)
      try {
        rawData = await _structureService.getStructuresByUser(userId);
        if (rawData.isNotEmpty) {
          await _dbHelper.syncStructuresLocal(rawData);
        }
      } catch (apiError) {
        debugPrint("🌐 Backend injoignable, passage en mode local : $apiError");
      }

      // 2️⃣ Fallback SQLite si API échoue ou vide
      if (rawData.isEmpty) {
        rawData = await _dbHelper.getLocalStructuresByUser(userId);
      }

      // 3️⃣ Filtrage (Actif et abonnement valide)
      final now = DateTime.now();
      final filteredData = rawData.where((s) {
        final dynamic activeField = s['active'] ?? s['isActive'];
        final bool isActive = (activeField == true || activeField.toString() == '1' || activeField.toString().toLowerCase() == 'true');

        final String? endSubStr = s['endSub']?.toString();
        if (endSubStr == null || endSubStr.isEmpty) return isActive;

        try {
          final DateTime endSub = DateTime.parse(endSubStr);
          return isActive && endSub.isAfter(now);
        } catch (_) {
          return isActive;
        }
      }).toList();

      if (mounted) {
        setState(() {
          allStructures = filteredData;
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("❌ Erreur critique : $e");
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _saveAndNavigate(dynamic structure) async {
    final prefs = await SharedPreferences.getInstance();
    final idStr = (structure['idStructure'] ?? structure['id']).toString();

    await prefs.setString('selected_structure_id', idStr);
    await prefs.setString('selected_structure_name', structure['nomStructure'] ?? 'Inconnu');
    await prefs.setString('codeStructure', structure['codeStructure'] ?? '');

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CategoriesScreen(
            structureId: idStr,
            structureName: structure['nomStructure'] ?? 'Inconnu',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool canAccessAdmin = userProfile == "Administrateur" || userProfile == "Super admin";

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text("Nos Business", style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.home_rounded, color: Color(0xFFFF9800)),
            onPressed: () => Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const HomeScreen()), (r) => false),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF9800)))
                : allStructures.isEmpty
                ? _buildEmptyState()
                : RefreshIndicator(
              onRefresh: fetchStructures,
              color: const Color(0xFFFF9800),
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                itemCount: allStructures.length,
                separatorBuilder: (_, __) => const SizedBox(height: 16),
                itemBuilder: (context, index) => _buildStructureCard(allStructures[index]),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: canAccessAdmin
          ? FloatingActionButton.extended(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MonEspaceScreen())),
        label: const Text("Admin", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        icon: const Icon(Icons.admin_panel_settings, color: Colors.white),
        backgroundColor: const Color(0xFFFF9800),
      )
          : null,
    );
  }

  Widget _buildHeader() => const Padding(
    padding: EdgeInsets.all(20.0),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Bonjour,", style: TextStyle(color: Colors.grey, fontSize: 16)),
            Text("Gérez vos espaces", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          ],
        ),
        CircleAvatar(backgroundColor: Color(0x1AFFFF98), child: Icon(Icons.business_center, color: Color(0xFFFF9800)))
      ],
    ),
  );

  Widget _buildEmptyState() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.cloud_off, size: 60, color: Colors.grey[300]),
        const Text("Aucune structure active trouvée.", style: TextStyle(color: Colors.grey)),
        TextButton(onPressed: fetchStructures, child: const Text("Réessayer", style: TextStyle(color: Color(0xFFFF9800)))),
      ],
    ),
  );

  Widget _buildStructureCard(dynamic s) {
    String photoUrl = s['photoPath'] ?? s['structPhotoUrl'] ?? '';
    if (photoUrl.contains('localhost')) photoUrl = photoUrl.replaceAll('http://localhost:8080', baseUrl);

    return InkWell(
      onTap: () => _saveAndNavigate(s),
      child: Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))]),
        child: Column(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: photoUrl.isNotEmpty && photoUrl.startsWith('http')
                    ? Image.network(photoUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _defaultImage())
                    : _defaultImage(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s['nomStructure'] ?? 'Structure', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                        const SizedBox(height: 4),
                        Text(s['villeStructure'] ?? 'Ville non précisée', style: const TextStyle(color: Colors.grey, fontSize: 14)),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios, size: 16, color: Color(0xFFFF9800))
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _defaultImage() => Container(color: Colors.grey[100], child: const Icon(Icons.business, color: Colors.grey, size: 40));
}