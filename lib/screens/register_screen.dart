import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
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

  String userProfile = "Administrateur";
  bool isLoading = false;
  bool obscurePassword = true;
  bool obscureConfirm = true;

  final UserService userService = UserService();

  @override
  void initState() {
    super.initState();
    if (widget.isFromLogin) userProfile = "Administrateur";
  }

  Future<void> handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    final List<ConnectivityResult> connectivityResult = await (Connectivity().checkConnectivity());
    if (connectivityResult.contains(ConnectivityResult.none)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Pas de connexion internet 🌐"), backgroundColor: Colors.red));
      }
      return;
    }

    setState(() => isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final String? structureId = prefs.getString('selected_structure_id');
      //final String? codeStructure = prefs.getString('selected_structure_id');


      final success = await userService.registerUser(
        nameController.text.trim(),
        phoneController.text.trim(),
        emailController.text.trim(),
        passwordController.text.trim(),
        userProfile,
        structureId,
      );

      setState(() => isLoading = false);
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Compte créé avec succès ✅"), backgroundColor: Colors.green));
        Navigator.pop(context);
      } else {
        throw Exception();
      }
    } catch (e) {
      setState(() => isLoading = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Erreur lors de l'inscription ❌"), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F7F2), // Fond crème Pro
      appBar: AppBar(
        title: const Text("Inscription", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
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
              _buildTextField(emailController, 'Adresse Email', Icons.email, TextInputType.emailAddress),
              _buildPasswordField(passwordController, 'Mot de passe', obscurePassword, () => setState(() => obscurePassword = !obscurePassword)),
              _buildPasswordField(confirmPasswordController, 'Confirmer MDP', obscureConfirm, () => setState(() => obscureConfirm = !obscureConfirm), isConfirm: true),

              const SizedBox(height: 20),
              if (!widget.isFromLogin) ...[
                const Text("  Type de profil :", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
                const SizedBox(height: 10),
                Container(
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))]),
                  child: Column(children: [_buildRadio("Administrateur"), _buildRadio("Vente"), _buildRadio("Gestionnaire de stock")]),
                ),
              ] else ...[
                ListTile(leading: const Icon(Icons.admin_panel_settings, color: Colors.orange), title: const Text("Profil : Administrateur"), subtitle: const Text("Vous créez le compte principal.")),
              ],

              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity, height: 55,
                child: ElevatedButton(
                  onPressed: isLoading ? null : handleRegister,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), elevation: 0),
                  child: isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text('S\'INSCRIRE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
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
      validator: (val) => (val == null || val.isEmpty) ? 'Requis' : (label == 'Adresse Email' && !val.contains('@') ? 'Email invalide' : null),
    ),
  );

  Widget _buildPasswordField(TextEditingController controller, String label, bool obscure, VoidCallback toggle, {bool isConfirm = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 15),
    child: TextFormField(
      controller: controller, obscureText: obscure,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(isConfirm ? Icons.lock_outline : Icons.lock, color: Colors.orange),
        suffixIcon: IconButton(icon: Icon(obscure ? Icons.visibility_off : Icons.visibility, color: Colors.orange), onPressed: toggle),
        filled: true, fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 15),
      ),
      validator: (val) => (val == null || val.isEmpty) ? 'Requis' : (isConfirm && val != passwordController.text ? "Mots de passe différents" : null),
    ),
  );

  Widget _buildRadio(String value) => RadioListTile<String>(title: Text(value, style: const TextStyle(fontWeight: FontWeight.w500)), value: value, groupValue: userProfile, activeColor: Colors.orange, onChanged: (val) => setState(() => userProfile = val!));
}