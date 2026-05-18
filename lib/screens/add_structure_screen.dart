import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../utils/constants.dart';
import '../services/structure_service.dart';
import 'structures_screen.dart';

class AddStructureScreen extends StatefulWidget {
  final String plan;
  const AddStructureScreen({super.key, required this.plan});

  @override
  State<AddStructureScreen> createState() => _AddStructureScreenState();
}

class _AddStructureScreenState extends State<AddStructureScreen> {
  final _formKey = GlobalKey<FormState>();
  final StructureService _structureService = StructureService();

  bool isLoading = false;
  bool isTypesLoading = true;
  bool isVillesLoading = true;
  bool isGpsLoading = false;

  // 🔹 Gestion d'internet et validation Nom
  bool isOnline = true;
  bool isCheckingName = false;
  String? nameError;
  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;
  final FocusNode _nomFocusNode = FocusNode();

  final nomCtrl = TextEditingController();
  final descriptionCtrl = TextEditingController();
  final disponibiliteCtrl = TextEditingController();
  final rueCtrl = TextEditingController();
  final codePosteCtrl = TextEditingController();
  final geoLocCtrl = TextEditingController();

  List<dynamic> _typesStructures = [];
  List<dynamic> _villesStructures = [];
  String? _selectedTypeId;
  String? _selectedVille;
  File? _selectedImage;

