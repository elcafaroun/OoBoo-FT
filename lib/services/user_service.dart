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
      String? email,
      String password,
      String profile,
      String? codeStructure,
      ) async {
    bool isOnline = await NetworkChecker.isBackendAccessible();
    if (!isOnline) {
      throw Exception(
        "OFFLINE_ERROR|Connexion Internet requise. L'enregistrement ne peut pas se faire hors-ligne.",
      );
    }

    try {
      final String urlString =
      (codeStructure != null && codeStructure.trim().isNotEmpty)
          ? '$baseUrl/user?codeStructure=${Uri.encodeComponent(codeStructure.trim())}'
          : '$baseUrl/user';

      // 💡 Nettoyage du payload : ne pas envoyer une chaîne vide "" pour l'email
      final Map<String, dynamic> bodyPayload = {
        'userName': name.trim(),
        'userPhone': phone.trim(),
        'userPassword': password,
        'userProfile': profile,
      };

      if (email != null && email.trim().isNotEmpty) {
        bodyPayload['userEmail'] = email.trim().toLowerCase();
      }

      final response = await http
          .post(
        Uri.parse(urlString),
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: jsonEncode(bodyPayload),
      )
          .timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception(
            "TIMEOUT_ERROR|Le serveur met trop de temps à répondre.",
          );
        },
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return true;
      } else {
        String errorMessage = "Erreur lors de l'enregistrement";
        String errorCode = "HTTP_${response.statusCode}";

        if (response.body.isNotEmpty) {
          try {
            final decoded = jsonDecode(utf8.decode(response.bodyBytes));

            if (decoded is Map<String, dynamic>) {
              // 1. Extraction du code d'erreur personnalisé
              errorCode = decoded['code'] ??
                  decoded['errorCode'] ??
                  decoded['status']?.toString() ??
                  errorCode;

              // 2. Extraction du message d'erreur
              errorMessage = decoded['message'] ??
                  decoded['detail'] ??
                  decoded['error'] ??
                  decoded['description'] ??
                  response.body;

              // 3. Gestion des erreurs de validation Spring (@Valid / BindingResult)
              if (decoded.containsKey('errors') && decoded['errors'] is List) {
                final List errors = decoded['errors'];
                if (errors.isNotEmpty) {
                  errorMessage = errors
                      .map((e) => e['defaultMessage'] ?? e.toString())
                      .join(', ');
                }
              }
            } else if (decoded is String) {
              errorMessage = decoded;
            }
          } catch (_) {
            // Fallback si le corps de réponse est du texte brut
            errorMessage = response.body.isNotEmpty ? response.body : errorMessage;
          }
        }

        throw Exception("$errorCode|$errorMessage");
      }
    } catch (e) {
      debugPrint("Erreur enregistrement utilisateur online : $e");
      rethrow;
    }
  }



  Future<bool> checkEmailAvailable(String email) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/user/check-email?email=${Uri.encodeComponent(email.trim())}'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final dynamic data = jsonDecode(response.body);
        if (data is Map) return data['available'] ?? false;
        if (data is bool) return data;
      }
      return false;
    } catch (e) {
      debugPrint("Erreur lors de la vérification de l'email : $e");
      throw Exception("CHECK_EMAIL_ERROR|Impossible de vérifier la disponibilité de l'email.");
    }
  }

  Future<bool> checkPhoneAvailable(String phone) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/user/check-phone?phone=${Uri.encodeComponent(phone.trim())}'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final dynamic data = jsonDecode(response.body);
        if (data is Map) return data['available'] ?? false;
        if (data is bool) return data;
      }
      return false;
    } catch (e) {
      debugPrint("Erreur lors de la vérification du téléphone : $e");
      throw Exception("CHECK_PHONE_ERROR|Impossible de vérifier la disponibilité du numéro.");
    }
  }

  Future<Map<String, dynamic>> login(String identifier, String password) async {
    bool serverIsUp = await NetworkChecker.isBackendAccessible();

    if (serverIsUp) {
      try {
        debugPrint(' Mode Online : Envoi des identifiants au backend');
        final response = await http.post(
          Uri.parse('$baseUrl/user/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'identifier': identifier, 'password': password}),
        ).timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            throw Exception("TIMEOUT_ERROR|Délai d'attente dépassé lors de la connexion.");
          },
        );

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
          throw Exception('INVALID_CREDENTIALS|Identifiants invalides.');
        } else {
          throw Exception('HTTP_${response.statusCode}|Erreur de connexion au serveur (${response.statusCode}).');
        }
      } catch (e) {
        debugPrint(' Micro-coupure ou problème lors de la requête en ligne : $e');
        if (e.toString().contains("INVALID_CREDENTIALS")) rethrow;
      }
    }

    // MODE FALLBACK AUTOMATIQUE OFFLINE
    debugPrint(' Basculement : Tentative de connexion via SQLite (Mode Offline)...');
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

      if (response.statusCode == 200) {
        return jsonDecode(utf8.decode(response.bodyBytes));
      } else {
        throw Exception("HTTP_${response.statusCode}|Échec de la récupération des utilisateurs.");
      }
    } catch (e) {
      debugPrint("Erreur récupération : $e");
      rethrow;
    }
  }

  Future<bool> updateUser(String id, Map<String, dynamic> userData) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/user/update/$id'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(userData),
      );
      if (response.statusCode == 200) return true;
      throw Exception("HTTP_${response.statusCode}|Échec de la modification de l'utilisateur.");
    } catch (e) {
      debugPrint("Erreur modification utilisateur : $e");
      rethrow;
    }
  }

  Future<bool> toggleUserStatus(String id, bool shouldEnable) async {
    final String action = shouldEnable ? "enable" : "disable";

    try {
      final response = await http.patch(
        Uri.parse('$baseUrl/user/$action/$id'),
        headers: {'Content-Type': 'application/json'},
      );
      if (response.statusCode == 200 || response.statusCode == 204) return true;
      throw Exception("HTTP_${response.statusCode}|Échec du changement de statut utilisateur.");
    } catch (e) {
      debugPrint("Erreur changement de statut : $action - $e");
      rethrow;
    }
  }

  Future<bool> resetPassword(String userId, String newPassword) async {
    try {
      final response = await http.patch(
        Uri.parse('$baseUrl/user/reset-password/$userId'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'newPassword': newPassword}),
      );
      if (response.statusCode == 200) return true;
      throw Exception("HTTP_${response.statusCode}|Échec de la réinitialisation du mot de passe.");
    } catch (e) {
      debugPrint("Erreur réinitialisation mot de passe : $e");
      rethrow;
    }
  }

  Future<bool> changeFirstPassword(String userId, String newPassword) async {
    try {
      final response = await http.patch(
        Uri.parse('$baseUrl/user/change-password/$userId'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'newPassword': newPassword}),
      );
      if (response.statusCode == 200) return true;
      throw Exception("HTTP_${response.statusCode}|Erreur lors de la modification du premier mot de passe.");
    } catch (e) {
      debugPrint("Erreur changement premier mot de passe : $e");
      rethrow;
    }
  }

  Future<void> disableUser(String userId) async {
    final url = Uri.parse('$baseUrl/user/disable/$userId');
    try {
      final response = await http.patch(url);
      if (response.statusCode != 204) {
        throw Exception("HTTP_${response.statusCode}|Erreur lors de la désactivation (${response.statusCode}).");
      }
    } catch (e) {
      debugPrint(" Exception : $e");
      rethrow;
    }
  }

  String? _extractUserId(Map<String, dynamic> data) {
    if (data['id'] != null) return data['id'].toString();
    if (data['user'] != null && data['user']['id'] != null) return data['user']['id'].toString();
    if (data['data'] != null && data['data']['id'] != null) return data['data']['id'].toString();
    return null;
  }
}