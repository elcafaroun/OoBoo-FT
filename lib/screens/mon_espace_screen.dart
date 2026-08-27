import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import '../services/structure_service.dart';
import '../services/network_checker.dart';
import '../services/sync_service.dart';
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
  final SyncService _syncService = SyncService();
  final ImagePicker _picker = ImagePicker();
  bool isLoading = true;
  bool isCheckingNetwork = false;
  bool isBackendAccessible = true;
  List<dynamic> userStructures = [];

  @override
  void initState() {
    super.initState();
    _checkNetworkAndLoad();
  }

  /// Déclenche la synchronisation globale complète (Queue + Profil + Tables connexes)
  Future<void> _triggerFullSync() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? userId = prefs.getString('userId');

      if (userId != null && userId.isNotEmpty) {
        debugPrint("🚀 Déclenchement de la synchronisation globale depuis Mon Espace...");
        await _syncService.fullSynchronization(userId);
      } else {
        debugPrint("⚠️ Impossible de synchroniser : aucun userId trouvé.");
      }
    } catch (e) {
      debugPrint("❌ Erreur lors de la synchronisation : $e");
    }
  }

  Future<void> _checkNetworkAndLoad() async {
    if (!mounted) return;
    setState(() {
      isLoading = true;
      isCheckingNetwork = true;
    });

    try {
      bool online = await NetworkChecker.isBackendAccessible();
      if (mounted) {
        setState(() => isBackendAccessible = online);
      }
      if (online) {
        await _loadStructures();
      }
    } catch (e) {
      debugPrint(" Erreur lors de la vérification réseau : $e");
      if (mounted) {
        setState(() => isBackendAccessible = false);
      }
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
          isCheckingNetwork = false;
        });
      }
    }
  }

  Future<void> _loadStructures() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? userId = prefs.getString('userId');
      if (userId != null) {
        List<dynamic> result =
        await _structureService.getStructuresByUser(userId);
        if (mounted) {
          setState(() {
            userStructures = result;
          });
        }
      }
    } catch (e) {
      debugPrint(" Erreur de chargement des structures : $e");
    }
  }

  Future<void> _navigateToAdmin(dynamic s) async {
    final prefs = await SharedPreferences.getInstance();
    final String id =
    (s['idStructure'] ?? s['id'] ?? s['structureId'] ?? '').toString();
    final String nom = s['nomStructure'] ?? s['nom'] ?? 'Structure';

    await prefs.setString('selected_structure_id', id);
    await prefs.setString('selected_structure_name', nom);
    await prefs.setString(
        'codeStructure', s['codeStructure'] ?? s['code'] ?? '');
    await prefs.reload();

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StructureCategoriesScreen(
          structureId: id,
          structureName: nom,
        ),
      ),
    );
  }

  bool _isExpired(dynamic s) {
    if (s['cout'] != null && (s['cout'] == 0.0 || s['cout'] == 0)) return false;
    if (s['endSub'] == null) return true;
    try {
      return DateTime.now().isAfter(DateTime.parse(s['endSub'].toString()));
    } catch (_) {
      return true;
    }
  }

  String _parseLabel(dynamic item) {
    if (item == null) return '';
    if (item is Map) {
      return (item['nom_type'] ??
          item['nom_ville'] ??
          item['nomType'] ??
          item['nomVille'] ??
          item['libelle'] ??
          item['nom'] ??
          item['designation'] ??
          item['name'] ??
          item['label'] ??
          '')
          .toString()
          .trim();
    }
    return item.toString().trim();
  }

  Future<bool> _submitStructureUpdate({
    required String id,
    required Map<String, dynamic> updatedStructure,
    File? imageFile,
  }) async {
    try {
      bool success = await _structureService.updateStructure(
        id,
        updatedStructure,
        imageFile: imageFile,
      );
      return success;
    } catch (_) {
      return false;
    }
  }

  Future<void> _showEditDialog(dynamic s) async {
    final String id =
    (s['idStructure'] ?? s['id'] ?? s['structureId'] ?? '').toString();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: Color(0xFFFF9800)),
      ),
    );

    List<dynamic> rawTypes = [];
    List<dynamic> rawVilles = [];

    try {
      final results = await Future.wait([
        _structureService.getAllTypeStructures(),
        _structureService.getAllVilleStructures(),
      ]);
      rawTypes = results[0] ?? [];
      rawVilles = results[1] ?? [];
    } catch (e) {
      debugPrint(" Erreur chargement listes types/villes : $e");
    } finally {
      if (mounted) Navigator.pop(context);
    }

    List<String> typesList = rawTypes
        .map((e) => _parseLabel(e))
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();

    List<String> villesList = rawVilles
        .map((e) => _parseLabel(e))
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();

    String extraireValeur(List<String> cles) {
      for (String cle in cles) {
        if (s[cle] != null) {
          return _parseLabel(s[cle]);
        }
      }
      return '';
    }

    final String nomParDefaut =
    extraireValeur(['nomStructure', 'nom', 'nom_structure']);
    final String typeParDefaut = extraireValeur(
        ['typeStructure', 'nom_type', 'nomType', 'type', 'type_structure']);
    final String descParDefaut = extraireValeur(
        ['descriptionStructure', 'descStructure', 'description', 'desc']);
    final String villeParDefaut = extraireValeur([
      'villeStructure',
      'nom_ville',
      'nomVille',
      'ville',
      'ville_structure'
    ]);
    final String cpParDefaut =
    extraireValeur(['codePoste', 'cp', 'codePostal', 'code_postal']);
    final String rueParDefaut =
    extraireValeur(['rueStructure', 'adresseStructure', 'adresse', 'rue']);
    final String gpsParDefaut = extraireValeur(
        ['geoLocStructure', 'gps', 'coordonnees', 'gpsStructure']);

    String? currentPhotoPath = extraireValeur([
      'structPhotoUrl',
      'photoStructure',
      'photo',
      'photo_structure',
      'logo',
      'image',
      'photoPath'
    ]);
    if ((currentPhotoPath?.isEmpty ?? true) || currentPhotoPath == "null") {
      currentPhotoPath = null;
    }

    final TextEditingController nomController =
    TextEditingController(text: nomParDefaut);
    final TextEditingController descController =
    TextEditingController(text: descParDefaut);
    final TextEditingController cpController =
    TextEditingController(text: cpParDefaut);
    final TextEditingController rueController =
    TextEditingController(text: rueParDefaut);
    final TextEditingController gpsController =
    TextEditingController(text: gpsParDefaut);

    String? selectedType = typeParDefaut.isNotEmpty ? typeParDefaut : null;
    String? selectedVille = villeParDefaut.isNotEmpty ? villeParDefaut : null;

    if (selectedType != null &&
        selectedType.isNotEmpty &&
        !typesList.contains(selectedType)) {
      typesList.add(selectedType);
    }
    if (selectedVille != null &&
        selectedVille.isNotEmpty &&
        !villesList.contains(selectedVille)) {
      villesList.add(selectedVille);
    }

    File? selectedNewImage;
    final formKey = GlobalKey<FormState>();

    if (!mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            Future<void> pickImage() async {
              try {
                final XFile? pickedFile = await _picker.pickImage(
                  source: ImageSource.gallery,
                  imageQuality: 80,
                );
                if (pickedFile != null) {
                  setStateDialog(() {
                    selectedNewImage = File(pickedFile.path);
                  });
                }
              } catch (e) {
                debugPrint("Erreur de sélection d'image : $e");
              }
            }

            Widget buildPhotoWidget() {
              return Center(
                child: Stack(
                  children: [
                    Container(
                      height: 140,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(16),
                        border:
                        Border.all(color: Colors.grey.shade300, width: 1.5),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(15),
                        child: selectedNewImage != null
                            ? Image.file(
                          selectedNewImage!,
                          key: ValueKey(selectedNewImage!.path +
                              DateTime.now().toString()),
                          fit: BoxFit.cover,
                        )
                            : (currentPhotoPath != null &&
                            currentPhotoPath!.isNotEmpty)
                            ? (currentPhotoPath!.startsWith('http')
                            ? Image.network(
                          "$currentPhotoPath?t=${DateTime.now().millisecondsSinceEpoch}",
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                          const Icon(Icons.broken_image,
                              size: 40, color: Colors.grey),
                        )
                            : (File(currentPhotoPath!).existsSync()
                            ? Image.file(
                          File(currentPhotoPath!),
                          key: ValueKey(currentPhotoPath! +
                              (File(currentPhotoPath!)
                                  .existsSync()
                                  ? File(currentPhotoPath!)
                                  .lastModifiedSync()
                                  .toString()
                                  : '')),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                          const Icon(
                              Icons.image_not_supported,
                              color: Colors.grey),
                        )
                            : const Icon(Icons.image_not_supported,
                            size: 40, color: Colors.grey)))
                            : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.add_a_photo_outlined,
                                size: 36, color: Color(0xFFFF9800)),
                            SizedBox(height: 6),
                            Text("Ajouter une photo",
                                style: TextStyle(
                                    color: Colors.grey,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13)),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF9800),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 4,
                                offset: const Offset(0, 2))
                          ],
                        ),
                        child: const Icon(Icons.camera_alt,
                            color: Colors.white, size: 18),
                      ),
                    )
                  ],
                ),
              );
            }

            return Dialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24)),
              elevation: 0,
              backgroundColor: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.all(24),
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.85),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 20,
                        offset: const Offset(0, 10))
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF9800).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.edit_rounded,
                              color: Color(0xFFFF9800), size: 24),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Modifier la structure",
                                style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 18,
                                    color: Colors.black87),
                              ),
                              SizedBox(height: 2),
                              Text(
                                "Mettez à jour les informations de votre structure",
                                style:
                                TextStyle(color: Colors.grey, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.grey),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const Divider(height: 28),
                    Expanded(
                      child: Form(
                        key: formKey,
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              InkWell(
                                onTap: pickImage,
                                borderRadius: BorderRadius.circular(16),
                                child: buildPhotoWidget(),
                              ),
                              const SizedBox(height: 20),
                              TextFormField(
                                controller: nomController,
                                decoration: InputDecoration(
                                  labelText: "Nom de la structure *",
                                  prefixIcon: const Icon(
                                      Icons.storefront_rounded,
                                      color: Color(0xFFFF9800)),
                                  filled: true,
                                  fillColor:
                                  Colors.grey.shade50.withOpacity(0.5),
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                          color: Colors.grey.shade300)),
                                  enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                          color: Colors.grey.shade300)),
                                  focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: const BorderSide(
                                          color: Color(0xFFFF9800), width: 2)),
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return "Le nom est requis";
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              DropdownButtonFormField<String>(
                                value: typesList.contains(selectedType)
                                    ? selectedType
                                    : null,
                                isExpanded: true,
                                hint: const Text("Sélectionnez le type"),
                                decoration: InputDecoration(
                                  labelText: "Type de structure",
                                  prefixIcon: const Icon(Icons.category_rounded,
                                      color: Color(0xFFFF9800)),
                                  filled: true,
                                  fillColor:
                                  Colors.grey.shade50.withOpacity(0.5),
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                          color: Colors.grey.shade300)),
                                  enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                          color: Colors.grey.shade300)),
                                  focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: const BorderSide(
                                          color: Color(0xFFFF9800), width: 2)),
                                ),
                                items: typesList.map((String type) {
                                  return DropdownMenuItem<String>(
                                    value: type,
                                    child: Text(type,
                                        overflow: TextOverflow.ellipsis),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  setStateDialog(() {
                                    selectedType = val;
                                  });
                                },
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: descController,
                                maxLines: 3,
                                decoration: InputDecoration(
                                  labelText: "Description",
                                  alignLabelWithHint: true,
                                  prefixIcon: const Padding(
                                    padding: EdgeInsets.only(bottom: 40.0),
                                    child: Icon(Icons.description_rounded,
                                        color: Color(0xFFFF9800)),
                                  ),
                                  filled: true,
                                  fillColor:
                                  Colors.grey.shade50.withOpacity(0.5),
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                          color: Colors.grey.shade300)),
                                  enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                          color: Colors.grey.shade300)),
                                  focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: const BorderSide(
                                          color: Color(0xFFFF9800), width: 2)),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: DropdownButtonFormField<String>(
                                      value: villesList.contains(selectedVille)
                                          ? selectedVille
                                          : null,
                                      isExpanded: true,
                                      hint: const Text("Ville"),
                                      decoration: InputDecoration(
                                        labelText: "Ville",
                                        prefixIcon: const Icon(
                                            Icons.location_city_rounded,
                                            color: Color(0xFFFF9800)),
                                        filled: true,
                                        fillColor: Colors.grey.shade50
                                            .withOpacity(0.5),
                                        border: OutlineInputBorder(
                                            borderRadius:
                                            BorderRadius.circular(12),
                                            borderSide: BorderSide(
                                                color: Colors.grey.shade300)),
                                        enabledBorder: OutlineInputBorder(
                                            borderRadius:
                                            BorderRadius.circular(12),
                                            borderSide: BorderSide(
                                                color: Colors.grey.shade300)),
                                        focusedBorder: OutlineInputBorder(
                                            borderRadius:
                                            BorderRadius.circular(12),
                                            borderSide: const BorderSide(
                                                color: Color(0xFFFF9800),
                                                width: 2)),
                                      ),
                                      items: villesList.map((String ville) {
                                        return DropdownMenuItem<String>(
                                          value: ville,
                                          child: Text(ville,
                                              overflow: TextOverflow.ellipsis),
                                        );
                                      }).toList(),
                                      onChanged: (val) {
                                        setStateDialog(() {
                                          selectedVille = val;
                                        });
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    flex: 2,
                                    child: TextFormField(
                                      controller: cpController,
                                      keyboardType: TextInputType.text,
                                      decoration: InputDecoration(
                                        labelText: "C. Postal",
                                        prefixIcon: const Icon(
                                            Icons.markunread_mailbox_rounded,
                                            color: Color(0xFFFF9800)),
                                        filled: true,
                                        fillColor: Colors.grey.shade50
                                            .withOpacity(0.5),
                                        border: OutlineInputBorder(
                                            borderRadius:
                                            BorderRadius.circular(12),
                                            borderSide: BorderSide(
                                                color: Colors.grey.shade300)),
                                        enabledBorder: OutlineInputBorder(
                                            borderRadius:
                                            BorderRadius.circular(12),
                                            borderSide: BorderSide(
                                                color: Colors.grey.shade300)),
                                        focusedBorder: OutlineInputBorder(
                                            borderRadius:
                                            BorderRadius.circular(12),
                                            borderSide: const BorderSide(
                                                color: Color(0xFFFF9800),
                                                width: 2)),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: rueController,
                                decoration: InputDecoration(
                                  labelText: "Rue / Adresse",
                                  prefixIcon: const Icon(Icons.map_rounded,
                                      color: Color(0xFFFF9800)),
                                  filled: true,
                                  fillColor:
                                  Colors.grey.shade50.withOpacity(0.5),
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                          color: Colors.grey.shade300)),
                                  enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                          color: Colors.grey.shade300)),
                                  focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: const BorderSide(
                                          color: Color(0xFFFF9800), width: 2)),
                                ),
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: gpsController,
                                decoration: InputDecoration(
                                  labelText: "GPS / Géolocalisation",
                                  prefixIcon: const Icon(
                                      Icons.gps_fixed_rounded,
                                      color: Color(0xFFFF9800)),
                                  suffixIcon: const Icon(
                                      Icons.my_location_rounded,
                                      color: Colors.grey),
                                  filled: true,
                                  fillColor:
                                  Colors.grey.shade50.withOpacity(0.5),
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                          color: Colors.grey.shade300)),
                                  enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                          color: Colors.grey.shade300)),
                                  focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: const BorderSide(
                                          color: Color(0xFFFF9800), width: 2)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              side: BorderSide(color: Colors.grey.shade300),
                            ),
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text("Annuler",
                                style: TextStyle(
                                    color: Colors.grey,
                                    fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFF9800),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              elevation: 0,
                            ),
                            onPressed: () async {
                              if (!formKey.currentState!.validate()) return;

                              showDialog(
                                context: context,
                                barrierDismissible: false,
                                builder: (_) => const Center(
                                  child: CircularProgressIndicator(
                                      color: Color(0xFFFF9800)),
                                ),
                              );

                              Map<String, dynamic> updatedStructure =
                              Map<String, dynamic>.from(s);
                              updatedStructure['nomStructure'] =
                                  nomController.text.trim();
                              updatedStructure['typeStructure'] =
                                  selectedType ?? '';
                              updatedStructure['descriptionStructure'] =
                                  descController.text.trim();
                              updatedStructure['villeStructure'] =
                                  selectedVille ?? '';
                              updatedStructure['codePoste'] =
                                  cpController.text.trim();
                              updatedStructure['rueStructure'] =
                                  rueController.text.trim();
                              updatedStructure['geoLocStructure'] =
                                  gpsController.text.trim();

                              if (selectedNewImage != null) {
                                updatedStructure['structPhotoUrl'] =
                                    selectedNewImage!.path;
                              }

                              bool success = await _submitStructureUpdate(
                                id: id,
                                updatedStructure: updatedStructure,
                                imageFile: selectedNewImage,
                              );

                              if (mounted) {
                                Navigator.pop(context); // Masquer le loader
                                if (success) {
                                  Navigator.pop(ctx); // Fermer la boîte de dialogue

                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                          "Structure mise à jour ! Synchronisation en cours..."),
                                      backgroundColor: Colors.green,
                                    ),
                                  );

                                  // 🚀 Lancement de la synchronisation globale
                                  await _triggerFullSync();

                                  _checkNetworkAndLoad();
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text("Échec de la mise à jour"),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              }
                            },
                            child: const Text("Enregistrer",
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _handleMenuAction(String value, dynamic s) async {
    final String id =
    (s['idStructure'] ?? s['id'] ?? s['structureId'] ?? '').toString();

    if (value == 'edit') {
      await _showEditDialog(s);
      return;
    }

    if (value == 'deactivate' || value == 'activate') {
      bool targetStatus = (value == 'activate');

      bool? confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text("${targetStatus ? 'Activer' : 'Désactiver'} la structure"),
          content: Text(
              "Êtes-vous sûr de vouloir ${targetStatus ? 'activer' : 'désactiver'} cette structure ?"),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text("Annuler")),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text("Confirmer",
                    style: TextStyle(
                        color: targetStatus ? Colors.green : Colors.red))),
          ],
        ),
      );

      if (confirm == true) {
        try {
          setState(() => isLoading = true);
          await _structureService.updateStructureStatus(id, targetStatus);

          // 🚀 Lancement de la synchronisation globale après modification du statut
          await _triggerFullSync();

          await _loadStructures();

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text("Statut mis à jour et synchronisé avec succès"),
              backgroundColor: Colors.green,
            ));
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text("Erreur lors de la mise à jour : $e"),
                backgroundColor: Colors.red));
          }
        } finally {
          if (mounted) setState(() => isLoading = false);
        }
      }
    }
  }

  // Vue bloquante affichée lorsqu'aucune connexion n'est disponible
  Widget _buildOfflineView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.wifi_off_rounded,
                size: 64,
                color: Color(0xFFFF9800),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              "Connexion requise",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              "L'accès à « Mon Espace » et la gestion des structures nécessitent une connexion internet active.",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF9800),
                padding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              onPressed: _checkNetworkAndLoad,
              icon: const Icon(Icons.refresh_rounded, color: Colors.white),
              label: const Text(
                "Vérifier la connexion",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Color(0xFF1E293B)),
        title: const Text(
          "Mon Espace",
          style: TextStyle(
            color: Color(0xFF1E293B),
            fontWeight: FontWeight.bold,
            letterSpacing: 0.3,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded,
                color: Color(0xFF1E293B), size: 24),
            onPressed: () async {
              await _triggerFullSync();
              _checkNetworkAndLoad();
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: !isBackendAccessible
            ? null
            : () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const SubscriptionScreen(
                structureId: '',
              ),
            ),
          );

          // 🚀 Lancement de la synchronisation globale après ajout de structure
          await _triggerFullSync();

          _checkNetworkAndLoad();
        },
        backgroundColor:
        !isBackendAccessible ? Colors.grey : const Color(0xFFFF9800),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text("Ajouter une structure",
            style:
            TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: isLoading
          ? const Center(
          child: CircularProgressIndicator(color: Color(0xFFFF9800)))
          : (!isBackendAccessible)
          ? _buildOfflineView()
          : userStructures.isEmpty
          ? Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    shape: BoxShape.circle),
                child: Icon(Icons.storefront_outlined,
                    size: 64, color: Colors.grey.shade400),
              ),
              const SizedBox(height: 24),
              const Text("Aucune structure enregistrée",
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E293B))),
            ],
          ),
        ),
      )
          : ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
        itemCount: userStructures.length,
        itemBuilder: (context, index) {
          final s = userStructures[index];
          return _buildProCard(s);
        },
      ),
    );
  }

  Widget _buildProCard(Map<String, dynamic> s) {
    final String id =
    (s['idStructure'] ?? s['id'] ?? s['structureId'] ?? '').toString();
    final String nom = s['nomStructure'] ?? s['nom'] ?? 'Structure sans nom';
    final String type =
    _parseLabel(s['typeStructure'] ?? s['nomType'] ?? s['type']);
    final String ville =
    _parseLabel(s['villeStructure'] ?? s['nomVille'] ?? s['ville']);
    final String? photoPath = _parseLabel(s['structPhotoUrl'] ??
        s['photoStructure'] ??
        s['photo'] ??
        s['logo'] ??
        s['image']);
    final bool expired = _isExpired(s);
    final bool active =
        s['isActive'] == true || s['isActive'] == 1 || s['active'] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Container(
                  height: 150,
                  width: double.infinity,
                  color: Colors.grey.shade200,
                  child: (photoPath != null && photoPath.isNotEmpty)
                      ? (photoPath.startsWith('http')
                      ? Image.network(
                    "$photoPath?t=${DateTime.now().millisecondsSinceEpoch}",
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(
                        Icons.broken_image,
                        size: 50,
                        color: Colors.grey),
                  )
                      : (File(photoPath).existsSync()
                      ? Image.file(
                    File(photoPath),
                    key: ValueKey(photoPath +
                        File(photoPath)
                            .lastModifiedSync()
                            .toString()),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(
                        Icons.image_not_supported,
                        size: 50,
                        color: Colors.grey),
                  )
                      : const Center(
                      child: Icon(Icons.image_not_supported,
                          size: 50, color: Colors.grey))))
                      : const Center(
                    child: Icon(Icons.storefront_rounded,
                        size: 50, color: Color(0xFFFF9800)),
                  ),
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      type.isNotEmpty ? type : "Non défini",
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  child: Container(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: active
                          ? Colors.green.withOpacity(0.8)
                          : Colors.red.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      active ? 'Actif' : 'Inactif',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nom,
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.location_on_rounded,
                          size: 16, color: Color(0xFFFF9800)),
                      const SizedBox(width: 4),
                      Text(
                        ville.isNotEmpty ? ville : "Ville non définie",
                        style: TextStyle(
                            color: Colors.grey.shade600, fontSize: 13),
                      ),
                    ],
                  ),
                  if (expired) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        children: const [
                          Icon(Icons.warning_amber_rounded,
                              color: Colors.red, size: 18),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              "Abonnement expiré. Renouvelez pour accéder.",
                              style: TextStyle(
                                  color: Colors.red,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor:
                          expired ? Colors.orange : Colors.green,
                        ),
                        onPressed: () async {
                          final dynamic rawPriority = s['priorite'] ??
                              s['priority'] ??
                              s['planPriorite'];
                          final int? currentPriority = rawPriority != null
                              ? int.tryParse(rawPriority.toString())
                              : null;

                          await Navigator.push<SubscriptionPlan>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => SubscriptionScreen(
                                structureId: id,
                                filterPriorite: currentPriority,
                              ),
                            ),
                          );

                          // 🚀 Synchro post-abonnement / renouvellement
                          await _triggerFullSync();
                          _checkNetworkAndLoad();
                        },
                        icon: const Icon(Icons.card_membership_rounded,
                            size: 18),
                        label: Text(
                          expired ? "Renouveler" : "Abonnement",
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      Row(
                        children: [
                          PopupMenuButton<String>(
                            onSelected: (val) => _handleMenuAction(val, s),
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: 'edit',
                                child: Row(
                                  children: [
                                    Icon(Icons.edit_rounded,
                                        color: Color(0xFFFF9800), size: 18),
                                    SizedBox(width: 8),
                                    Text("Modifier"),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: active ? 'deactivate' : 'activate',
                                child: Row(
                                  children: [
                                    Icon(
                                      active
                                          ? Icons.block_rounded
                                          : Icons.check_circle_rounded,
                                      color: active ? Colors.red : Colors.green,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(active ? "Désactiver" : "Activer"),
                                  ],
                                ),
                              ),
                            ],
                            icon: const Icon(Icons.more_vert_rounded,
                                color: Colors.grey),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: expired
                                  ? Colors.grey
                                  : const Color(0xFFFF9800),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              elevation: 0,
                            ),
                            onPressed:
                            expired ? null : () => _navigateToAdmin(s),
                            child: const Text("Gérer",
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}