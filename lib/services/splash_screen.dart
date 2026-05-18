import 'package:fada/screens/home_screen.dart';
import 'package:fada/screens/subscription_screen.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/structure_service.dart';
import '../services/database/database_helper.dart';

class NavigationService {
  final StructureService _structureService = StructureService();
  final DatabaseHelper _dbHelper = DatabaseHelper();

  /// Gère la redirection intelligente après Login
  Future<void> handlePostLoginNavigation(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final String? userId = prefs.getString('userId');
    final String? profile = prefs.getString('userProfile');
    final String? codeStructure = prefs.getString('codeStructure');

    List<dynamic> structures = [];

    // Sécurité : Si pas de userId, on ne peut pas naviguer correctement
    if (userId == null) {
      debugPrint("⚠️ NavigationService: userId est null");
      if (context.mounted) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const SubscriptionScreen()));
      }
      return;
    }

    try {
      // 1. TENTATIVE VIA API (BACKEND)
      try {
        if (profile == "Administrateur" && (codeStructure ?? '').isEmpty) {
          structures = await _structureService.getStructuresByUser(userId);
        } else if (codeStructure != null && codeStructure.isNotEmpty) {
          structures = await _structureService.getStructuresByCode(codeStructure);
        }

        // Si l'API renvoie des structures, on synchronise le cache local
        if (structures.isNotEmpty) {
          await _dbHelper.syncStructuresLocal(structures);
        }
      } catch (apiError) {
        debugPrint("🌐 Backend injoignable pendant la redirection : $apiError");
      }

      // 2. BASCULE (FALLBACK) : Recherche filtrée par l'ID utilisateur en local
      if (structures.isEmpty) {
        // MISE À JOUR : On utilise le userId pour vérifier l'existence locale
        structures = await _dbHelper.getLocalStructuresByUser(userId);
        debugPrint("📂 SQLite : ${structures.length} structure(s) pour l'utilisateur $userId");
      }

      // 3. LOGIQUE DE NAVIGATION
      if (context.mounted) {
        // Si l'utilisateur a au moins une structure (trouvée en ligne ou en local)
        // OU s'il a un codeStructure (cas des employés/vendeurs)
        if (structures.isNotEmpty || (codeStructure != null && codeStructure.isNotEmpty)) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => const HomeScreen()),
                (route) => false,
          );
        } else {
          // Cas où l'utilisateur n'a absolument rien créé encore
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => const SubscriptionScreen()),
                (route) => false,
          );
        }
      }
    } catch (e) {
      debugPrint("❌ Erreur fatale lors de la redirection : $e");
      if (context.mounted) {
        // Par défaut, on tente le Home pour ne pas bloquer l'utilisateur inutilement
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const HomeScreen()),
              (route) => false,
        );
      }
    }
  }
}