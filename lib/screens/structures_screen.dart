import 'package:fada/services/sync_service.dart';
import 'package:fada/widgets/product_image_widget.dart';
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
  final SyncService _syncService = SyncService();
  final DatabaseHelper _dbHelper = DatabaseHelper();

  List<dynamic> allStructures = [];
  bool isLoading = true;
  bool isRefreshing = false;
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

  Future<void> fetchStructures() async {
    if (!mounted) return;
    setState(() {
      if (allStructures.isEmpty) {
        isLoading = true;
      } else {
        isRefreshing = true;
      }
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final String? userId = prefs.getString('userId');

      if (userId == null) {
        if (mounted) setState(() => isLoading = false);
        return;
      }

      try {
        await _syncService.fullSynchronization("", userId);
      } catch (apiError) {
        debugPrint("🌐 Mode hors ligne (données locales utilisées) : $apiError");
      }

      final List<Map<String, dynamic>> rawData = await _dbHelper.getLocalStructuresByUser(userId);

      final filteredData = rawData.where((s) {
        final dynamic activeField = s['active'] ?? s['isActive'];
        return (activeField == true || activeField.toString() == '1' || activeField.toString().toLowerCase() == 'true');
      }).toList();

      if (mounted) {
        setState(() {
          allStructures = filteredData;
          isLoading = false;
          isRefreshing = false;
        });
      }
    } catch (e) {
      debugPrint("❌ Erreur critique structures : $e");
      if (mounted) {
        setState(() {
          isLoading = false;
          isRefreshing = false;
        });
      }
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
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text(
            "Nos Business",
            style: TextStyle(color: Color(0xFF1E293B), fontWeight: FontWeight.bold, letterSpacing: 0.3)
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.home_rounded, color: Color(0xFFFF9800), size: 26),
            onPressed: () => Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const HomeScreen()), (r) => false),
          ),
        ],
      ),
      // APPLICATION DU SAFE AREA ICI
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: _buildCurrentState(),
        ),
      ),
      floatingActionButton: canAccessAdmin
          ? FloatingActionButton.extended(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MonEspaceScreen())),
        label: const Text("Admin", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
        icon: const Icon(Icons.admin_panel_settings_rounded, color: Colors.white),
        backgroundColor: const Color(0xFFFF9800),
        elevation: 4,
      )
          : null,
    );
  }

  Widget _buildCurrentState() {
    if (isLoading) {
      return const Center(
        key: ValueKey('loading_structures'),
        child: CircularProgressIndicator(color: Color(0xFFFF9800)),
      );
    }

    if (allStructures.isEmpty) {
      return _buildEmptyState();
    }

    return Column(
      key: const ValueKey('content_structures'),
      children: [
        _buildHeader(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: fetchStructures,
            color: const Color(0xFFFF9800),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              itemCount: allStructures.length,
              separatorBuilder: (_, __) => const SizedBox(height: 16),
              itemBuilder: (context, index) => _buildStructureCard(allStructures[index]),
            ),
          ),
        ),
      ],
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
              Text("Bonjour,", style: TextStyle(color: Color(0xFF64748B), fontSize: 15)),
              SizedBox(height: 4),
              Text("Gorez vos espaces", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1E293B), letterSpacing: -0.5)),
            ],
          ),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFF9800).withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.business_center_rounded, color: Color(0xFFFF9800), size: 26),
          )
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      key: const ValueKey('empty_structures'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.grey.shade100, shape: BoxShape.circle),
              child: Icon(Icons.cloud_off_rounded, size: 64, color: Colors.grey.shade400),
            ),
            const SizedBox(height: 24),
            const Text("Aucun espace actif", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
            const SizedBox(height: 8),
            const Text("Aucune structure active n'a été trouvée pour votre compte actuellement.", textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF64748B), fontSize: 14, height: 1.4)),
            const SizedBox(height: 24),
            TextButton.icon(
              onPressed: isRefreshing ? null : fetchStructures,
              icon: isRefreshing
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Color(0xFFFF9800), strokeWidth: 2))
                  : const Icon(Icons.refresh_rounded, color: Color(0xFFFF9800)),
              label: Text(isRefreshing ? "Chargement..." : "Réessayer", style: const TextStyle(color: Color(0xFFFF9800), fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStructureCard(dynamic s) {
    final String localPath = s['photoPath'] ?? '';
    String photoUrl = s['structPhotoUrl'] ?? '';
    if (photoUrl.contains('localhost')) photoUrl = photoUrl.replaceAll('http://localhost:8080', baseUrl);

    return Container(
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 12, offset: const Offset(0, 4))]
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _saveAndNavigate(s),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: ProductImageWidget(
                    localPath: localPath,
                    networkUrl: photoUrl,
                    borderRadius: null,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s['nomStructure'] ?? 'Structure', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Color(0xFF1E293B), letterSpacing: 0.2)),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Icon(Icons.location_on_rounded, size: 14, color: Colors.grey.shade400),
                                const SizedBox(width: 4),
                                Text(s['villeStructure'] ?? 'Ville non précisée', style: const TextStyle(color: Color(0xFF64748B), fontSize: 13)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: const Color(0xFFFF9800).withOpacity(0.08), shape: BoxShape.circle),
                        child: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFFFF9800)),
                      )
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}