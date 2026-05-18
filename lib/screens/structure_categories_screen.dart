import 'package:flutter/material.dart';
import '../services/cat_service.dart';
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
  List<dynamic> categories = [];

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      final result = await _catService.getCategoriesByStructure(widget.structureId);
      if (mounted) {
        setState(() {
          categories = result ?? [];
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Erreur de chargement")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Text('Categories ➔ ${widget.structureName}',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        centerTitle: false,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF9800)))
          : categories.isEmpty
          ? _buildEmptyState()
          : ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 20),
        itemCount: categories.length,
        // Séparateur entre les lignes
        separatorBuilder: (_, __) => const Divider(
          height: 1, thickness: 1, color: Colors.black12, indent: 20, endIndent: 20,
        ),
        itemBuilder: (context, index) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _buildCategoryCard(categories[index]),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => StructureAdminScreen(
                structureId: widget.structureId,
                structureName: widget.structureName,
              ),
            ),
          ).then((_) => _loadCategories());
        },
        backgroundColor: const Color(0xFFFF9800),
        icon: const Icon(Icons.settings, color: Colors.white),
        label: const Text("Gérer la boutique", style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildCategoryCard(dynamic cat) {
    final String? imageUrl = cat['categoryPhotoUrl'];
    final bool isActive = cat['active'] ?? true;

    return Opacity(
      opacity: isActive ? 1.0 : 0.6,
      child: Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          leading: _buildCategoryImage(imageUrl),
          title: Text(
            cat['nameCat'] ?? 'Sans nom',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          subtitle: Text(
            cat['description'] ?? 'Pas de description',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          // Navigation activée
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
          // Menu contextuel
          trailing: PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.orange),
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
                  Icon(isActive ? Icons.block : Icons.check_circle,
                      size: 18, color: isActive ? Colors.red : Colors.green),
                  const SizedBox(width: 8),
                  Text(isActive ? "Désactiver" : "Activer"),
                ]),
              ),
              const PopupMenuItem(
                value: 'edit',
                child: Row(children: [
                  Icon(Icons.edit, color: Colors.blue, size: 18),
                  const SizedBox(width: 8),
                  Text("Modifier"),
                ]),
              ),
            ],
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
        title: const Text("Modifier la catégorie"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameController, decoration: const InputDecoration(labelText: "Nom")),
            const SizedBox(height: 10),
            TextField(controller: descController, decoration: const InputDecoration(labelText: "Description")),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Annuler")),
          ElevatedButton(
            onPressed: () async {
              try {
                await _catService.updateCategory(
                  categoryId: cat['id'].toString(),
                  name: nameController.text,
                  description: descController.text,
                  structureId: widget.structureId,
                );
                Navigator.pop(context);
                _loadCategories();
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Modifié avec succès")));
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Erreur modification")));
              }
            },
            child: const Text("Enregistrer"),
          ),
        ],
      ),
    );
  }

  void _toggleStatus(dynamic cat) async {
    final bool currentStatus = cat['active'] ?? true;
    try {
      await _catService.updateStatus(categoryId: cat['id'].toString(), isActive: !currentStatus);
      _loadCategories();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Erreur mise à jour")));
    }
  }

  Widget _buildCategoryImage(String? imageUrl) {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: (imageUrl != null && imageUrl.isNotEmpty)
            ? Image.network(
          imageUrl,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Icon(Icons.category, color: Color(0xFFFF9800)),
        )
            : const Icon(Icons.category, color: Color(0xFFFF9800), size: 24),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2_outlined, size: 60, color: Colors.grey[400]),
          const SizedBox(height: 16),
          const Text("Aucune catégorie trouvée", style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}