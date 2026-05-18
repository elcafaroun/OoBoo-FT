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

  /// Récupère les structures avec bascule automatique et filtrage par User
  Future<void> fetchStructures() async {
    if (!mounted) return;
    setState(() => isLoading = true);

    List<dynamic> rawData = [];

    try {
      final prefs = await SharedPreferences.getInstance();
      final String? profile = prefs.getString('userProfile');
      final String? userId = prefs.getString('userId');
      final String? codeStructure = prefs.getString('codeStructure');

      if (userId == null) {
        if (mounted) setState(() => isLoading = false);
        return;
      }

      // 1. TENTATIVE VIA API (BACKEND)
      try {
        if (profile == "Administrateur" && (codeStructure ?? '').isEmpty) {
          rawData = await _structureService.getStructuresByUser(userId);
        } else if (codeStructure != null && codeStructure.isNotEmpty) {
          rawData = await _structureService.getStructuresByCode(codeStructure);
        }

        // Si l'API répond, on synchronise.
        // Note: Votre syncStructuresLocal doit maintenant gérer le champ createdUserId
        if (rawData.isNotEmpty) {
          await _dbHelper.syncStructuresLocal(rawData);
        }
      } catch (apiError) {
        debugPrint("🌐 Backend injoignable, passage au mode local pour l'user $userId");
      }

      // 2. BASCULE (FALLBACK) : Recherche filtrée par USER ID dans SQLite
      if (rawData.isEmpty) {
        // Utilisation de la méthode filtrée pour ne pas avoir 0 si l'user est lié
        rawData = await _dbHelper.getLocalStructuresByUser(userId);
        debugPrint("📂 SQLite : ${rawData.length} structures trouvées pour l'utilisateur.");
      }

      // 3. LOGIQUE DE FILTRAGE (Status & Abonnement)
      final now = DateTime.now();
      final List<dynamic> filteredData = rawData.where((s) {
        // État actif
        final dynamic activeField = s['isActive'] ?? s['active'];
        final bool isActive = (activeField == true ||
            activeField.toString().toLowerCase() == 'true' ||
            activeField == 1);

        // Date de fin d'abonnement
        final String? endSubStr = s['endSub']?.toString();

        if (endSubStr == null || endSubStr.isEmpty) {
          return isActive; // En local, si l'info manque, on laisse passer
        }

        try {
          final DateTime endSub = DateTime.parse(endSubStr);
          return isActive && endSub.isAfter(now);
        } catch (e) {
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
      debugPrint("❌ Erreur critique StructuresScreen : $e");
      if (mounted) setState(() => isLoading = false);
    }
  }

  // --- Reste du code (UI et Navigation) identique à votre version ---

  Future<void> _saveAndNavigate(dynamic structure) async {
    final prefs = await SharedPreferences.getInstance();
    // Support idStructure (Backend) ou id (SQLite)
    final idStr = (structure['idStructure'] ?? structure['id']).toString();
    debugPrint("❌ ID STRUCTURE : " + idStr);
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
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text("Vos Structures",
            style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.black87),
        actions: [
          IconButton(
            icon: const Icon(Icons.home_rounded, color: Color(0xFFFF9800)),
            onPressed: () => Navigator.pushAndRemoveUntil(
                context, MaterialPageRoute(builder: (_) => const HomeScreen()), (r) => false),
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
                separatorBuilder: (c, i) => const SizedBox(height: 16),
                itemBuilder: (context, index) => _buildStructureCard(allStructures[index]),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: userProfile == "Administrateur"
          ? FloatingActionButton.extended(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MonEspaceScreen())),
        label: const Text("Admin", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        icon: const Icon(Icons.admin_panel_settings, color: Colors.white),
        backgroundColor: const Color(0xFFFF9800),
      )
          : null,
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Bonjour,", style: TextStyle(color: Colors.grey, fontSize: 16)),
              Text("Gérez vos espaces", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            ],
          ),
          CircleAvatar(
            backgroundColor: const Color(0xFFFF9800).withOpacity(0.1),
            child: const Icon(Icons.business_center, color: Color(0xFFFF9800)),
          )
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_off, size: 60, color: Colors.grey[300]),
          const SizedBox(height: 10),
          const Text("Aucune structure disponible.", style: TextStyle(color: Colors.grey)),
          TextButton(
              onPressed: fetchStructures,
              child: const Text("Réessayer", style: TextStyle(color: Color(0xFFFF9800)))
          )
        ],
      ),
    );
  }

  Widget _buildStructureCard(dynamic s) {
    String photoUrl = s['photoPath'] ?? s['structPhotoUrl'] ?? '';
    if (photoUrl.contains('localhost')) photoUrl = photoUrl.replaceAll('http://localhost:8080', baseUrl);

    return InkWell(
      onTap: () => _saveAndNavigate(s),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Column(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: photoUrl.isNotEmpty && photoUrl.startsWith('http')
                    ? Image.network(photoUrl, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _defaultImage())
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
                        Text(s['nomStructure'] ?? 'Structure',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.location_on_outlined, size: 14, color: Colors.grey),
                            const SizedBox(width: 4),
                            Text(s['villeStructure'] ?? 'Ville non précisée',
                                style: const TextStyle(color: Colors.grey, fontSize: 14)),
                          ],
                        ),
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