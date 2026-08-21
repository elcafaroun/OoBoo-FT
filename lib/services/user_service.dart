import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/constants.dart';
import 'database/database_helper.dart';
import 'network_checker.dart';

class UserService {
  final DatabaseHelper _dbHelper = DatabaseHelper();

  Future<bool> registerUser(
      String name,
      String phone,
      String email,
      String password,
      String profile,
      String? codeStructure,
      ) async {
    bool isOnline = await NetworkChecker.isBackendAccessible();
    if (!isOnline) {
      throw Exception(
        "OFFLINE_ERROR|Connexion Internet requise. L'enregistrement des utilisateurs ne peut pas se faire hors-ligne.",
      );
    }

    try {
      // 2️⃣ Construction de l'URL avec Query Parameter
      final String urlString =
      (codeStructure != null && codeStructure.trim().isNotEmpty)
          ? '$baseUrl/user?codeStructure=${Uri.encodeComponent(codeStructure.trim())}'
          : '$baseUrl/user';

      // 3️⃣ Envoi de la requête HTTP
      final response = await http
          .post(
        Uri.parse(urlString),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userName': name,
          'userPhone': phone,
          'userEmail': email,
          'userPassword': password,
          'userProfile': profile,
        }),
      )
          .timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception("TIMEOUT_ERROR|Le serveur met trop de temps à répondre.");
        },
      );

      // 4️⃣ Traitement de la réponse
      if (response.statusCode == 200 || response.statusCode == 201) {
        return true;
      } else {
        String errorMessage = "Erreur d'enregistrement (${response.statusCode})";
        String errorCode = "UNKNOWN_ERROR";

        if (response.body.isNotEmpty) {
          try {
            final decoded = jsonDecode(utf8.decode(response.bodyBytes));
            errorMessage = decoded['message'] ?? response.body;
            errorCode = decoded['code'] ?? "HTTP_${response.statusCode}";
          } catch (_) {
            errorMessage = response.body;
          }
        }
        // Formatage standardisé 'CODE|MESSAGE' pour l'UI
        throw Exception("$errorCode|$errorMessage");
      }
    } catch (e) {
      debugPrint(" Erreur enregistrement utilisateur online : $e");
      rethrow; // Propagation pour capture dans l'UI
    }
  }

  /// 🔹 Vérifier la disponibilité d'un Email auprès de l'API Spring Boot
  Future<bool> checkEmailAvailable(String email) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/user/check-email?email=${Uri.encodeComponent(email.trim())}'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final dynamic data = jsonDecode(response.body);
        if (data is Map) {
          return data['available'] ?? false;
        } else if (data is bool) {
          return data;
        }
      }
      return false;
    } catch (e) {
      debugPrint("Erreur lors de la vérification de l'email : $e");
      return false;
    }
  }

  /// 🔹 Vérifier la disponibilité d'un Numéro de Téléphone auprès de l'API Spring Boot
  Future<bool> checkPhoneAvailable(String phone) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/user/check-phone?phone=${Uri.encodeComponent(phone.trim())}'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final dynamic data = jsonDecode(response.body);
        if (data is Map) {
          return data['available'] ?? false;
        } else if (data is bool) {
          return data;
        }
      }
      return false;
    } catch (e) {
      debugPrint("Erreur lors de la vérification du téléphone : $e");
      return false;
    }
  }

  /// 🔹 Connexion Hybride (Online Multi-structure / Fallback Offline)
  Future<Map<String, dynamic>> login(String identifier, String password) async {
    bool serverIsUp = await NetworkChecker.isBackendAccessible();

    if (serverIsUp) {
      try {
        debugPrint('➡️ Mode Online : Envoi des identifiants au backend');
        final response = await http.post(
          Uri.parse('$baseUrl/user/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'identifier': identifier, 'password': password}),
        ).timeout(const Duration(seconds: 5));

        if (response.statusCode == 200) {
          final data = jsonDecode(utf8.decode(response.bodyBytes));
          String? userId = _extractUserId(data);

          if (userId != null) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('userId', userId);

            final String? profile = data['userProfile'];
            if (profile != null) {
              await prefs.setString('userProfile', profile);
            }

            List<dynamic> userStructures = data['structures'] ?? [];
            String? defaultCodeStructure;
            String? defaultRole;

            if (userStructures.isNotEmpty) {
              final firstStruct = userStructures.first;
              defaultCodeStructure = firstStruct['codeStructure'];
              defaultRole = firstStruct['roleInStructure'];

              await prefs.setString('codeStructure', defaultCodeStructure ?? "");
              await prefs.setString('userRoleInStructure', defaultRole ?? "");
              await prefs.setString('cached_user_structures', jsonEncode(userStructures));
            }

            // ✅ Synchronisation SQLite locale
            await _dbHelper.saveOrUpdateUserLocal({
              'id': userId,
              'userName': data['userName'] ?? identifier,
              'userEmail': data['userEmail'],
              'userPhone': data['userPhone'],
              'userProfile': profile,
              'codeStructure': defaultCodeStructure,
              'codeUser': data['codeUser'],
              'isActive': 1,
              'updatedAt': DateTime.now().toIso8601String(),
            });

            if (data['codeUser'] != null) {
              await prefs.setString('codeUser', data['codeUser'].toString());
            }

            return data;
          }
        } else if (response.statusCode == 401 || response.statusCode == 403) {
          debugPrint('🚫 Identifiants incorrects sur le serveur');
          throw Exception('INVALID_CREDENTIALS|Identifiants invalides.');
        }
      } catch (e) {
        debugPrint('⚠️ Micro-coupure ou problème lors de la requête en ligne : $e');
      }
    }

    // 2️⃣ MODE FALLBACK AUTOMATIQUE OFFLINE
    debugPrint('📥 Basculement : Tentative de connexion via SQLite (Mode Offline)...');
    final localUser = await _dbHelper.getUserByIdentifier(identifier);

    if (localUser != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('userId', localUser['id'].toString());

      if (localUser['userProfile'] != null) {
        await prefs.setString('userProfile', localUser['userProfile'].toString());
      }
      if (localUser['codeUser'] != null) {
        await prefs.setString('codeUser', localUser['codeUser'].toString());
      }
      if (localUser['codeStructure'] != null) {
        await prefs.setString('codeStructure', localUser['codeStructure'].toString());
      }

      debugPrint('💾 Connexion réussie hors-ligne via SQLite pour : $identifier');
      return Map<String, dynamic>.from(localUser);
    }

    throw Exception('OFFLINE_LOGIN_FAILED|Connexion impossible. Serveur injoignable et aucun identifiant local correspondant.');
  }

  Future<List<dynamic>> getAllUsersByStructure(String codeStructure) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/user/users/$codeStructure'),
        headers: {'Content-Type': 'application/json'},
      );

      debugPrint("DEBUG JSON REÇU : ${response.body}");

      if (response.statusCode == 200) {
        return jsonDecode(utf8.decode(response.bodyBytes));
      } else {
        return [];
      }
    } catch (e) {
      debugPrint("Erreur récupération : $e");
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
      debugPrint("Erreur modification utilisateur : $e");
      return false;
    }
  }

  /// 🔹 Activer/Désactiver l'accès d'un compte utilisateur
  Future<bool> toggleUserStatus(String id, bool shouldEnable) async {
    final String action = shouldEnable ? "enable" : "disable";

    try {
      final response = await http.patch(
        Uri.parse('$baseUrl/user/$action/$id'),
        headers: {'Content-Type': 'application/json'},
      );
      return response.statusCode == 200 || response.statusCode == 204;
    } catch (e) {
      debugPrint("Erreur changement de statut : $action - $e");
      return false;
    }
  }

  /// 🔹 Réinitialiser le mot de passe d'un utilisateur
  Future<bool> resetPassword(String userId, String newPassword) async {
    try {
      final response = await http.patch(
        Uri.parse('$baseUrl/user/reset-password/$userId'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'newPassword': newPassword}),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint("Erreur réinitialisation mot de passe : $e");
      return false;
    }
  }

  /// 🔹 Mettre à jour le mot de passe initial
  Future<bool> changeFirstPassword(String userId, String newPassword) async {
    try {
      final response = await http.patch(
        Uri.parse('$baseUrl/user/change-password/$userId'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'newPassword': newPassword}),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint("Erreur changement premier mot de passe : $e");
      return false;
    }
  }

  Future<void> disableUser(String userId) async {
    final url = Uri.parse('$baseUrl/user/disable/$userId');
    debugPrint("🚀 Tentative d'appel à l'URL : $url");
    try {
      final response = await http.patch(url);
      if (response.statusCode == 204) {
        debugPrint("✅ Utilisateur désactivé avec succès");
      } else {
        debugPrint("❌ Erreur serveur (${response.statusCode}) : ${response.body}");
      }
    } catch (e) {
      debugPrint("❌ Exception : $e");
    }
  }

  /// 🔹 Utilitaire d'extraction d'ID utilisateur dans les payloads
  String? _extractUserId(Map<String, dynamic> data) {
    if (data['id'] != null) return data['id'].toString();
    if (data['user'] != null && data['user']['id'] != null) return data['user']['id'].toString();
    if (data['data'] != null && data['data']['id'] != null) return data['data']['id'].toString();
    return null;
  }
}