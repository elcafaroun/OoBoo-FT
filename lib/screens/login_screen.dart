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

  // ✅ OFFLINE-FIRST : Navigation rapide basée sur l'état local ou en ligne
  Future<void> _checkAndNavigate(String userId, String codeStructure, bool isOnlineTarget) async {
    try {
      List<dynamic> structures;
      if (isOnlineTarget && await NetworkChecker.isBackendAccessible()) {
        structures = await _structureService.getStructuresByUser(userId);
        await DatabaseHelper().syncStructuresLocal(structures);
      } else {
        structures = await DatabaseHelper().getLocalStructuresByUser(userId);
      }

      if (!mounted) return;

      if (structures.isEmpty && codeStructure.isEmpty) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const SubscriptionScreen()));
      } else {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const HomeScreen()));
      }
    } catch (e) {
      debugPrint('⚠️ Erreur de pré-chargement des structures (Bascule locale automatique) : $e');
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const HomeScreen()));
    }
  }

  // ✅ LE CŒUR DU OFFLINE-FIRST SÉCURISÉ
  void _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final String loginValue = _loginController.text.trim();
    final String passwordValue = _passwordController.text.trim();

    try {
      // 1️⃣ ÉTAPE 1 : On vérifie si cet identifiant existe déjà en local dans SQLite
      final db = await DatabaseHelper().database;
      final List<Map<String, dynamic>> localUserExists = await db.query(
        'users',
        where: 'userEmail = ? OR userName = ? OR userPhone = ?',
        whereArgs: [loginValue, loginValue, loginValue],
        limit: 1,
      );

      if (localUserExists.isNotEmpty) {
        // 🔐 L'utilisateur existe en local -> FLUX OFFLINE-FIRST STRICT
        final localUser = await DatabaseHelper().checkLoginOffline(loginValue, passwordValue);

        if (localUser != null) {
          // 🎉 PIN Correct -> Connexion instantanée
          final SharedPreferences prefs = await SharedPreferences.getInstance();
          final String cachedCodeStructure = localUser['codeStructure']?.toString() ?? '';
          final String userId = localUser['id'].toString();

          // 🔄 On transmet le user tel quel pour récupérer son 'userProfile' stocké localement
          await _saveSession(prefs, Map<String, dynamic>.from(localUser), cachedCodeStructure);

          if (mounted) {
            _showSnackBar('Connexion réussie 🛰️', Colors.blueGrey);
            setState(() => _isLoading = false);
          }

          await _checkAndNavigate(userId, cachedCodeStructure, false);

          // Sync discrète du profil en arrière-plan
          _triggerBackgroundSync(loginValue, passwordValue);
          return;
        } else {
          // ❌ L'utilisateur existe mais le PIN est FAUX -> On bloque DIRECTEMENT ici !
          debugPrint("❌ [SÉCURITÉ] Rejet immédiat : Code PIN local invalide.");
          _showErrorLogin();
          return;
        }
      }

      // 2️⃣ ÉTAPE 2 : TOUTE PREMIÈRE CONNEXION (L'utilisateur n'existe pas encore en local)
      debugPrint("🔍 Utilisateur inconnu en local. Tentative de premier enregistrement via le serveur...");

      if (await NetworkChecker.isBackendAccessible()) {
        final userData = await _userService.login(loginValue, passwordValue);

        if (userData != null) {
          // Double sécurité : On s'assure que le serveur valide le PIN envoyé
          final String serverCodeUser = (userData['codeUser'] ?? '').toString();
          if (serverCodeUser.isNotEmpty && serverCodeUser != passwordValue && userData['isFirstLogin'] != true) {
            _showErrorLogin();
            return;
          }

          final SharedPreferences prefs = await SharedPreferences.getInstance();
          final String userId = userData['id'].toString();

          List<dynamic> structuresAssociees = userData['structures'] ?? [];
          String codeStructure = '';
          if (structuresAssociees.isNotEmpty) {
            codeStructure = structuresAssociees.first['codeStructure']?.toString() ?? '';
          }

          // 👑 On conserve 'userProfile' en local s'il vient du serveur, ou 'SUPER_ADMIN' par sécurité
          String profileValue = userData['userProfile']?.toString() ?? 'SUPER_ADMIN';

          Map<String, dynamic> localUserMap = {
            'id': userId,
            'userName': userData['userName'] ?? loginValue,
            'userEmail': userData['userEmail'],
            'userPhone': userData['userPhone'],
            'userProfile': profileValue, // ✅ Conservé pour le reste de ton application
            'codeStructure': codeStructure,
            'codeUser': serverCodeUser.isNotEmpty ? serverCodeUser : passwordValue,
            'isActive': 1,
            'updatedAt': DateTime.now().toIso8601String(),
          };

          // On initialise la session locale SQLite
          await DatabaseHelper().saveOrUpdateUserLocal(localUserMap);
          final bool isFirstLogin = userData['isFirstLogin'] == true;
          await _saveSession(prefs, userData, codeStructure);

          if (mounted) {
            setState(() => _isLoading = false);
            if (isFirstLogin) {
              _showChangePasswordDialog(userId, codeStructure, localUserMap);
            } else {
              _checkAndNavigate(userId, codeStructure, true);
            }
          }
        } else {
          _showErrorLogin();
        }
      } else {
        // Pas de réseau ET aucun compte local existant = impossible de se connecter
        _showSnackBar('Première connexion requise en ligne 🌐', Colors.orangeAccent);
        setState(() => _isLoading = false);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _showSnackBar('Erreur : $e', Colors.red);
    }
  }

  // 🛰️ Tâche asynchrone en arrière-plan pour synchroniser sans bloquer l'interface
  void _triggerBackgroundSync(String login, String password) async {
    try {
      if (await NetworkChecker.isBackendAccessible()) {
        final userData = await _userService.login(login, password);
        if (userData != null) {
          final String userId = userData['id'].toString();
          List<dynamic> structuresAssociees = userData['structures'] ?? [];
          String codeStructure = structuresAssociees.isNotEmpty
              ? (structuresAssociees.first['codeStructure']?.toString() ?? '')
              : '';

          String profileValue = userData['userProfile']?.toString() ?? 'SUPER_ADMIN';

          Map<String, dynamic> localUserMap = {
            'id': userId,
            'userName': userData['userName'] ?? login,
            'userEmail': userData['userEmail'],
            'userPhone': userData['userPhone'],
            'userProfile': profileValue, // ✅ Préservé lors de la sync
            'codeStructure': codeStructure,
            'codeUser': userData['codeUser'] ?? password,
            'isActive': 1,
            'updatedAt': DateTime.now().toIso8601String(),
          };
          await DatabaseHelper().saveOrUpdateUserLocal(localUserMap);
          debugPrint("🔄 [Sync Arrière-plan] Données utilisateur (avec profil) synchronisées.");
        }
      }
    } catch (e) {
      debugPrint("⚠️ [Sync Arrière-plan] Échec silencieux de la mise à jour : $e");
    }
  }

  void _showErrorLogin() {
    setState(() => _isLoading = false);
    _showSnackBar('Identifiant ou code PIN incorrect ❌', Colors.red);
  }

  void _showChangePasswordDialog(String userId, String codeStructure, Map<String, dynamic> localUserMap) {
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
              title: const Row(children: [Icon(Icons.security, color: Colors.orange), SizedBox(width: 10), Text("Sécurité requise")]),
              content: Form(
                key: _dialogFormKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text("Première connexion : veuillez personnaliser votre code PIN à 4 chiffres.", style: TextStyle(color: Colors.black54, fontSize: 13)),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _newPinController,
                        obscureText: _obscureNew,
                        keyboardType: TextInputType.number,
                        maxLength: 4,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: InputDecoration(
                          labelText: "Nouveau Code PIN",
                          prefixIcon: const Icon(Icons.lock, color: Colors.orange),
                          suffixIcon: IconButton(icon: Icon(_obscureNew ? Icons.visibility_off : Icons.visibility), onPressed: () => setDialogState(() => _obscureNew = !_obscureNew)),
                        ),
                        validator: (v) => (v == null || v.length != 4) ? "Requis (4 chiffres)" : null,
                      ),
                      const SizedBox(height: 15),
                      TextFormField(
                        controller: _confirmPinController,
                        obscureText: _obscureConfirm,
                        keyboardType: TextInputType.number,
                        maxLength: 4,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: InputDecoration(
                          labelText: "Confirmer le Code PIN",
                          prefixIcon: const Icon(Icons.lock_outline, color: Colors.orange),
                          suffixIcon: IconButton(icon: Icon(_obscureConfirm ? Icons.visibility_off : Icons.visibility), onPressed: () => setDialogState(() => _obscureConfirm = !_obscureConfirm)),
                        ),
                        validator: (v) => v != _newPinController.text ? "Les codes ne correspondent pas" : null,
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                    onPressed: _isDialogLoading ? null : () async {
                      if (!_dialogFormKey.currentState!.validate()) return;
                      setDialogState(() => _isDialogLoading = true);

                      String dynamicNewPin = _newPinController.text.trim();
                      bool updateSuccess = await _userService.changeFirstPassword(userId, dynamicNewPin);
                      setDialogState(() => _isDialogLoading = false);

                      if (updateSuccess) {
                        localUserMap['codeUser'] = dynamicNewPin;
                        await DatabaseHelper().saveOrUpdateUserLocal(localUserMap);

                        if (context.mounted) {
                          Navigator.pop(context);
                          _showSnackBar('Code PIN mis à jour avec succès ! 🎉', Colors.green);
                          _checkAndNavigate(userId, codeStructure, true);
                        }
                      } else {
                        _showSnackBar('Erreur lors de la mise à jour ❌', Colors.red);
                      }
                    },
                    child: _isDialogLoading ? const CircularProgressIndicator(color: Colors.white) : const Text("VALIDER MON NOUVEAU PIN"),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ✅ Sécurisé : On sauvegarde à nouveau 'userProfile' dans SharedPreferences pour les autres écrans
  Future<void> _saveSession(SharedPreferences prefs, Map<String, dynamic> data, String codeStructure) async {
    await prefs.setString('userId', data['id'].toString());
    await prefs.setString('userName', data['userName'] ?? '');
    await prefs.setString('userProfile', data['userProfile'] ?? 'SUPER_ADMIN'); // 🔐 Sauvegardé ici !
    await prefs.setString('codeStructure', codeStructure);
    await prefs.setString('selected_structure_id', codeStructure);
    if (data['structures'] != null) {
      await prefs.setString('cached_user_structures', jsonEncode(data['structures']));
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              height: 300,
              width: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [Colors.orange, Color(0xFFFF8C00)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.only(bottomLeft: Radius.circular(80)),
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.business_center, size: 80, color: Colors.white),
                  SizedBox(height: 10),
                  Text("PB-M", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 1.5)),
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
                    const Text("Connexion", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 30),
                    _buildTextField(controller: _loginController, label: "Identifiant", icon: Icons.person_outline_rounded),
                    const SizedBox(height: 20),
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
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                        child: const Text("SE CONNECTER", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                    ),
                    const SizedBox(height: 25),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton(
                          onPressed: () {
                            _showSnackBar("Fonctionnalité bientôt disponible. Veuillez contacter votre administrateur. ⚙️", Colors.blueGrey);
                          },
                          style: TextButton.styleFrom(padding: EdgeInsets.zero),
                          child: const Text(
                            "Code PIN oublié ?",
                            style: TextStyle(color: Colors.black54, fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            // ✅ Mis en adéquation avec le paramètre attendu par le constructeur
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const RegisterScreen(isFromLogin: true),
                              ),
                            );
                          },
                          style: TextButton.styleFrom(padding: EdgeInsets.zero),
                          child: const Text(
                            "Créer un compte",
                            style: TextStyle(color: Colors.orange, fontSize: 14, fontWeight: FontWeight.bold),
                          ),
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
    bool isNumericPin = false,
  }) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))]),
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
          suffixIcon: isPassword ? IconButton(icon: Icon(obscureText ? Icons.visibility_off : Icons.visibility), onPressed: onToggleVisibility) : null,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
          filled: true,
          fillColor: Colors.white,
        ),
        validator: (value) => (value == null || value.isEmpty) ? "Champ requis" : (isNumericPin && value.length != 4 ? "Doit faire 4 chiffres" : null),
      ),
    );
  }
}