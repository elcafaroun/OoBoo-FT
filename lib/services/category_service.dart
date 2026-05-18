import 'dart:convert';
import 'package:http/http.dart' as http;
import '../utils/constants.dart';
import 'database/database_helper.dart';
import 'network_checker.dart';

class CategoryService {
  final DatabaseHelper _dbHelper = DatabaseHelper();

  /// Récupère les catégories d'une structure (Mode Hybride : Online -> Cache Local / Fallback -> Offline Local)
  Future<List<dynamic>> getCategoriesByStructure(String structureId) async {
    // 1. VRAIE vérification de la disponibilité du micro-service
    bool serverIsUp = await NetworkChecker.isBackendAccessible();

    if (serverIsUp) {
      try {
        final url = Uri.parse('$baseUrl/category/structure/$structureId');

        // Timeout ajusté à 5s car le serveur a été détecté comme vivant juste avant
        final response = await http.get(url).timeout(const Duration(seconds: 5));

        if (response.statusCode == 200) {
          final body = jsonDecode(response.body);
          List<dynamic> data = [];

          if (body is List) {
            data = body;
          } else if (body is Map && body.containsKey('data')) {
            data = body['data'] ?? [];
          } else if (body is Map) {
            data = [body];
          }

          // ✅ Mise à jour du cache local pour le fonctionnement hors-ligne ultérieur
          await _dbHelper.syncCategoriesLocal(data);
          return data;
        } else {
          print("⚠️ Le serveur a répondu avec un code d'erreur : ${response.statusCode}");
          // On ne bloque pas, on laisse le flux descendre vers le cache SQLite
        }
      } catch (e) {
        print("⚠️ Micro-coupure réseau ou timeout sur les catégories : $e");
        // En cas de timeout ou crash HTTP, on continue vers le local
      }
    } else {
      print("📡 Le serveur est détecté comme inaccessible par le NetworkChecker.");
    }

    // 2. MODE FALLBACK UNIFIÉ : Exécuté si le serveur est DOWN, si le statut n'est pas 200, ou si la requête a échoué
    print("📥 Mode Offline : Récupération des catégories depuis SQLite pour la structure: $structureId");
    try {
      return await _dbHelper.getLocalEntities('categories', structureId);
    } catch (sqliteError) {
      print("❌ Erreur critique lors de la lecture SQLite de secours : $sqliteError");
      return []; // Renvoie une liste vide plutôt que de faire crasher l'UI
    }
  }
}