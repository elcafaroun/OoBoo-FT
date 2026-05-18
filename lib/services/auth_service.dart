import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/constants.dart';
import 'database/database_helper.dart';
import 'network_checker.dart'; // 👈 IMPORT DU NOUVEAU CHECKER

class AuthService {
  final DatabaseHelper _dbHelper = DatabaseHelper();

  Future<Map<String, dynamic>> login(String identifier, String password) async {
    final url = Uri.parse('$baseUrl/user/login');

    // 1. VRAIE vérification de la disponibilité des micro-services
    bool serverIsUp = await NetworkChecker.isBackendAccessible();

    if (serverIsUp) {
      try {
        print('➡️ VRAI Mode Online : Envoi à $url');
        final response = await http.post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'identifier': identifier,
            'password': password,
          }),
        ).timeout(const Duration(seconds: 5)); // Le checker est passé, on peut mettre 5s de timeout sereinement

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          String? userId = _extractUserId(data);

          if (userId != null) {
            // ✅ MISE À JOUR DU CACHE LOCAL
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
        } else {
          print('🚫 Erreur d\'authentification serveur : ${response.statusCode}');
          // Optionnel : Si le serveur répond 401/403 (mauvais mot de passe),
          // on ne veut pas forcément basculer sur le offline si l'utilisateur s'est trompé.
          // Mais si c'est une erreur 500 (crash micro-service), on laisse le flux glisser vers le offline.
          if (response.statusCode == 401 || response.statusCode == 403) {
            throw Exception('❌ Identifiants invalides.');
          }
        }
      } catch (e) {
        print('⚠️ Problème survenu pendant la requête vers le micro-service : $e');
        // En cas de coupure de courant ou micro-coupure réseau au moment précis de la requête
      }
    }

    // 2. MODE FALLBACK AUTOMATIQUE (Si serveur Down OU si la requête en ligne a échoué)
    print('📥 Basculement : Tentative de connexion via SQLite (Mode Offline)...');
    final localUser = await _dbHelper.getUserByIdentifier(identifier);

    if (localUser != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('userId', localUser['id'].toString());

      print('💾 Connexion réussie via base locale pour : $identifier');
      return localUser;
    }

    // 3. ÉCHEC TOTAL
    throw Exception('❌ Serveur indisponible et aucun compte local trouvé pour cet identifiant.');
  }

  String? _extractUserId(Map<String, dynamic> data) {
    if (data['id'] != null) return data['id'].toString();
    if (data['user'] != null && data['user']['id'] != null) return data['user']['id'].toString();
    if (data['data'] != null && data['data']['id'] != null) return data['data']['id'].toString();
    return null;
  }
}