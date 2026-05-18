import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/constants.dart';
import 'database/database_helper.dart';
import 'network_checker.dart'; // 👈 Centralise la vérification de disponibilité des micro-services

class UserService {
  final DatabaseHelper _dbHelper = DatabaseHelper();

  /// 🔹 Enregistrement (Supporte le code structure optionnel)
  Future<bool> registerUser(String name, String phone, String email, String password, String profile, String? codeStructure) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/user'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userName': name,
          'userPhone': phone,
          'userEmail': email,
          'userPassword': password,
          'userProfile': profile,
          'codeStructure': codeStructure ?? "",
        }),
      );
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      print("Erreur inscription : $e");
      return false;
    }
  }

  /// 🔹 Connexion Hybride (Online avec Cache / Fallback Offline via SQLite)
  Future<Map<String, dynamic>> login(String identifier, String password) async {
    // 1. Vérification réelle de l'accessibilité du micro-service
    bool serverIsUp = await NetworkChecker.isBackendAccessible();

    if (serverIsUp) {
      try {
        print('➡️ Mode Online : Envoi des identifiants au backend');
        final response = await http.post(
          Uri.parse('$baseUrl/user/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'identifier': identifier, 'password': password}),
        ).timeout(const Duration(seconds: 5));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          String? userId = _extractUserId(data);

          if (userId != null) {
            // ✅ MISE À JOUR DU CACHE SQLITE LOCAL
            await _dbHelper.saveOrUpdateUserLocal({
              'id': userId,
              'userName': data['userName'] ?? identifier,
              'userEmail': data['userEmail'],
              'userPhone': data['userPhone'],
              'userProfile': data['userProfile'],
              'codeStructure': data['codeStructure'],
              'isActive': 1,
              'updatedAt': DateTime.now().toIso8601String(),
            });

            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('userId', userId);

            return data;
          }
        } else if (response.statusCode == 401 || response.statusCode == 403) {
          print('🚫 Identifiants incorrects sur le serveur');
          throw Exception('❌ Identifiants invalides.');
        }
      } catch (e) {
        print('⚠️ Micro-coupure ou problème lors de la requête en ligne : $e');
        // On laisse le code continuer vers le mode hors-ligne en dessous
      }
    }

    // 2. MODE FALLBACK AUTOMATIQUE (Exécuté si serveur DOWN ou si la requête a échoué)
    print('📥 Basculement : Tentative de connexion via SQLite (Mode Offline)...');
    final localUser = await _dbHelper.getUserByIdentifier(identifier);

    if (localUser != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('userId', localUser['id'].toString());

      print('💾 Connexion réussie hors-ligne via SQLite pour : $identifier');

      // On retourne la structure attendue par l'UI, simulée depuis SQLite
      return Map<String, dynamic>.from(localUser);
    }

    // 3. ÉCHEC TOTAL
    throw Exception('❌ Connexion impossible. Serveur injoignable et aucun identifiant local correspondant.');
  }

  /// 🔹 Récupérer les utilisateurs d'une structure
  Future<List<dynamic>> getAllUsersByStructure(String codeStructure) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/user/structure/$codeStructure'),
        headers: {'Content-Type': 'application/json'},
      );
      return response.statusCode == 200 ? jsonDecode(response.body) : [];
    } catch (e) {
      print("Erreur récupération utilisateurs : $e");
      return [];
    }
  }

  /// 🔹 Modifier un utilisateur
  Future<bool> updateUser(String id, Map<String, dynamic> userData) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/user/update/$id'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(userData),
      );
      return response.statusCode == 200;
    } catch (e) {
      print("Erreur modification utilisateur : $e");
      return false;
    }
  }

  /// 🔹 Activer/Désactiver
  Future<bool> toggleUserStatus(String id, bool shouldEnable) async {
    try {
      final String action = shouldEnable ? "enable" : "disable";
      final response = await http.patch(
        Uri.parse('$baseUrl/user/$action/$id'),
        headers: {'Content-Type': 'application/json'},
      );
      return response.statusCode == 200 || response.statusCode == 204;
    } catch (e) {
      print("Erreur changement de statut : $e");
      return false;
    }
  }

  /// 🔹 Réinitialiser le mot de passe
  Future<bool> resetPassword(String userId, String newPassword) async {
    try {
      final response = await http.patch(
        Uri.parse('$baseUrl/user/reset-password/$userId'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'newPassword': newPassword}),
      );
      return response.statusCode == 200;
    } catch (e) {
      print("Erreur réinitialisation mot de passe : $e");
      return false;
    }
  }

  /// 🔹 Outil interne pour extraire l'ID utilisateur de formats JSON variés
  String? _extractUserId(Map<String, dynamic> data) {
    if (data['id'] != null) return data['id'].toString();
    if (data['user'] != null && data['user']['id'] != null) return data['user']['id'].toString();
    if (data['data'] != null && data['data']['id'] != null) return data['data']['id'].toString();
    return null;
  }
}