  @override
  void initState() {
    super.initState();
    _checkInitialConnectivity();
    _loadInitialData();

    // 🔹 Écouter quand l'utilisateur quitte le champ NOM
    _nomFocusNode.addListener(() {
      if (!_nomFocusNode.hasFocus && nomCtrl.text.isNotEmpty) {
        _checkNameAvailability(nomCtrl.text.trim());
      }
    });

    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      setState(() => isOnline = !results.contains(ConnectivityResult.none));
    });
  }

  @override
  void dispose() {
    _connectivitySubscription.cancel();
    _nomFocusNode.dispose();
    nomCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkInitialConnectivity() async {
    var result = await Connectivity().checkConnectivity();
    setState(() => isOnline = !result.contains(ConnectivityResult.none));
  }

  // 🔹 REGLE 1 : Charger et filtrer les données actives
  Future<void> _loadInitialData() async {
    try {
      final results = await Future.wait([
        _structureService.getAllTypeStructures(),
        _structureService.getAllVilleStructures(),
      ]);

      setState(() {
        _typesStructures = results[0].where((t) => t['active'] == true || t['isActive'] == true).toList();
        _villesStructures = results[1].where((v) => v['active'] == true || v['isActive'] == true).toList();
        isTypesLoading = false;
        isVillesLoading = false;
      });
    } catch (e) {
      setState(() { isTypesLoading = false; isVillesLoading = false; });
    }
  }

  // 🔹 Vérification API du nom unique
  Future<void> _checkNameAvailability(String nom) async {
    if (!isOnline) return;
    setState(() { isCheckingName = true; nameError = null; });

    try {
      // Appel à votre endpoint backend /exists?nom=...
      final response = await http.get(
        Uri.parse('$baseUrl/structure/exists?nom=${Uri.encodeComponent(nom)}'),
      );
      if (response.statusCode == 200) {
        bool exists = jsonDecode(response.body);
        setState(() {
          nameError = exists ? "Ce nom est déjà utilisé ❌" : null;
        });
      }
    } catch (e) {
      debugPrint("Erreur validation nom: $e");
    } finally {
      setState(() => isCheckingName = false);
    }
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked != null) setState(() => _selectedImage = File(picked.path));
  }

  Future<void> _getCurrentLocation() async {
    setState(() => isGpsLoading = true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      setState(() => geoLocCtrl.text = "${position.latitude}, ${position.longitude}");
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erreur GPS : $e")));
    } finally {
      if (mounted) setState(() => isGpsLoading = false);
    }
  }

  Future<void> handleSubmit() async {
    // 🔹 REGLE 2 : Bloquer si hors ligne ou erreur de nom
    if (!isOnline || nameError != null) return;

    if (!_formKey.currentState!.validate()) return;
    setState(() => isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('userId');

      final structureData = {
        "nomStructure": nomCtrl.text.trim(),
        "typeStructure": _selectedTypeId,
        "descriptionStructure": descriptionCtrl.text.trim(),
        "disponibiliteStructure": disponibiliteCtrl.text.trim(),
        "paysStructure": "Burkina Faso",
        "villeStructure": _selectedVille,
        "rueStructure": rueCtrl.text.trim(),
        "codePoste": codePosteCtrl.text.trim(),
        "geoLocStructure": geoLocCtrl.text.trim(),
        "createdUserId": userId,
        "planStructure": widget.plan,
      };

      final response = await http.post(
          Uri.parse('$baseUrl/structure'),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode(structureData)
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final decoded = jsonDecode(response.body);
        final structureId = decoded['idStructure']?.toString();
        if (structureId != null && _selectedImage != null) {
          final request = http.MultipartRequest("PUT", Uri.parse("$baseUrl/structure/photo"))
            ..fields['id'] = structureId
            ..files.add(await http.MultipartFile.fromPath('file', _selectedImage!.path));
          await request.send();
        }
        if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const StructuresScreen()));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erreur : $e")));
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  InputDecoration _fieldStyle(String label, IconData icon) => InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon, color: const Color(0xFFFF9800)),
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFFF9800), width: 2)),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F4F4),
      appBar: AppBar(
        title: const Text("NOUVELLE STRUCTURE", style: TextStyle(fontWeight: FontWeight.w900)),
        centerTitle: true, backgroundColor: Colors.white, foregroundColor: Colors.black, elevation: 0,
      ),
      body: Column(
        children: [
          // 🔹 BANDE DE NOTIFICATION INTERNET
          if (!isOnline)
            Container(
              width: double.infinity, color: Colors.redAccent, padding: const EdgeInsets.symmetric(vertical: 8),
              child: const Text("⚠️ Pas d'internet. Enregistrement désactivé.", textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
                        width: double.infinity, height: 180,
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade300)),
                        child: _selectedImage == null
                            ? const Center(child: Text("AJOUTER UNE PHOTO"))
                            : ClipRRect(borderRadius: BorderRadius.circular(16), child: Image.file(_selectedImage!, fit: BoxFit.cover)),
                      ),
                    ),
                    const SizedBox(height: 25),

                    // 🔹 Champ NOM avec FocusNode et vérification
                    TextFormField(
                      controller: nomCtrl,
                      focusNode: _nomFocusNode,
                      decoration: _fieldStyle("NOM", Icons.storefront).copyWith(
                        suffixIcon: isCheckingName
                            ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2))
                            : (nameError == null && nomCtrl.text.isNotEmpty ? const Icon(Icons.check_circle, color: Colors.green) : null),
                        errorText: nameError,
                      ),
                      validator: (v) => v!.isEmpty ? "Obligatoire" : nameError,
                      onChanged: (val) { if(nameError != null) setState(() => nameError = null); },
                    ),
                    const SizedBox(height: 15),

                    isTypesLoading
                        ? const LinearProgressIndicator()
                        : DropdownButtonFormField<String>(
                      value: _selectedTypeId,
                      decoration: _fieldStyle("TYPE", Icons.category),
                      items: _typesStructures.map((t) => DropdownMenuItem<String>(value: t['id'], child: Text(t['nomType'] ?? "Type"))).toList(),
                      onChanged: (val) => setState(() => _selectedTypeId = val),
                    ),
                    const SizedBox(height: 15),

                    TextFormField(controller: descriptionCtrl, maxLines: 2, decoration: _fieldStyle("DESCRIPTION", Icons.description)),
                    const SizedBox(height: 15),

                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: isVillesLoading
                              ? const LinearProgressIndicator()
                              : DropdownButtonFormField<String>(
                            value: _selectedVille,
                            decoration: _fieldStyle("VILLE", Icons.location_city),
                            items: _villesStructures.map((v) => DropdownMenuItem<String>(value: v['nomVille'], child: Text(v['nomVille'] ?? "Ville"))).toList(),
                            onChanged: (val) => setState(() => _selectedVille = val),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: TextFormField(controller: codePosteCtrl, decoration: _fieldStyle("C.P", Icons.mail))),
                      ],
                    ),
                    const SizedBox(height: 15),

                    TextFormField(controller: rueCtrl, decoration: _fieldStyle("ADRESSE", Icons.map)),
                    const SizedBox(height: 15),

                    TextFormField(
                      controller: geoLocCtrl, readOnly: true,
                      decoration: _fieldStyle("GPS", Icons.my_location).copyWith(
                        suffixIcon: isGpsLoading ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2)) : IconButton(icon: const Icon(Icons.gps_fixed), onPressed: _getCurrentLocation),
                      ),
                    ),
                    const SizedBox(height: 30),

                    SizedBox(
                      width: double.infinity, height: 55,
                      child: ElevatedButton(
                        onPressed: (isLoading || !isOnline || nameError != null) ? null : handleSubmit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF9800),
                          disabledBackgroundColor: Colors.grey.shade400,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                        ),
                        child: isLoading
                            ? const CircularProgressIndicator(color: Colors.white)
                            : const Text("ENREGISTRER", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
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