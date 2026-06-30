import 'package:flutter/material.dart';
import '../services/cat_service.dart';
import '../services/network_checker.dart'; // ✅ Intégration de ton service réseau
import 'category_products_screen.dart';
import 'structure_admin_screen.dart';

class StructureCategoriesScreen extends StatefulWidget {
  final String structureId;
  final String structureName;

  const StructureCategoriesScreen({
    super.key,
    required this.structureId,
    required this.structureName,
  });

  @override
  State<StructureCategoriesScreen> createState() => _StructureCategoriesScreenState();
}

class _StructureCategoriesScreenState extends State<StructureCategoriesScreen> {
  final CatService _catService = CatService();

  bool isLoading = true;
  bool isCheckingNetwork = false;
  bool isBackendAccessible = true;
  List<dynamic> categories = [];

  @override
  void initState() {
    super.initState();
    _checkNetworkAndLoad();
  }

  /// 🔹 Vérification réseau et chargement des catégories
  Future<void> _checkNetworkAndLoad() async {
    if (!mounted) return;
    setState(() {
      if (categories.isEmpty) {
        isLoading = true;
      } else {
        isCheckingNetwork = true;
      }
    });

    try {
      // ✅ Appel direct de ton service centralisé Actuator/Connectivity
      bool online = await NetworkChecker.isBackendAccessible();

      if (!online) {
        if (mounted) {
          setState(() {
            isBackendAccessible = false;
            isLoading = false;
            isCheckingNetwork = false;
          });
        }
        return;
      }

      if (mounted) {
        setState(() => isBackendAccessible = true);
      }
      await _loadCategories();
    } catch (e) {
      debugPrint("❌ Erreur réseau catégories : $e");
      if (mounted) {
        setState(() {
          isBackendAccessible = false;
          isLoading = false;
          isCheckingNetwork = false;
        });
      }
    }
  }

