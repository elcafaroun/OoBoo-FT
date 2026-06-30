import 'dart:io';
import 'dart:async';
import 'package:fada/screens/scanner_screen.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../services/product_service.dart';

class AddProductScreen extends StatefulWidget {
  final String categoryId;

  const AddProductScreen({super.key, required this.categoryId});

  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
  final _formKey = GlobalKey<FormState>();

  // Contrôleurs
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _priceController = TextEditingController();
  final _purchasePriceController = TextEditingController();
  final _productQteController = TextEditingController();
  final _stockAlertController = TextEditingController();
  final _qrCodeController = TextEditingController(); // 👈 Nouveau contrôleur pour le Code QR

  // Focus et Validation Nom
  final FocusNode _nameFocusNode = FocusNode();
  String? _nameError;
  bool _isCheckingName = false;
  bool _isNameValid = false;

  // État de connexion
  bool _isOnline = true;
  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;

  File? _imageFile;
  bool _loading = false;
  final ProductService _service = ProductService();

  @override
  void initState() {
    super.initState();
    _checkInitialConnectivity();

    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      setState(() => _isOnline = !results.contains(ConnectivityResult.none));
    });

    _nameFocusNode.addListener(() {
      if (!_nameFocusNode.hasFocus && _nameController.text.isNotEmpty) {
        _validateProductName();
      }
    });
  }

  @override
  void dispose() {
    _connectivitySubscription.cancel();
    _nameFocusNode.dispose();
    _nameController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _purchasePriceController.dispose();
    _productQteController.dispose();
    _stockAlertController.dispose();
    _qrCodeController.dispose(); // 👈 Nettoyage du contrôleur QR
    super.dispose();
  }

  Future<void> _checkInitialConnectivity() async {
    final result = await Connectivity().checkConnectivity();
    setState(() => _isOnline = !result.contains(ConnectivityResult.none));
  }

  /// 🔍 Génération automatique d'un code unique basé sur le temps et la structure
  void _generateAutomaticQrCode() async {
    final prefs = await SharedPreferences.getInstance();
    final String codeStructure = prefs.getString('selected_structure_id') ?? "PBM";
    final int timestamp = DateTime.now().millisecondsSinceEpoch;

    // Génère une structure propre : PBM-1719669518 (Exemple)
    setState(() {
      _qrCodeController.text = "${codeStructure.toUpperCase()}-$timestamp";
    });
  }

  /// 📸 Fonction simulée ou reliée à ton module de scan de caméra
  /// 📸 Ouvre l'écran de la caméra et récupère le code scanné
  Future<void> _scanProductCode() async {
    // Import du fichier fraîchement créé
    final String? codeScanne = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const ScannerScreen()),
    );

    // Si l'utilisateur n'a pas fait un retour arrière vide, on assigne la valeur
    if (codeScanne != null && codeScanne.isNotEmpty) {
      setState(() {
        _qrCodeController.text = codeScanne;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Code produit récupéré : $codeScanne ✅"),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _validateProductName() async {
    if (!_isOnline) return;

    setState(() {
      _isCheckingName = true;
      _nameError = null;
      _isNameValid = false;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final String codeStructure = prefs.getString('selected_structure_id') ?? "DEFAUT";

      final bool exists = await _service.checkProductNameExists(
        productName: _nameController.text.trim(),
        categoryId: widget.categoryId,
        codeStructure: codeStructure,
      );

      setState(() {
        if (exists) {
          _nameError = "Ce produit existe déjà ici ❌";
          _isNameValid = false;
        } else {
          _nameError = null;
          _isNameValid = true;
        }
      });
    } catch (e) {
      debugPrint("Erreur validation nom: $e");
    } finally {
      setState(() => _isCheckingName = false);
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final img = await ImagePicker().pickImage(source: source, imageQuality: 80);
    if (img != null) {
      setState(() => _imageFile = File(img.path));
      if (mounted) Navigator.pop(context);
    }
  }

  void _showImageSourceOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Source de l'image", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Color(0xFFFF9800)),
              title: const Text("Prendre une photo"),
              onTap: () => _pickImage(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Color(0xFFFF9800)),
              title: const Text("Choisir dans la galerie"),
              onTap: () => _pickImage(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveProduct() async {
    if (!_isOnline || _nameError != null) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);
    final prefs = await SharedPreferences.getInstance();
    final String codeStructure = prefs.getString('selected_structure_id') ?? "DEFAUT";

    final data = {
      "productName": _nameController.text.trim(),
      "productDescription": _descriptionController.text.trim(),
      "productQrCode": _qrCodeController.text.trim(), // 👈 Injection du code QR / Code-barres
      "productPrice": double.tryParse(_priceController.text.trim()) ?? 0.0,
      "prixAchat": double.tryParse(_purchasePriceController.text.trim()) ?? 0.0,
      "categoryId": widget.categoryId,
      "productQte": double.tryParse(_productQteController.text.trim()) ?? 0.0,
      "stockAlert": double.tryParse(_stockAlertController.text.trim()) ?? 0.0,
      "codeStructure": codeStructure,
    };

    try {
      final created = await _service.createProduct(data);
      final String? id = created["id"]?.toString();

      if (_imageFile != null && id != null) {
        await _service.uploadPhoto(id, _imageFile!);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Produit ajouté !"), backgroundColor: Colors.green));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erreur : $e"), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  InputDecoration _fieldStyle(String label, IconData icon, {bool checking = false, String? error, bool valid = false, Widget? suffix}) {
    return InputDecoration(
      labelText: label,
      errorText: error,
      prefixIcon: Icon(icon, color: Colors.orange.shade700),
      suffixIcon: suffix ?? (checking
          ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2))
          : (valid ? const Icon(Icons.check_circle, color: Colors.green) : null)),
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
        title: const Text("Nouveau Produit", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white, foregroundColor: Colors.black, elevation: 0,
      ),
      body: Column(
        children: [
          if (!_isOnline)
            Container(
              width: double.infinity, color: Colors.redAccent, padding: const EdgeInsets.symmetric(vertical: 8),
              child: const Text("⚠️ Hors-ligne. Enregistrement bloqué.", textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),

          Expanded(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  // Sélecteur d'image
                  GestureDetector(
                    onTap: _showImageSourceOptions,
                    child: Container(
                      height: 160,
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey.shade300)),
                      child: _imageFile == null
                          ? const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.camera_enhance, size: 40, color: Color(0xFFFF9800)), Text("Ajouter une photo")])
                          : ClipRRect(borderRadius: BorderRadius.circular(18), child: Image.file(_imageFile!, fit: BoxFit.cover)),
                    ),
                  ),
                  const SizedBox(height: 25),

                  // Champ Nom avec validation dynamique
                  TextFormField(
                    controller: _nameController,
                    focusNode: _nameFocusNode,
                    decoration: _fieldStyle("Nom du produit", Icons.shopping_bag, checking: _isCheckingName, error: _nameError, valid: _isNameValid),
                    validator: (v) => v!.isEmpty ? "Requis" : _nameError,
                    onChanged: (val) { if(_nameError != null) setState(() => _nameError = null); },
                  ),
                  const SizedBox(height: 15),

                  // 🔐 Champ Code QR / Code-barres avec Double Action (Scanner ou Générer)
                  TextFormField(
                    controller: _qrCodeController,
                    decoration: _fieldStyle(
                      "Code QR / Code-barres (Optionnel)",
                      Icons.qr_code_2_rounded,
                      suffix: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.document_scanner_rounded, color: Colors.blue),
                            tooltip: "Scanner un code",
                            onPressed: _scanProductCode,
                          ),
                          IconButton(
                            icon: const Icon(Icons.autorenew_rounded, color: Colors.green),
                            tooltip: "Générer un code",
                            onPressed: _generateAutomaticQrCode,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 15),

                  TextFormField(controller: _descriptionController, maxLines: 2, decoration: _fieldStyle("Description", Icons.description)),
                  const SizedBox(height: 15),

                  Row(
                    children: [
                      Expanded(child: TextFormField(controller: _purchasePriceController, decoration: _fieldStyle("Prix Achat", Icons.add_shopping_cart), keyboardType: TextInputType.number)),
                      const SizedBox(width: 10),
                      Expanded(child: TextFormField(controller: _priceController, decoration: _fieldStyle("Prix Vente", Icons.sell), keyboardType: TextInputType.number, validator: (v) => v!.isEmpty ? "Requis" : null)),
                    ],
                  ),
                  const SizedBox(height: 15),

                  Row(
                    children: [
                      Expanded(child: TextFormField(controller: _productQteController, decoration: _fieldStyle("Quantité", Icons.inventory), keyboardType: TextInputType.number)),
                      const SizedBox(width: 10),
                      Expanded(child: TextFormField(controller: _stockAlertController, decoration: _fieldStyle("Alerte Stock", Icons.warning), keyboardType: TextInputType.number)),
                    ],
                  ),
                  const SizedBox(height: 35),

                  SizedBox(
                    height: 55,
                    child: ElevatedButton(
                      onPressed: (_loading || !_isOnline || _nameError != null) ? null : _saveProduct,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF9800),
                        disabledBackgroundColor: Colors.grey.shade400,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      ),
                      child: _loading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Text(_isOnline ? "ENREGISTRER" : "CONNEXION REQUISE", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}