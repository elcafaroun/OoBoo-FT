import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:fada/services/cat_service.dart';
import 'package:fada/screens/mon_espace_screen.dart';

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

  // 🔹 États pour le doublon et la connexion
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
      if (mounted) {
        setState(() => _isOnline = !results.contains(ConnectivityResult.none));
      }
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
    if (mounted) {
      setState(() => _isOnline = !result.contains(ConnectivityResult.none));
    }
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

      if (mounted) {
        setState(() {
          if (exists) {
            _nameError = "Cette catégorie existe déjà dans votre boutique ❌";
            _isNameValid = false;
          } else {
            _nameError = null;
            _isNameValid = true;
          }
        });
      }
    } catch (e) {
      debugPrint("Erreur validation: $e");
    } finally {
      if (mounted) setState(() => _isCheckingName = false);
    }
  }

  Future<void> _pickImage() async {
    final img = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (img != null) setState(() => _imageFile = File(img.path));
  }

  // 🔹 Navigation vers MonEspaceScreen
  void _navigateToMonEspace() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const MonEspaceScreen(),
      ),
    );
  }

  // 🔹 Dialogue d'alerte limite atteinte
  void _showLimitReachedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
              SizedBox(width: 10),
              Text(
                "Limite atteinte",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ],
          ),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Le nombre maximum de catégories est atteint.",
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 10),
              Text(
                "Merci de modifier votre plan dans votre espace ou de contacter l'équipe technique.",
                style: TextStyle(fontSize: 14, color: Colors.black87),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF9800),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                Navigator.of(ctx).pop();
                _navigateToMonEspace();
              },
              child: const Text(
                "FERMER",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _saveCategory() async {
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
          const SnackBar(content: Text("Catégorie ajoutée !"), backgroundColor: Colors.green),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        String errorMsg = e.toString().replaceAll("Exception: ", "");

        if (errorMsg.contains("Limite atteinte") || errorMsg.contains("maximum")) {
          _showLimitReachedDialog();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Erreur: $errorMsg"), backgroundColor: Colors.red),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  InputDecoration _inputStyle(String label, IconData icon, {bool isChecking = false, bool isValid = false, String? error}) {
    return InputDecoration(
      labelText: label,
      errorText: error,
      prefixIcon: Icon(icon, color: Colors.orange.shade700),
      suffixIcon: isChecking
          ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2))
          : (isValid ? const Icon(Icons.check_circle, color: Colors.green) : null),
      filled: true,
      fillColor: const Color(0xFFFAFAFA),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFFF9800), width: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F7F2),
      appBar: AppBar(
        title: const Text("Ajouter une catégorie", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: Column(
        children: [
          if (!_isOnline)
            Container(
              width: double.infinity,
              color: Colors.redAccent,
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: const Text(
                "⚠️ Mode hors-ligne. Enregistrement impossible.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.grey.shade200),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.03),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Informations de la catégorie",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Sélection photo
                      GestureDetector(
                        onTap: _pickImage,
                        child: Container(
                          height: 140,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFAFAFA),
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(color: Colors.grey.shade300, style: BorderStyle.solid),
                          ),
                          child: _imageFile == null
                              ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_a_photo_outlined, color: Colors.orange.shade700, size: 36),
                              const SizedBox(height: 8),
                              Text(
                                "Ajouter une image",
                                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                              ),
                            ],
                          )
                              : ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Image.file(_imageFile!, fit: BoxFit.cover),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      TextFormField(
                        controller: _nameController,
                        focusNode: _nameFocusNode,
                        decoration: _inputStyle("Nom", Icons.category, isChecking: _isCheckingName, isValid: _isNameValid, error: _nameError),
                        validator: (v) => (v == null || v.isEmpty) ? "Requis" : _nameError,
                        onChanged: (val) {
                          if (_nameError != null) setState(() => _nameError = null);
                        },
                      ),
                      const SizedBox(height: 16),

                      TextFormField(
                        controller: _descriptionController,
                        maxLines: 3,
                        decoration: _inputStyle("Description", Icons.notes),
                      ),
                      const SizedBox(height: 25),

                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: (_isLoading || !_isOnline || _nameError != null) ? null : _saveCategory,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF9800),
                            disabledBackgroundColor: Colors.grey.shade300,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: _isLoading ? const SizedBox.shrink() : const Icon(Icons.check_circle_rounded),
                          label: _isLoading
                              ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                              : const Text("ENREGISTRER", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}