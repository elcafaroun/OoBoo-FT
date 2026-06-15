import 'dart:convert';
import 'package:fada/services/database/database_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fada/services/user_service.dart';
import 'package:fada/services/structure_service.dart';
import 'package:fada/services/network_checker.dart';
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
  final TextEditingController _loginController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;

  final UserService _userService = UserService();
  final StructureService _structureService = StructureService();

  /// 🔹 Vérification de la destination (Home ou Subscription)
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
        structures = await _structureService.getStructuresByUser(userId);
        await DatabaseHelper().syncStructuresLocal(structures);
      } else {
        structures = await DatabaseHelper().getLocalStructuresByUser(userId);
      }

      if (!mounted) return;
      if (isOnline) Navigator.pop(context);

      // Si aucune structure n'est associée, redirection vers l'écran d'abonnement / création
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

  /// 🔹 Logique de connexion Hybride avec gestion du tableau de structures
  void _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      bool serverIsUp = await NetworkChecker.isBackendAccessible();
      final String loginValue = _loginController.text.trim();
      final String passwordValue = _passwordController.text.trim();

      if (serverIsUp) {
        // --- 🌐 TENTATIVE ONLINE ---
        final userData = await _userService.login(loginValue, passwordValue);

        if (userData != null) {
          final SharedPreferences prefs = await SharedPreferences.getInstance();
          final String userId = userData['id'].toString();

          // 🆕 Extraction sécurisée de la structure par défaut depuis la liste Many-to-Many
          List<dynamic> structuresAssociees = userData['structures'] ?? [];
          String codeStructure = '';

          if (structuresAssociees.isNotEmpty) {
            codeStructure = structuresAssociees.first['codeStructure']?.toString() ?? '';
          }

          // Préparer l'objet épuré pour la base locale SQLite
          Map<String, dynamic> localUserMap = {
            'id': userId,
            'userName': userData['userName'] ?? loginValue,
            'userEmail': userData['userEmail'],
            'userPhone': userData['userPhone'],
            'userProfile': userData['userProfile'],
            'codeStructure': codeStructure,
            'codeUser': userData['codeUser'],
            'isActive': 1,
            'updatedAt': DateTime.now().toIso8601String(),
          };

          await DatabaseHelper().saveOrUpdateUserLocal(localUserMap);

          // 🆕 Détection du flag de première connexion renvoyé par Spring Boot
          final bool isFirstLogin = userData['isFirstLogin'] == true;

          await _saveSession(prefs, userData, codeStructure);

          if (mounted) {
            if (isFirstLogin) {
              setState(() => _isLoading = false);
              // 🔒 Bloquer le flux standard et forcer le changement immédiat du PIN
              _showChangePasswordDialog(userId, codeStructure);
            } else {
              // Redirection classique
              _checkAndNavigate(userId, codeStructure, true);
            }
          }
        } else {
          _showSnackBar('Identifiant ou code PIN incorrect ❌', Colors.red);
          setState(() => _isLoading = false);
        }
      } else {
        // --- 🛰️ TENTATIVE OFFLINE AUTOMATIQUE ---
        debugPrint("🔄 Serveur inaccessible. Bascule : Mode Offline pour le login");

        final localUser = await DatabaseHelper().getUserByIdentifier(loginValue);

        if (localUser != null) {
          final SharedPreferences prefs = await SharedPreferences.getInstance();
          final String cachedCodeStructure = localUser['codeStructure']?.toString() ?? '';

          // Adapter la structure de données locale pour la fonction de session
          await _saveSession(prefs, Map<String, dynamic>.from(localUser), cachedCodeStructure);

          if (mounted) {
            _showSnackBar('Connexion hors-ligne réussie 🛰️', Colors.blueGrey);
            _checkAndNavigate(localUser['id'].toString(), cachedCodeStructure, false);
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

  // 🔐 MODALE POUR FORCER LE CHANGEMENT DE CODE PIN (PREMIÈRE CONNEXION)
  void _showChangePasswordDialog(String userId, String codeStructure) {
    final _dialogFormKey = GlobalKey<FormState>();
    final TextEditingController _newPinController = TextEditingController();
    final TextEditingController _confirmPinController = TextEditingController();
    bool _isDialogLoading = false;
    bool _obscureNew = true;
    bool _obscureConfirm = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Row(
                children: [
                  Icon(Icons.security, color: Colors.orange),
                  SizedBox(width: 10),
                  Text("Sécurité requise", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                ],
              ),
              content: Form(
                key: _dialogFormKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        "Il s'agit de votre première connexion. Par mesure de sécurité, veuillez personnaliser votre code PIN d'accès à 4 chiffres.",
                        style: TextStyle(color: Colors.black54, fontSize: 13, height: 1.4),
                      ),
                      const SizedBox(height: 20),

                      // Champ : Nouveau Code PIN
                      TextFormField(
                        controller: _newPinController,
                        obscureText: _obscureNew,
                        keyboardType: TextInputType.number,
                        maxLength: 4,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: InputDecoration(
                          labelText: "Nouveau Code PIN",
                          prefixIcon: const Icon(Icons.lock, color: Colors.orange),
                          counterText: "",
                          filled: true,
                          fillColor: Colors.grey.withOpacity(0.05),
                          suffixIcon: IconButton(
                            icon: Icon(_obscureNew ? Icons.visibility_off : Icons.visibility, color: Colors.grey),
                            onPressed: () => setDialogState(() => _obscureNew = !_obscureNew),
                          ),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        ),
                        validator: (v) => (v == null || v.length != 4) ? "Requis (4 chiffres)" : null,
                      ),
                      const SizedBox(height: 15),

                      // Champ : Confirmation du Code PIN
                      TextFormField(
                        controller: _confirmPinController,
                        obscureText: _obscureConfirm,
                        keyboardType: TextInputType.number,
                        maxLength: 4,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: InputDecoration(
                          labelText: "Confirmer le Code PIN",
                          prefixIcon: const Icon(Icons.lock_outline, color: Colors.orange),
                          counterText: "",
                          filled: true,
                          fillColor: Colors.grey.withOpacity(0.05),
                          suffixIcon: IconButton(
                            icon: Icon(_obscureConfirm ? Icons.visibility_off : Icons.visibility, color: Colors.grey),
                            onPressed: () => setDialogState(() => _obscureConfirm = !_obscureConfirm),
                          ),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) return "Requis";
                          if (v != _newPinController.text) return "Les codes PIN ne correspondent pas";
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0, left: 5, right: 5),
                  child: SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      onPressed: _isDialogLoading ? null : () async {
                        if (!_dialogFormKey.currentState!.validate()) return;

                        setDialogState(() => _isDialogLoading = true);

                        bool updateSuccess = await _userService.changeFirstPassword(
                            userId,
                            _newPinController.text.trim()
                        );

                        setDialogState(() => _isDialogLoading = false);

                        if (updateSuccess) {
                          Navigator.pop(context);
                          _showSnackBar('Code PIN mis à jour avec succès ! 🎉', Colors.green);
                          _checkAndNavigate(userId, codeStructure, true);
                        } else {
                          _showSnackBar('Erreur lors de la mise à jour du code PIN ❌', Colors.red);
                        }
                      },
                      child: _isDialogLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text("VALIDER MON NOUVEAU PIN", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _saveSession(SharedPreferences prefs, Map<String, dynamic> data, String codeStructure) async {
    await prefs.setString('userId', data['id'].toString());
    await prefs.setString('userProfile', data['userProfile'] ?? 'Vente');
    await prefs.setString('userName', data['userName'] ?? '');
    await prefs.setString('codeStructure', codeStructure);
    await prefs.setString('selected_structure_id', codeStructure);

    // Si la liste complète des structures est présente (Mode Online), on la met en cache SharedPreferences
    if (data['structures'] != null) {
      await prefs.setString('cached_user_structures', jsonEncode(data['structures']));
    }
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
            // Header dégradé élégant PB-M
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
                  const Text("PB-M", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 1.5)),
                  Text("Performance & Gestion", style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 14)),
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

                    // Champ Identifiant
                    _buildTextField(
                      controller: _loginController,
                      label: "Identifiant",
                      icon: Icons.person_outline_rounded,
                      keyboardType: TextInputType.text,
                    ),
                    const SizedBox(height: 20),

                    // Champ Code PIN
                    _buildTextField(
                      controller: _passwordController,
                      label: "Code PIN (4 chiffres)",
                      icon: Icons.lock_outline_rounded,
                      isPassword: true,
                      obscureText: _obscurePassword,
                      onToggleVisibility: () => setState(() => _obscurePassword = !_obscurePassword),
                      keyboardType: TextInputType.number,
                      isNumericPin: true,
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

                    const SizedBox(height: 30),

                    Center(
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          const Text("Nouveau sur la plateforme ? ", style: TextStyle(color: Colors.black87)),
                          GestureDetector(
                            onTap: () {
                              Navigator.push(context, MaterialPageRoute(builder: (context) => const RegisterScreen(isFromLogin: true)));
                            },
                            child: const Text("Créer un compte", style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
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
    bool isNumericPin = false,
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
        maxLength: isNumericPin ? 4 : null,
        inputFormatters: isNumericPin ? [FilteringTextInputFormatter.digitsOnly] : null,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: Colors.orange),
          counterText: "",
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
        validator: (value) {
          if (value == null || value.isEmpty) {
            return "Champ requis";
          }
          if (isNumericPin && value.length != 4) {
            return "Le code PIN doit faire exactement 4 chiffres";
          }
          return null;
        },
      ),
    );
  }
}