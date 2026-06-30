import 'package:flutter/material.dart';
import 'package:fada/screens/login_screen.dart';
import 'package:fada/screens/register_screen.dart';
import 'package:url_launcher/url_launcher.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  /// 💬 Fonction pour ouvrir la discussion WhatsApp avec l'administrateur
  Future<void> _contactAdmin(BuildContext context) async {
    const String phoneNumber = "+22661616134";
    const String message = "Bonjour, je souhaite contacter l'administrateur de l'application PB-M.";

    final Uri whatsappUrl = Uri.parse(
        "https://wa.me/$phoneNumber?text=${Uri.encodeComponent(message)}"
    );

    try {
      if (await launchUrl(whatsappUrl, mode: LaunchMode.externalApplication)) {
        // Succès du lancement
      } else {
        throw "Impossible d'ouvrir WhatsApp.";
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Impossible d'ouvrir WhatsApp ❌ ($e)"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        // 🎨 Dégradé de fond premium et discret
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFFFFFFF),
              Color(0xFFFEEFE3), // Une touche très légère d'orange pastel en bas
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(flex: 2),

                // 🏷️ Section Identité Visuelle (Logo & Nom)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.12),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.orange.withOpacity(0.05),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          )
                        ],
                      ),
                      child: const Icon(
                        Icons.business_center_rounded,
                        size: 72,
                        color: Colors.orange,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      "PB-M",
                      style: TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF2D3142),
                        letterSpacing: 2.0,
                      ),
                    ),
                  ],
                ),

                const Spacer(),

                // 📝 Message de Bienvenue travaillé
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: RichText(
                    textAlign: TextAlign.center,
                    text: const TextSpan(
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF4C516D),
                        height: 1.6,
                      ),
                      children: [
                        TextSpan(text: "Bienvenue sur l'application "),
                        TextSpan(
                          text: "POKIBOO",
                          style: TextStyle(
                            color: Colors.orange,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        TextSpan(
                          text: " qui vous permet de suivre votre activité en temps réel.",
                        ),
                      ],
                    ),
                  ),
                ),

                const Spacer(flex: 2),

                // 🔘 Boutons d'action modernes
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Bouton Connexion (Plein + Ombre subtile)
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.orange.withOpacity(0.25),
                            blurRadius: 15,
                            offset: const Offset(0, 8),
                          )
                        ],
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => const LoginScreen()),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          // ✅ CORRECTION : Le mot-clé const global de la ligne a été supprimé
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text(
                                "CONNEXION",
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 0.5),
                              ),
                              const SizedBox(width: 10),
                              Icon(Icons.arrow_forward_rounded, color: Colors.white.withOpacity(0.9), size: 20),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Bouton Créer un compte (Bordure épurée)
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const RegisterScreen(isFromLogin: true),
                            ),
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.orange, width: 2),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          backgroundColor: Colors.white.withOpacity(0.6),
                        ),
                        child: const Text(
                          "CRÉER UN COMPTE",
                          style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 0.5),
                        ),
                      ),
                    ),

                    const SizedBox(height: 18),

                    // 💬 Bouton d'assistance WhatsApp vert
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton.icon(
                        onPressed: () => _contactAdmin(context),
                        icon: const Icon(Icons.forum_rounded, color: Colors.white),                        label: const Text(
                          "ASSISTANCE WHATSAPP",
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 0.5),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF25D366), // Vert officiel WhatsApp
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}