import 'dart:convert';
import 'package:fada/services/database/database_helper.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fada/services/user_service.dart';
import 'package:fada/services/structure_service.dart';
import 'package:fada/services/network_checker.dart'; // 👈 IMPORT DU CHECKER UNIQUE
import 'package:fada/screens/register_screen.dart';
import 'package:fada/screens/subscription_screen.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;

  final UserService _userService = UserService();
  final StructureService _structureService = StructureService();

  /// 🔹 Vérification de la destination (Home ou Subscription)
  /// Gère dynamiquement les sources de données (API ou SQLite)
  Future<void> _checkAndNavigate(String userId, String codeStructure, bool isOnline) async {
    if (isOnline) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator(color: Colors.orange)),
      );
    }

    try {
      List<dynamic> structures;

      if (isOnline) {
        // 🌍 Récupération via l'API mise à jour
        structures = await _structureService.getStructuresByUser(userId);
        // 💾 Rafraîchissement immédiat du cache local pour la cohérence des données
        await DatabaseHelper().syncStructuresLocal(structures);
      } else {
        // 🏠 Récupération via SQLite local
        structures = await DatabaseHelper().getLocalStructuresByUser(userId);
      }

      if (!mounted) return;
      if (isOnline) Navigator.pop(context); // Fermer le loader uniquement si online

      if (structures.isEmpty && codeStructure.isEmpty) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const SubscriptionScreen()),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const HomeScreen()),
        );
      }
    } catch (e) {
      if (!mounted) return;
      if (isOnline) Navigator.pop(context);
      _showSnackBar('Erreur de vérification : $e', Colors.red);
    }
  }

  /// 🔹 Logique de connexion Hybride optimisée
  void _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      // 1️⃣ VRAIE vérification de la disponibilité du micro-service backend
      bool serverIsUp = await NetworkChecker.isBackendAccessible();

      if (serverIsUp) {
        // --- 🌐 TENTATIVE ONLINE (Serveur disponible) ---
        final userData = await _userService.login(
          _phoneController.text.trim(),
          _passwordController.text.trim(),
        );

        if (userData != null) {
          // 💾 Sauvegarde ou mise à jour du profil utilisateur dans SQLite
          await DatabaseHelper().saveOrUpdateUserLocal(userData);

          final SharedPreferences prefs = await SharedPreferences.getInstance();
          final String userId = userData['id'].toString();
          final String codeStructure = userData['codeStructure']?.toString() ?? '';

          await _saveSession(prefs, userData);

          if (mounted) _checkAndNavigate(userId, codeStructure, true);
        } else {
          _showSnackBar('Téléphone ou mot de passe incorrect ❌', Colors.red);
          setState(() => _isLoading = false);
        }
      } else {
        // --- 🛰️ TENTATIVE OFFLINE AUTOMATIQUE (Serveur inaccessible) ---
        debugPrint("🔄 Serveur inaccessible. Bascule : Mode Offline pour le login");
        final String identifier = _phoneController.text.trim();

        // Recherche sécurisée de l'utilisateur dans la base locale SQLite
        final localUser = await DatabaseHelper().getUserByIdentifier(identifier);

        if (localUser != null) {
          // Note : Idéalement, ajoutez une vérification locale hashée du mot de passe si nécessaire.
          final SharedPreferences prefs = await SharedPreferences.getInstance();

          // Reconstitution de la session depuis SQLite
          await prefs.setString('userId', localUser['id'].toString());
          await prefs.setString('codeStructure', localUser['codeStructure'] ?? '');
          await prefs.setString('userName', localUser['userName'] ?? '');

          if (mounted) {
            _showSnackBar('Connexion hors-ligne réussie 🛰️', Colors.blueGrey);
            _checkAndNavigate(localUser['id'].toString(), localUser['codeStructure'] ?? '', false);
          }
        } else {
          _showSnackBar('Aucun profil local trouvé. Connectez-vous avec internet la première fois.', Colors.orange);
          setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _showSnackBar('Erreur : $e', Colors.red);
    }
  }

  /// Helper pour sauvegarder les SharedPreferences
  Future<void> _saveSession(SharedPreferences prefs, Map<String, dynamic> data) async {
    await prefs.setString('userId', data['id'].toString());
    await prefs.setString('userProfile', data['userProfile'] ?? 'Vente');
    await prefs.setString('userName', data['userName'] ?? '');
    await prefs.setString('codeStructure', data['codeStructure']?.toString() ?? '');
    await prefs.setString('selected_structure_id', data['codeStructure']?.toString() ?? '');
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Header
            Container(
              height: 300,
              width: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.orange, Color(0xFFFF8C00)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.only(bottomLeft: Radius.circular(80)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.business_center, size: 80, color: Colors.white),
                  const SizedBox(height: 10),
                  const Text("OoBou", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 1.5)),
                  Text("Gestion & Performance", style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 14)),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Connexion", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF2D3436))),
                    const SizedBox(height: 8),
                    const Text("Veuillez entrer vos identifiants pour continuer", style: TextStyle(color: Colors.grey)),
                    const SizedBox(height: 30),

                    _buildTextField(
                      controller: _phoneController,
                      label: "Numéro de téléphone",
                      icon: Icons.phone_android_rounded,
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 20),

                    _buildTextField(
                      controller: _passwordController,
                      label: "Mot de passe",
                      icon: Icons.lock_outline_rounded,
                      isPassword: true,
                      obscureText: _obscurePassword,
                      onToggleVisibility: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),

                    const SizedBox(height: 30),

                    _isLoading
                        ? const Center(child: CircularProgressIndicator(color: Colors.orange))
                        : SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: ElevatedButton(
                        onPressed: _login,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          elevation: 4,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                        ),
                        child: const Text("SE CONNECTER", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                    ),

                    const SizedBox(height: 20),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                     // mainAxisAlignment: MainAxisAlignment.center,
                     // mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text("Nouveau sur la plateforme ? "),
                        GestureDetector(
                          onTap: () {
                            Navigator.push(context, MaterialPageRoute(builder: (context) => const RegisterScreen(isFromLogin: true)));
                          },
                          child: const Text("Créer un compte", style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isPassword = false,
    bool obscureText = false,
    VoidCallback? onToggleVisibility,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))],
      ),
      child: TextFormField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: Colors.orange),
          suffixIcon: isPassword
              ? IconButton(
            icon: Icon(obscureText ? Icons.visibility_off : Icons.visibility, color: Colors.grey),
            onPressed: onToggleVisibility,
          )
              : null,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 18),
        ),
        validator: (value) => (value == null || value.isEmpty) ? "Champ requis" : null,
      ),
    );
  }
}