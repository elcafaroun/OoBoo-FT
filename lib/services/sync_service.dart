import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/constants.dart';
import 'database/database_helper.dart';
import 'network_checker.dart';

class SyncService {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  bool _isSyncing = false;

  // Endpoints
  final String _commandUrl = "$baseUrl/command";
  final String _stockUrl = "$baseUrl/update-stock";
  final String _productUrl = "$baseUrl/product";
  final String _categoryUrl = "$baseUrl/category";
  final String _structureUrl = "$baseUrl/structure";
  final String _userUrl = "$baseUrl/user";
  final String _customerUrl = "$baseUrl/customer";

  /// Cycle complet : Pousse les modifs locales puis télécharge les données de la structure active
  Future<void> fullSynchronization(String codeStructure, String userId) async {
    debugPrint(
        "🔄 Début de la synchronisation pour la structure : $codeStructure...");

    // 1. Pousser d'abord les actions en attente vers le serveur
    await processQueue();

    // 2. Vérifier la connectivité réseau pour les données distantes
    bool serverIsUp = await NetworkChecker.isBackendAccessible();
    if (!serverIsUp) {
      debugPrint(
          "📡 Micro-services indisponibles. Synchronisation distante annulée.");
      return;
    }

    // 3. Synchroniser le profil utilisateur si l'ID est fourni
    if (userId.isNotEmpty) {
      await _syncUserProfile(userId);
    }

    // 4. Rafraîchir les données métiers de la structure spécifique active
    print("Le code du de la structue ### :$codeStructure");

    if (codeStructure.isNotEmpty) {
      await refreshLocalDataForStructure(codeStructure);
    }

    // 5. Notifier la fin de la synchronisation
    if (userId.isNotEmpty) {
      await _notifySyncCompletion(userId);
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_sync_date', DateTime.now().toIso8601String());

    debugPrint(
        "✅ Synchronisation de la structure $codeStructure terminée avec succès.");
  }

  /// Pousse les actions en attente vers le serveur
  Future<void> processQueue() async {
    if (!(await NetworkChecker.isBackendAccessible())) return;

    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> queue = await db.query(
      'sync_queue',
      where: "status = ?",
      whereArgs: ['PENDING'],
      orderBy: 'timestamp ASC',
    );

    if (queue.isEmpty) return;

    for (var task in queue) {
      int taskId = task['id'];
      String tableName = task['tableName'];
      String action = task['action'];
      String entityId = task['entityId'];
      Map<String, dynamic> data = jsonDecode(task['data']);

      bool success = false;
      if (action == 'UPDATE_PASSWORD') {
        success = await _sendPasswordUpdateToServer(entityId, data);
      } else if (tableName == 'commands') {
        if (action == 'INSERT') {
          success = await _sendOrderToServer(data);
        } else if (action == 'UPDATE' && data['status'] == 'CANCELLED') {
          success = await _sendCancelToServer(entityId);
        }
      } else if (tableName == 'customers') {
        if (action == 'INSERT') {
          success = await _sendCustomerToServer(data, isUpdate: false);
        } else if (action == 'UPDATE') {
          success = await _sendCustomerToServer(data, isUpdate: true);
        }
      } else if (action == 'UPDATE_STOCK') {
        success = await _sendStockUpdateToServer(data);
      } else if (tableName == 'structures' && action == 'UPDATE') {
        success = await _sendStructureUpdateToServer(entityId, data);
      } else if (action == 'UPDATE_STOCK') {
        success = await _sendStockUpdateToServer(data);
      } else if (tableName == 'structures' && action == 'UPDATE') {
        success = await _sendStructureUpdateToServer(entityId, data);
      }

      if (success) {
        await db.delete('sync_queue', where: 'id = ?', whereArgs: [taskId]);

        if (tableName == 'commands') {
          await db.update('commands', {'isSynced': 1},
              where: 'id = ?', whereArgs: [entityId]);
        } else if (tableName == 'customers') {
          await db.update('customers', {'isSynced': 1},
              where: 'id = ?', whereArgs: [entityId]);
        }
      }
    }
  }

  /// Rafraîchit les données métiers spécifiquement pour une structure active
  Future<void> refreshLocalDataForStructure(String codeStructure) async {
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      debugPrint(
          "📥 Téléchargement des données pour la structure : $codeStructure");
      final headers = {'Content-Type': 'application/json'};

      // A. Catégories
      final catResp = await http.get(
          Uri.parse("$_categoryUrl/structure/$codeStructure"),
          headers: headers);
      if (catResp.statusCode == 200) {
        await _dbHelper
            .syncCategoriesLocal(jsonDecode(utf8.decode(catResp.bodyBytes)));
      }

      // B. Produits
      final prodResp = await http.get(
          Uri.parse("$_productUrl/structure/$codeStructure"),
          headers: headers);
      if (prodResp.statusCode == 200) {
        await _dbHelper
            .syncProductsLocal(jsonDecode(utf8.decode(prodResp.bodyBytes)));
      }

      // C. Commandes
      final cmdResp = await http.get(
          Uri.parse("$_commandUrl/structure/$codeStructure"),
          headers: headers);
      if (cmdResp.statusCode == 200) {
        await _dbHelper
            .syncCommandsLocal(jsonDecode(utf8.decode(cmdResp.bodyBytes)));
      }

      // D. Clients par structure
      final custResp = await http.get(
          Uri.parse("$_customerUrl/structure/$codeStructure"),
          headers: headers);
      if (custResp.statusCode == 200) {
        final List<dynamic> customersData =
            jsonDecode(utf8.decode(custResp.bodyBytes));
        await _dbHelper.syncCustomersLocal(customersData);
        debugPrint(
            "✅ [DB] ${customersData.length} clients synchronisés pour la structure $codeStructure.");
      } else {
        debugPrint(
            "⚠️ Échec synchro clients - Code HTTP : ${custResp.statusCode}");
      }

      debugPrint("✅ Cache local de la structure $codeStructure rafraîchi.");
    } catch (e) {
      debugPrint("❌ Erreur critique refreshLocalDataForStructure : $e");
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _syncUserProfile(String userId) async {
    try {
      final response = await http.get(Uri.parse("$_userUrl/$userId"));

      if (response.statusCode == 200) {
        final Map<String, dynamic> userData =
            jsonDecode(utf8.decode(response.bodyBytes));

        // 1. Sauvegarde utilisateur
        await _dbHelper.saveOrUpdateUserLocal(userData);

        // 2. Synchronisation des liens structures
        if (userData.containsKey('structures') &&
            userData['structures'] is List) {
          List<Map<String, dynamic>> relations =
              (userData['structures'] as List)
                  .map((s) => {
                        'id': s['id']?.toString() ??
                            DateTime.now().microsecondsSinceEpoch.toString(),
                        'user_id': userId,
                        'structure_id': s['structureId']?.toString() ??
                            s['idStructure']?.toString(),
                        'role_in_structure':
                            s['roleInStructure'] ?? 'COLLABORATEUR',
                        'updated_at': DateTime.now().toIso8601String(),
                      })
                  .toList();

          await _dbHelper.syncUserStructuresLocal(relations);
          debugPrint(
              "✅ Structures utilisateur synchronisées : ${relations.length}");
        }
      }
    } catch (e) {
      debugPrint("⚠️ Échec récupération profil serveur : $e");
    }
  }

  // --- Méthodes API ---

  Future<bool> _sendPasswordUpdateToServer(
      String userId, Map<String, dynamic> data) async {
    try {
      final response = await http.patch(
          Uri.parse('$_userUrl/reset-password/$userId'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(data));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _sendOrderToServer(Map<String, dynamic> data) async {
    try {
      final response = await http.post(Uri.parse(_commandUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(data));
      return response.statusCode == 201 || response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _sendCustomerToServer(Map<String, dynamic> data,
      {bool isUpdate = false}) async {
    try {
      // Si c'est une mise à jour, on tape sur /customer/update comme défini dans ton Controller Spring Boot
      final url = isUpdate ? "$_customerUrl/update" : _customerUrl;

      debugPrint(
          "📤 [API] Envoi du client (${isUpdate ? 'UPDATE' : 'INSERT'}) vers : $url");

      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(data),
      );

      debugPrint(
          "📡 [API] Réponse serveur client - Code : ${response.statusCode} | Body : ${response.body}");
      return response.statusCode == 201 || response.statusCode == 200;
    } catch (e) {
      debugPrint("❌ [API] Erreur réseau lors de l'envoi du client : $e");
      return false;
    }
  }

  Future<bool> _sendStockUpdateToServer(Map<String, dynamic> data) async {
    try {
      final response = await http.post(Uri.parse(_stockUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(data));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _sendCancelToServer(String orderId) async {
    try {
      final response =
          await http.put(Uri.parse("$_commandUrl/$orderId/cancel"));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _sendStructureUpdateToServer(
      String id, Map<String, dynamic> data) async {
    try {
      final response = await http.put(Uri.parse("$_structureUrl/$id"),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(data));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<void> _notifySyncCompletion(String userId) async {
    try {
      await http.post(Uri.parse("$_userUrl/$userId/update-sync-date"));
    } catch (e) {
      debugPrint("⚠️ Notification sync échouée : $e");
    }
  }
}
