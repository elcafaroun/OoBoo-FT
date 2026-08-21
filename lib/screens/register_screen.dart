import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/user_service.dart';
import '../services/network_checker.dart';

class RegisterScreen extends StatefulWidget {
  final bool isFromLogin;

  const RegisterScreen({super.key, this.isFromLogin = false});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController nameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController = TextEditingController();

  String userProfile = "Vente";
  bool isLoading = false;
  bool obscurePassword = true;
  bool obscureConfirm = true;

  // 🌐 États pour le contrôle de l'accès à l'API/Backend au démarrage
  bool _isCheckingConnectivity = true;
  bool _isOnline = false;

  final UserService userService = UserService();

  @override
  void initState() {
    super.initState();
    if (widget.isFromLogin) {
      userProfile = "Super admin";
    }
    _checkInitialConnectivity();
  }

  @override
  void dispose() {
    nameController.dispose();
    phoneController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  /// 🔒 Appel du NetworkChecker avant d'afficher le formulaire
  Future<void> _checkInitialConnectivity() async {
    if (!mounted) return;
    setState(() {
      _isCheckingConnectivity = true;
    });

    final bool backendAccessible = await NetworkChecker.isBackendAccessible();

    if (!mounted) return;
    setState(() {
      _isOnline = backendAccessible;
      _isCheckingConnectivity = false;
    });
  }

  String _generateRandomPin() {
    final random = Random();
    int pin = 1000 + random.nextInt(9000);
    return pin.toString();
  }

  /// 🚨 Modale d'avertissement en cas de limite de quota atteinte
  void _showQuotaLimitDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20.0),
          ),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  "Limite atteinte",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF64748B),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                "Souhaitez-vous passer à une formule supérieure pour ajouter d'autres collaborateurs ?",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1E293B),
                ),
              ),
            ],
          ),
          actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          actions: [
            // 🔘 FERMER : Redirection vers l'écran précédent
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                if (mounted) {
                  Navigator.pop(context);
                }
              },
              child: const Text(
                "Fermer",
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            // 🚀 CHANGER DE PLAN : Redirection vers les Abonnements
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                if (mounted) {
                  Navigator.pushNamed(context, '/subscription');
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text(
                "Changer de plan",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 📝 Envoi du Code PIN d'accès (WhatsApp ou SMS)
  Future<void> _sendAccessCode(String method, String phone, String userName, String pin) async {
    final cleanPhone = phone.replaceAll(' ', '');
    final message = "Bonjour $userName, voici vos accès à l'application POKIBOO.\n\n"
        "Profil : $userProfile\n"
        "Identifiant (Email) : ${emailController.text.trim()}\n"
        "Votre Code PIN secret : *$pin*\n\n"
        "Veuillez modifier votre code dès votre première connexion.";

    Uri url;
    if (method == 'whatsapp') {
      url = Uri.parse("https://wa.me/$cleanPhone?text=${Uri.encodeComponent(message)}");
    } else {
      if (Platform.isAndroid) {
        url = Uri.parse("sms:$cleanPhone?body=${Uri.encodeComponent(message)}");
      } else if (Platform.isIOS) {
        url = Uri.parse("sms:$cleanPhone&body=${Uri.encodeComponent(message)}");
      } else {
        url = Uri.parse("sms:$cleanPhone");
      }
    }

    try {
      if (await launchUrl(url, mode: LaunchMode.externalApplication)) {
        // Succès
      } else {
        throw 'Impossible d\'ouvrir l\'application de messagerie.';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Impossible d'ouvrir l'application sélectionnée ❌ ($e)"),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  /// 💬 Modale de sélection du canal d'envoi (WhatsApp / SMS)
  void _showShareOptions(String phone, String userName, String pin) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (bottomSheetContext) {
        return Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Envoyer les accès au collaborateur",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
              ),
              const SizedBox(height: 5),
              Text(
                "Le code PIN généré est le $pin. Choisissez un canal d'envoi :",
                style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(Icons.message, color: Colors.blue, size: 24),
                title: const Text("Envoyer par SMS", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                onTap: () async {
                  Navigator.pop(bottomSheetContext);
                  await _sendAccessCode('sms', phone, userName, pin);
                  if (mounted) Navigator.pop(context);
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.phone_android, color: Colors.green, size: 24),
                title: const Text("Envoyer par WhatsApp", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                onTap: () async {
                  Navigator.pop(bottomSheetContext);
                  await _sendAccessCode('whatsapp', phone, userName, pin);
                  if (mounted) Navigator.pop(context);
                },
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  /// ⚡ Soumission du formulaire d'enregistrement
  Future<void> handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    if (!await NetworkChecker.isBackendAccessible()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Le serveur est devenu injoignable ou votre connexion a coupé 🌐"),
          backgroundColor: Colors.red,
        ));
      }
      return;
    }

    setState(() => isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      String? codeStructure = prefs.getString('codeStructure');

      if (!widget.isFromLogin && (codeStructure == null || codeStructure.isEmpty)) {
        codeStructure = prefs.getString('selected_structure_id') ?? prefs.getString('current_structure_code');
      }

      if (!widget.isFromLogin && (codeStructure == null || codeStructure.isEmpty)) {
        if (mounted) setState(() => isLoading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text("Erreur : Impossible de lier l'utilisateur à une structure active ❌"),
              backgroundColor: Colors.red
          ));
        }
        return;
      }

      final targetEmail = emailController.text.trim();
      final targetPhone = phoneController.text.trim();
      final targetName = nameController.text.trim();

      if (targetEmail.isNotEmpty) {
        bool emailAvailable = await userService.checkEmailAvailable(targetEmail);
        if (!emailAvailable) {
          if (mounted) setState(() => isLoading = false);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text("Cette adresse e-mail est déjà prise ❌"),
                backgroundColor: Colors.red));
          }
          return;
        }
      }

      bool phoneAvailable = await userService.checkPhoneAvailable(targetPhone);
      if (!phoneAvailable) {
        if (mounted) setState(() => isLoading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text("Ce numéro de téléphone est déjà utilisé ❌"),
              backgroundColor: Colors.red));
        }
        return;
      }

      String finalPassword = widget.isFromLogin ? passwordController.text.trim() : _generateRandomPin();

      debugPrint("🔑 [TEST LOG] Mot de passe / PIN généré pour $targetName : '$finalPassword'");

      final success = await userService.registerUser(
        targetName,
        targetPhone,
        targetEmail,
        finalPassword,
        userProfile,
        widget.isFromLogin ? null : codeStructure,
      );

      if (mounted) setState(() => isLoading = false);

      if (success) {
        if (mounted) {
          if (widget.isFromLogin) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text("Compte Super admin configuré ! Prochaine étape : Créez votre boutique. ✅"),
                backgroundColor: Colors.green
            ));
            Navigator.pop(context);
          } else {
            _showShareOptions(targetPhone, targetName, finalPassword);
          }
        }
      }
    } catch (e) {
      if (mounted) setState(() => isLoading = false);

      // Nettoyage de la chaîne de l'exception
      final String rawError = e.toString()
          .replaceAll("Exception: ", "")
          .replaceAll("Exception", "")
          .trim();

      debugPrint("🚨 [REGISTER ERROR CATCH] : $rawError");

      if (mounted) {
        final String lowerError = rawError.toLowerCase();

        // Interception large du message de limite de quota, d'abonnement ou d'erreur de structure
        if (lowerError.contains("limite") ||
            lowerError.contains("quota") ||
            lowerError.contains("abonnement") ||
            lowerError.contains("maximum")) {
          _showQuotaLimitDialog(rawError);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(rawError.isNotEmpty ? rawError : "Une erreur est survenue lors de l'enregistrement ❌"),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingConnectivity) {
      return const Scaffold(
        backgroundColor: Color(0xFFF8F9FA),
        body: Center(
          child: CircularProgressIndicator(color: Colors.orange),
        ),
      );
    }

    if (!_isOnline) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8F9FA),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Color(0xFF1E293B)),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20.0),
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
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.cloud_off_rounded, size: 64, color: Colors.orange),
                  const SizedBox(height: 20),
                  const Text(
                    "Serveur Central Injoignable",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    "L'application n'arrive pas à joindre les services de synchronisation réseau. L'enregistrement de nouveaux comptes est désactivé en mode hors-ligne pour préserver la cohérence des structures.",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: Color(0xFF64748B), height: 1.5),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 46,
                    child: ElevatedButton.icon(
                      onPressed: _checkInitialConnectivity,
                      icon: const Icon(Icons.sync_rounded, color: Colors.white, size: 16),
                      label: const Text("TENTER UNE RECONNEXION", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Text(
          widget.isFromLogin ? "Initialisation Super admin" : "Nouvel Utilisateur",
          style: const TextStyle(color: Color(0xFF1E293B), fontWeight: FontWeight.bold, fontSize: 16),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Color(0xFF1E293B)),
      ),
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
                            Text(
                              widget.isFromLogin ? "CONFIGURATION ADMIN" : "CRÉATION DE COMPTE",
                              style: const TextStyle(
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
                    const Divider(color: Color(0xFFF1F5F9), thickness: 1),
                    const SizedBox(height: 16),

                    // 📝 Champs du Formulaire
                    _buildTextField(nameController, 'Nom complet', Icons.person_outline_rounded, TextInputType.name),
                    const SizedBox(height: 12),
                    _buildTextField(phoneController, 'Téléphone', Icons.phone_outlined, TextInputType.phone),
                    const SizedBox(height: 12),
                    _buildTextField(emailController, 'Adresse Email (Optionnel)', Icons.email_outlined, TextInputType.emailAddress),

                    if (widget.isFromLogin) ...[
                      const SizedBox(height: 12),
                      _buildPasswordField(passwordController, 'Code PIN (4 chiffres)', obscurePassword, () => setState(() => obscurePassword = !obscurePassword)),
                      const SizedBox(height: 12),
                      _buildPasswordField(confirmPasswordController, 'Confirmer le Code PIN', obscureConfirm, () => setState(() => obscureConfirm = !obscureConfirm), isConfirm: true),
                    ] else ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.orange.withOpacity(0.2)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.info_outline_rounded, color: Colors.orange, size: 18),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                "Le code PIN sera généré automatiquement et pourra être envoyé par WhatsApp ou SMS.",
                                style: TextStyle(color: Color(0xFF475569), fontSize: 11, fontWeight: FontWeight.w500, height: 1.3),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),

                    if (!widget.isFromLogin) ...[
                      const Text("Type de profil d'accès :", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF1E293B))),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8F9FA),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          children: [
                            _buildRadio("Administrateur"),
                            _buildRadio("Vente"),
                            _buildRadio("Gestionnaire de stock"),
                          ],
                        ),
                      ),
                    ] else ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8F9FA),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.admin_panel_settings_rounded, color: Colors.orange, size: 18),
                            SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("Profil assigné : Super admin", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF1E293B))),
                                Text("Gestionnaire suprême de la plateforme.", style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),

                    // 🔘 Bouton Soumission
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: ElevatedButton(
                        onPressed: isLoading ? null : handleRegister,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: isLoading
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(widget.isFromLogin ? Icons.check_circle_outline_rounded : Icons.send_rounded, color: Colors.white, size: 16),
                            const SizedBox(width: 8),
                            Text(
                              widget.isFromLogin ? 'INITIALISER MON COMPTE' : 'GÉNÉRER & ENVOYER',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5),
                            ),
                          ],
                        ),
                      ),
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

  Widget _buildTextField(TextEditingController controller, String label, IconData icon, TextInputType type) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: TextFormField(
        controller: controller,
        keyboardType: type,
        style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B)),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
          prefixIcon: Icon(icon, color: Colors.orange, size: 18),
          filled: true,
          fillColor: Colors.transparent,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        ),
        validator: (val) {
          if (val == null || val.trim().isEmpty) {
            if (label.contains('Optionnel')) return null;
            return 'Champ requis';
          }
          if (label.contains('Email') && !val.contains('@')) return 'Email invalide';
          return null;
        },
      ),
    );
  }

  Widget _buildPasswordField(TextEditingController controller, String label, bool obscure, VoidCallback toggle, {bool isConfirm = false}) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: TextFormField(
        controller: controller,
        obscureText: obscure,
        keyboardType: TextInputType.number,
        maxLength: 4,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B)),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
          prefixIcon: Icon(isConfirm ? Icons.lock_outline_rounded : Icons.lock_rounded, color: Colors.orange, size: 18),
          suffixIcon: IconButton(
            icon: Icon(obscure ? Icons.visibility_off : Icons.visibility, color: const Color(0xFF64748B), size: 18),
            onPressed: toggle,
          ),
          filled: true,
          fillColor: Colors.transparent,
          counterText: "",
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        ),
        validator: (val) {
          if (val == null || val.isEmpty) return 'Champ requis';
          if (val.length != 4) return 'Doit faire 4 chiffres';
          if (isConfirm && val != passwordController.text) return 'Les codes diffèrent';
          return null;
        },
      ),
    );
  }

  Widget _buildRadio(String value) {
    return RadioListTile<String>(
      title: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF1E293B))),
      value: value,
      groupValue: userProfile,
      activeColor: Colors.orange,
      dense: true,
      onChanged: (val) => setState(() => userProfile = val!),
    );
  }
}