  Future<void> _loadCategories() async {
    try {
      final result = await _catService.getCategoriesByStructure(widget.structureId);
      if (mounted) {
        setState(() {
          categories = result ?? [];
          isLoading = false;
          isCheckingNetwork = false;
        });
      }
    } catch (e) {
      debugPrint("❌ Erreur chargement catégories : $e");
      if (mounted) {
        setState(() {
          isLoading = false;
          isCheckingNetwork = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Erreur de chargement des données"), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: isBackendAccessible ? const Color(0xFFF8FAFC) : Colors.white,
      appBar: AppBar(
        title: Text(
          isBackendAccessible ? 'Catégories ➔ ${widget.structureName}' : '',
          style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.3, fontSize: 16),
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1E293B),
        elevation: 0,
        centerTitle: false,
        leading: const BackButton(color: Colors.black87),
        actions: isBackendAccessible
            ? [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _checkNetworkAndLoad,
          )
        ]
            : null,
      ),
      floatingActionButton: (isBackendAccessible && !isLoading)
          ? FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => StructureAdminScreen(
                structureId: widget.structureId,
                structureName: widget.structureName,
              ),
            ),
          ).then((_) => _checkNetworkAndLoad());
        },
        backgroundColor: const Color(0xFFFF9800),
        elevation: 4,
        icon: const Icon(Icons.settings_rounded, color: Colors.white),
        label: const Text("GÉRER LA BOUTIQUE", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 0.5)),
      )
          : null,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: _buildCurrentState(),
      ),
    );
  }

  /// 🔹 Routeur d'états d'affichage
  Widget _buildCurrentState() {
    if (isLoading) {
      return const Center(
        key: ValueKey('loading_cats'),
        child: CircularProgressIndicator(color: Color(0xFFFF9800)),
      );
    }

    if (!isBackendAccessible) {
      return _buildOfflineView();
    }

    if (categories.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      key: const ValueKey('content_cats'),
      onRefresh: _checkNetworkAndLoad,
      color: const Color(0xFFFF9800),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) => _buildCategoryCard(categories[index]),
      ),
    );
  }

  /// 🛰️ 1. Vue Hors-ligne unifiée et propre
  Widget _buildOfflineView() {
    return SafeArea(
      key: const ValueKey('offline_cats'),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(color: Colors.red.shade50, shape: BoxShape.circle),
                child: Icon(Icons.wifi_off_rounded, size: 72, color: Colors.red.shade400),
              ),
              const SizedBox(height: 32),
              const Text(
                "Service déconnecté",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1E293B), letterSpacing: -0.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              const Text(
                "La gestion des catégories requiert une connexion en direct avec le serveur. Vérifiez votre réseau ou réessayez.",
                style: TextStyle(fontSize: 14, color: Color(0xFF64748B), height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: isCheckingNetwork ? null : _checkNetworkAndLoad,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF9800),
                    disabledBackgroundColor: Colors.orange.shade300,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  child: isCheckingNetwork
                      ? const SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                  )
                      : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.refresh_rounded, color: Colors.white),
                      SizedBox(width: 8),
                      Text("VÉRIFIER À NOUVEAU", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 0.5)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 📦 2. Vue Liste des Catégories (Moderne & Épurée)
  Widget _buildCategoryCard(dynamic cat) {
    final String? imageUrl = cat['categoryPhotoUrl'];
    final bool isActive = cat['active'] ?? true;

    return Opacity(
      opacity: isActive ? 1.0 : 0.6,
      child: Container(
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
            border: Border.all(color: isActive ? Colors.transparent : Colors.grey.shade200, width: 1)
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: _buildCategoryImage(imageUrl),
            title: Text(
              cat['nameCat'] ?? 'Sans nom',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1E293B)),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Text(
                cat['description'] ?? 'Pas de description',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
              ),
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CategoryProductsScreen(
                    categoryId: cat['id'].toString(),
                    categoryName: cat['nameCat'] ?? 'Produits',
                  ),
                ),
              );
            },
            trailing: PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded, color: Color(0xFFFF9800)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              onSelected: (value) {
                if (value == 'toggle') {
                  _toggleStatus(cat);
                } else if (value == 'edit') {
                  _showEditDialog(cat);
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'toggle',
                  child: Row(children: [
                    Icon(isActive ? Icons.block_rounded : Icons.check_circle_rounded,
                        size: 18, color: isActive ? Colors.red : Colors.green),
                    const SizedBox(width: 8),
                    Text(isActive ? "Désactiver" : "Activer"),
                  ]),
                ),
                const PopupMenuItem(
                  value: 'edit',
                  child: Row(children: [
                    Icon(Icons.edit_rounded, color: Colors.blue, size: 18),
                    const SizedBox(width: 8),
                    Text("Modifier"),
                  ]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showEditDialog(dynamic cat) {
    final TextEditingController nameController = TextEditingController(text: cat['nameCat']);
    final TextEditingController descController = TextEditingController(text: cat['description']);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Modifier la catégorie", style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: "Nom", labelStyle: TextStyle(color: Colors.grey)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descController,
              decoration: const InputDecoration(labelText: "Description", labelStyle: TextStyle(color: Colors.grey)),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Annuler", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF9800),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              try {
                await _catService.updateCategory(
                  categoryId: cat['id'].toString(),
                  name: nameController.text,
                  description: descController.text,
                  structureId: widget.structureId,
                );
                if (context.mounted) Navigator.pop(context);
                _checkNetworkAndLoad();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ Modifié avec succès !"), backgroundColor: Colors.green));
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Erreur modification"), backgroundColor: Colors.red));
                }
              }
            },
            child: const Text("Enregistrer", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _toggleStatus(dynamic cat) async {
    final bool currentStatus = cat['active'] ?? true;
    try {
      await _catService.updateStatus(categoryId: cat['id'].toString(), isActive: !currentStatus);
      _checkNetworkAndLoad();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Erreur mise à jour"), backgroundColor: Colors.red));
      }
    }
  }

  Widget _buildCategoryImage(String? imageUrl) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: const Color(0xFFFF9800).withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: (imageUrl != null && imageUrl.isNotEmpty && imageUrl.startsWith('http'))
            ? Image.network(
          imageUrl,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Icon(Icons.category_rounded, color: Color(0xFFFF9800)),
        )
            : const Icon(Icons.category_rounded, color: Color(0xFFFF9800), size: 24),
      ),
    );
  }

  /// 📭 3. Vue État Vide
  Widget _buildEmptyState() {
    return Center(
      key: const ValueKey('empty_cats'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.grey.shade100, shape: BoxShape.circle),
              child: Icon(Icons.inventory_2_outlined, size: 60, color: Colors.grey.shade400),
            ),
            const SizedBox(height: 24),
            const Text("Aucune catégorie trouvée", style: TextStyle(color: Color(0xFF1E293B), fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            const Text("Ajoutez des catégories depuis l'espace de gestion pour commencer.", textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF64748B), fontSize: 13)),
          ],
        ),
      ),
    );
  }
}