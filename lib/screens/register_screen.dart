import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/user_service.dart';

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

  final UserService userService = UserService();

  @override
  void initState() {
    super.initState();
    if (widget.isFromLogin) {
      userProfile = "Super admin";
    }
  }

  String _generateRandomPin() {
    final random = Random();
    int pin = 1000 + random.nextInt(9000);
    return pin.toString();
  }

  /// 📝 Envoi du Code PIN d'accès (WhatsApp ou SMS) pour les collaborateurs de l'application PB-M
  Future<void> _sendAccessCode(String method, String phone, String userName, String pin) async {
    final cleanPhone = phone.replaceAll(' ', '');
    final message = "Bonjour $userName, voici vos accès à l'application PB-M.\n\n"
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
        // Succès du lancement
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

  /// 💬 Modale de sélection pour le canal d'envoi (WhatsApp / SMS)
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
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 5),
              Text(
                "Le code PIN généré est le $pin. Choisissez un canal d'envoi :",
                style: const TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(Icons.message, color: Colors.blue, size: 30),
                title: const Text("Envoyer par SMS", style: TextStyle(fontWeight: FontWeight.bold)),
                onTap: () async {
                  Navigator.pop(bottomSheetContext); // Ferme la modale proprement
                  await _sendAccessCode('sms', phone, userName, pin);
                  if (mounted) Navigator.pop(context); // Quitte l'écran de création
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.phone_android, color: Colors.green, size: 30),
                title: const Text("Envoyer par WhatsApp", style: TextStyle(fontWeight: FontWeight.bold)),
                onTap: () async {
                  Navigator.pop(bottomSheetContext); // Ferme la modale proprement
                  await _sendAccessCode('whatsapp', phone, userName, pin);
                  if (mounted) Navigator.pop(context); // Quitte l'écran de création
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

    final List<ConnectivityResult> connectivityResult = await (Connectivity().checkConnectivity());
    if (connectivityResult.contains(ConnectivityResult.none)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Pas de connexion internet pour l'initialisation ou l'affectation 🌐"),
          backgroundColor: Colors.red,
        ));
      }
      return;
    }

    setState(() => isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      String? codeStructure = prefs.getString('codeStructure');

      // Récupération intelligente et fallback si la structure par défaut est stockée différemment
      if (!widget.isFromLogin && (codeStructure == null || codeStructure.isEmpty)) {
        codeStructure = prefs.getString('selected_structure_id') ?? prefs.getString('current_structure_code');
      }

      // Sécurité : Un collaborateur doit impérativement posséder un code structure d'affectation
      if (!widget.isFromLogin && (codeStructure == null || codeStructure.isEmpty)) {
        setState(() => isLoading = false);
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

      // 🔍 1. Vérification d'unicité de l'E-mail (si renseigné)
      if (targetEmail.isNotEmpty) {
        bool emailAvailable = await userService.checkEmailAvailable(targetEmail);
        if (!emailAvailable) {
          setState(() => isLoading = false);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text("Cette adresse e-mail est déjà prise ❌"),
                backgroundColor: Colors.red));
          }
          return;
        }
      }

      // 🔍 2. Vérification d'unicité du Téléphone
      bool phoneAvailable = await userService.checkPhoneAvailable(targetPhone);
      if (!phoneAvailable) {
        setState(() => isLoading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text("Ce numéro de téléphone est déjà utilisé ❌"),
              backgroundColor: Colors.red));
        }
        return;
      }

      // Définition ou génération du mot de passe (PIN)
      String finalPassword;
      if (widget.isFromLogin) {
        finalPassword = passwordController.text.trim();
      } else {
        finalPassword = _generateRandomPin();
      }

      // 📡 Envoi au service backend (Liaison via Query Parameter conforme)
      final success = await userService.registerUser(
        targetName,
        targetPhone,
        targetEmail,
        finalPassword,
        userProfile,
        widget.isFromLogin ? null : codeStructure,
      );

      setState(() => isLoading = false);

      if (success) {
        if (mounted) {
          if (widget.isFromLogin) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text("Compte Super admin configuré ! Prochaine étape : Créez votre boutique. ✅"),
                backgroundColor: Colors.green
            ));
            Navigator.pop(context);
          } else {
            // Ouvrir le BottomSheet d'options d'envoi (SMS / WhatsApp) pour les collaborateurs
            _showShareOptions(targetPhone, targetName, finalPassword);
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text("Erreur lors de l'enregistrement de l'utilisateur par le serveur ❌"),
              backgroundColor: Colors.red
          ));
        }
      }
    } catch (e) {
      setState(() => isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Une erreur technique est survenue : $e"),
            backgroundColor: Colors.red
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F7F2),
      appBar: AppBar(
        title: Text(
            widget.isFromLogin ? "Initialisation Super admin" : "Nouvel Utilisateur",
            style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTextField(nameController, 'Nom complet', Icons.person, TextInputType.name),
              _buildTextField(phoneController, 'Téléphone', Icons.phone, TextInputType.phone),
              _buildTextField(emailController, 'Adresse Email (Optionnel)', Icons.email, TextInputType.emailAddress),

              if (widget.isFromLogin) ...[
                _buildPasswordField(passwordController, 'Code PIN (4 chiffres)', obscurePassword, () => setState(() => obscurePassword = !obscurePassword)),
                _buildPasswordField(confirmPasswordController, 'Confirmer le Code PIN', obscureConfirm, () => setState(() => obscureConfirm = !obscureConfirm), isConfirm: true),
              ] else ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 15, left: 5, right: 5),
                  child: Container(
                    decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange.withOpacity(0.3))
                    ),
                    child: const ListTile(
                      leading: Icon(Icons.info_outline, color: Colors.orange),
                      title: Text(
                        "Le mot de passe d'accès sera un code PIN à 4 chiffres généré automatiquement. Vous pourrez l'envoyer par WhatsApp ou SMS à la fin.",
                        style: TextStyle(color: Colors.black87, fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 10),
              if (!widget.isFromLogin) ...[
                const Text("  Type de profil d'accès :", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
                const SizedBox(height: 10),
                Container(
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))]
                  ),
                  child: Column(children: [
                    _buildRadio("Administrateur"),
                    _buildRadio("Vente"),
                    _buildRadio("Gestionnaire de stock")
                  ]),
                ),
              ] else ...[
                const ListTile(
                    leading: Icon(Icons.admin_panel_settings, color: Colors.orange),
                    title: Text("Profil assigné : Super admin"),
                    subtitle: Text("Gestionnaire suprême de la plateforme.")
                ),
              ],

              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity, height: 55,
                child: ElevatedButton(
                  onPressed: isLoading ? null : handleRegister,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      elevation: 0
                  ),
                  child: isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(
                      widget.isFromLogin ? 'INITIALISER MON COMPTE' : 'GÉNÉRER LES ACCÈS & ENVOYER',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, IconData icon, TextInputType type) => Padding(
    padding: const EdgeInsets.only(bottom: 15),
    child: TextFormField(
      controller: controller,
      keyboardType: type,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Colors.orange),
        filled: true, fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 15),
      ),
      validator: (val) {
        if (val == null || val.trim().isEmpty) {
          if (label.contains('Optionnel')) return null;
          return 'Requis';
        }
        if (label.contains('Email') && !val.contains('@')) return 'Email invalide';
        return null;
      },
    ),
  );

  Widget _buildPasswordField(TextEditingController controller, String label, bool obscure, VoidCallback toggle, {bool isConfirm = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 15),
    child: TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: TextInputType.number,
      maxLength: 4,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(isConfirm ? Icons.lock_outline : Icons.lock, color: Colors.orange),
        suffixIcon: IconButton(icon: Icon(obscure ? Icons.visibility_off : Icons.visibility, color: Colors.orange), onPressed: toggle),
        filled: true, fillColor: Colors.white,
        counterText: "",
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 15),
      ),
      validator: (val) {
        if (val == null || val.isEmpty) return 'Requis';
        if (val.length != 4) return 'Le code PIN doit contenir exactement 4 chiffres';
        if (isConfirm && val != passwordController.text) return 'Mots de passe différents';
        return null;
      },
    ),
  );

  Widget _buildRadio(String value) => RadioListTile<String>(
      title: Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
      value: value,
      groupValue: userProfile,
      activeColor: Colors.orange,
      onChanged: (val) => setState(() => userProfile = val!)
  );
}