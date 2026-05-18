import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:fada/services/cat_service.dart';

class AddCategoryScreen extends StatefulWidget {
  final String structureId;
  const AddCategoryScreen({super.key, required this.structureId});

  @override
  State<AddCategoryScreen> createState() => _AddCategoryScreenState();
}

class _AddCategoryScreenState extends State<AddCategoryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final CatService _catService = CatService();

  // 🔹 Nouveaux états pour le doublon et la connexion
  final FocusNode _nameFocusNode = FocusNode();
  String? _nameError;
  bool _isCheckingName = false;
  bool _isNameValid = false;
  bool _isOnline = true;
  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;

  File? _imageFile;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _checkConnectivity();

    // Surveiller la connexion
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      setState(() => _isOnline = !results.contains(ConnectivityResult.none));
    });

    // 🔹 Écouter quand l'utilisateur quitte le champ Nom pour vérifier le doublon
    _nameFocusNode.addListener(() {
      if (!_nameFocusNode.hasFocus && _nameController.text.isNotEmpty) {
        _validateNameUniqueness();
      }
    });
  }

  @override
  void dispose() {
    _connectivitySubscription.cancel();
    _nameFocusNode.dispose();
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _checkConnectivity() async {
    final result = await Connectivity().checkConnectivity();
    setState(() => _isOnline = !result.contains(ConnectivityResult.none));
  }

  // 🔹 Fonction de vérification du doublon
  Future<void> _validateNameUniqueness() async {
    if (!_isOnline) return;

    setState(() {
      _isCheckingName = true;
      _nameError = null;
      _isNameValid = false;
    });

    try {
      final exists = await _catService.checkCategoryNameExists(
        _nameController.text.trim(),
        widget.structureId,
      );

      setState(() {
        if (exists) {
          _nameError = "Cette catégorie existe déjà dans votre boutique ❌";
          _isNameValid = false;
        } else {
          _nameError = null;
          _isNameValid = true; // Affiche le check vert
        }
      });
    } catch (e) {
      debugPrint("Erreur validation: $e");
    } finally {
      setState(() => _isCheckingName = false);
    }
  }

  Future<void> _pickImage() async {
    final img = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (img != null) setState(() => _imageFile = File(img.path));
  }

  Future<void> _saveCategory() async {
    // Bloquer si hors-ligne ou si le nom est un doublon
    if (!_isOnline || _nameError != null) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final response = await _catService.createCategory(
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        structureId: widget.structureId,
      );

      final categoryId = response["id"]?.toString();
      if (_imageFile != null && categoryId != null) {
        await _catService.uploadPhoto(categoryId, _imageFile!);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Catégorie ajoutée !"), backgroundColor: Colors.green)
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erreur: $e"), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Style des champs avec indicateur de succès/chargement
  InputDecoration _inputStyle(String label, IconData icon, {bool isChecking = false, bool isValid = false, String? error}) {
    return InputDecoration(
      labelText: label,
      errorText: error,
      prefixIcon: Icon(icon, color: Colors.orange.shade700),
      suffixIcon: isChecking
          ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2))
          : (isValid ? const Icon(Icons.check_circle, color: Colors.green) : null),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide(color: Colors.grey.shade300)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: Color(0xFFFF9800), width: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F7F2),
      appBar: AppBar(
        title: const Text("Ajouter une catégorie", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white, foregroundColor: Colors.black, elevation: 0,
      ),
      body: Column(
        children: [
          // Bandeau d'alerte connexion
          if (!_isOnline)
            Container(
              width: double.infinity, color: Colors.redAccent, padding: const EdgeInsets.symmetric(vertical: 8),
              child: const Text("⚠️ Mode hors-ligne. Enregistrement impossible.", textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 12)),
            ),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: _pickImage,
                      child: Container(
                        height: 160, width: double.infinity,
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey.shade300)),
                        child: _imageFile == null
                            ? const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.camera_enhance, color: Colors.orange, size: 40), Text("Photo")])
                            : ClipRRect(borderRadius: BorderRadius.circular(18), child: Image.file(_imageFile!, fit: BoxFit.cover)),
                      ),
                    ),
                    const SizedBox(height: 25),

                    TextFormField(
                      controller: _nameController,
                      focusNode: _nameFocusNode,
                      decoration: _inputStyle("Nom", Icons.category, isChecking: _isCheckingName, isValid: _isNameValid, error: _nameError),
                      validator: (v) => (v == null || v.isEmpty) ? "Requis" : _nameError,
                      onChanged: (val) {
                        if (_nameError != null) setState(() => _nameError = null);
                      },
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _descriptionController,
                      maxLines: 3,
                      decoration: _inputStyle("Description", Icons.notes),
                    ),
                    const SizedBox(height: 35),

                    SizedBox(
                      width: double.infinity, height: 55,
                      child: ElevatedButton.icon(
                        onPressed: (_isLoading || !_isOnline || _nameError != null) ? null : _saveCategory,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF9800),
                          disabledBackgroundColor: Colors.grey.shade400,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                        ),
                        icon: _isLoading ? const SizedBox.shrink() : const Icon(Icons.check_circle_rounded),
                        label: _isLoading
                            ? const CircularProgressIndicator(color: Colors.white)
                            : const Text("ENREGISTRER", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}