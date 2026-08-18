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

      // Extraction de l'ID de structure si disponible
      final String structureId = (structures.isNotEmpty && structures.first['id'] != null)
          ? structures.first['id'].toString()
          : codeStructure;

      if (structures.isEmpty && codeStructure.isEmpty) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => SubscriptionScreen(
              structureId: structureId,

            ),
          ),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const HomeScreen()),
        );
      }
    } catch (e) {
      debugPrint('⚠️ Erreur de pré-chargement des structures (Bascule locale automatique) : $e');
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const HomeScreen()),
      );
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
            'userProfile': profileValue,
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
            'userProfile': profileValue,
            'codeStructure': codeStructure,
            'codeUser': userData['codeUser'] ?? password,
            'isActive': 1,
            'updatedAt': DateTime.now().toIso8601String(),
          };
          await DatabaseHelper().saveOrUpdateUserLocal(localUserMap);
          debugPrint("🔄 [Sync Arrière-plan] Données utilisateur synchronisées.");
        }
      }
    } catch (e) {
      debugPrint("⚠️ [Sync Arrière-plan] Échec silencieux : $e");
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
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
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
                    child: _isDialogLoading ? const CircularProgressIndicator(color: Colors.white) : const Text("VALIDER MON NOUVEAU PIN", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
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
    await prefs.setString('userName', data['userName'] ?? '');
    await prefs.setString('userProfile', data['userProfile'] ?? 'SUPER_ADMIN');
    await prefs.setString('codeStructure', codeStructure);
    await prefs.setString('selected_structure_id', codeStructure);
    await prefs.setString('last_sync_date', data['updatedAt'] ?? 'Jamais');
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
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 440),
              padding: const EdgeInsets.all(24.0),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24.0),
                border: Border.all(color: Colors.grey.shade200, width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 🏢 Badge SaaS Header
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.orange.withOpacity(0.2)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: Colors.orange,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              "ESPACE SÉCURISÉ SaaS",
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Colors.orange,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 18),

                    // 🏷️ Logo & Nom de la marque
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.business_center_rounded,
                            size: 40,
                            color: Colors.orange,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          "POKIBOO",
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF1E293B),
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          "Connectez-vous à votre tableau de bord",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 22),
                    const Divider(color: Color(0xFFF1F5F9), thickness: 1),
                    const SizedBox(height: 16),

                    // 📝 Champs du Formulaire
                    _buildTextField(
                      controller: _loginController,
                      label: "Identifiant",
                      icon: Icons.person_outline_rounded,
                    ),
                    const SizedBox(height: 14),
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

                    const SizedBox(height: 24),

                    // 🔘 Bouton Connexion Compact
                    _isLoading
                        ? const Center(child: CircularProgressIndicator(color: Colors.orange))
                        : SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: ElevatedButton(
                        onPressed: _login,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.login_rounded, color: Colors.white, size: 16),
                            SizedBox(width: 8),
                            Text(
                              "SE CONNECTER",
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Liens bas de page
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
                            style: TextStyle(color: Color(0xFF64748B), fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
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
                            style: TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
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
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: TextFormField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        maxLength: isNumericPin ? 4 : null,
        inputFormatters: isNumericPin ? [FilteringTextInputFormatter.digitsOnly] : null,
        style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B)),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
          prefixIcon: Icon(icon, color: Colors.orange, size: 18),
          counterText: "",
          suffixIcon: isPassword
              ? IconButton(
            icon: Icon(obscureText ? Icons.visibility_off : Icons.visibility, size: 18, color: Color(0xFF64748B)),
            onPressed: onToggleVisibility,
          )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        validator: (value) => (value == null || value.isEmpty)
            ? "Champ requis"
            : (isNumericPin && value.length != 4 ? "Doit faire 4 chiffres" : null),
      ),
    );
  }
}