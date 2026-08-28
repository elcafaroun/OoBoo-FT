import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/constants.dart';
import 'database/database_helper.dart';
import 'network_checker.dart';

/// Service gérant la synchronisation bidirectionnelle (File d'attente locale vers serveur,
/// et récupération des données distantes par structure vers SQLite).
class SyncService {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  bool _isSyncing = false;

  // Endpoints de l'API
  final String _commandUrl = "$baseUrl/command";
  final String _stockUrl = "$baseUrl/update-stock";
  final String _productUrl = "$baseUrl/product";
  final String _categoryUrl = "$baseUrl/category";
  final String _structureUrl = "$baseUrl/structure";
  final String _userUrl = "$baseUrl/user";
  final String _customerUrl = "$baseUrl/customer";

  Future<void> fullSynchronization(String userId) async {
    debugPrint("🚀 [SyncService] Début de la synchronisation globale... [User: $userId]");

    // 1. Pousser d'abord les actions en attente vers le serveur
    await processQueue();

    // 2. Vérifier la connectivité réseau
    bool serverIsUp = await NetworkChecker.isBackendAccessible();
    if (!serverIsUp) {
      debugPrint("⚠️ [SyncService] Micro-services indisponibles. Synchronisation distante annulée.");
      return;
    }

    // 3. Synchroniser en priorité le profil utilisateur et ses structures associées (Tables mères)
    if (userId.isNotEmpty) {
      await _syncUserProfile(userId);
    }

    // 4. Récupérer les structures et boucler directement dessus pour synchroniser leurs tables connexes
    await syncAllStructuresData(userId);

    // 5. Notifier la fin de la synchronisation au serveur
    if (userId.isNotEmpty) {
      await _notifySyncCompletion(userId);
    }

    // Enregistrer la date de dernière synchronisation réussie
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_sync_date', DateTime.now().toIso8601String());

    debugPrint("✅ [SyncService] Synchronisation globale terminée avec succès.");
  }

  /// C'est ici qu'on récupère les structures et qu'on boucle sur chacune
  /// pour synchroniser l'ensemble de ses données métiers connexes.
  Future<void> syncAllStructuresData(String userId) async {
    if (_isSyncing) {
      debugPrint("⏳ [SyncService] Une synchronisation des structures est déjà en cours. Ignorée.");
      return;
    }
    _isSyncing = true;

    try {
      List<Map<String, dynamic>> userStructures = [];
      if (userId.isNotEmpty) {
        userStructures = await _dbHelper.getLocalStructuresByUser(userId);
      }

      debugPrint("🔄 [SyncService] Lancement de la synchronisation en boucle pour ${userStructures.length} structure(s).");

      for (var structure in userStructures) {
        // C'est dans cette boucle qu'on extrait le code/id de chaque structure connue
        final String structIdentifier = structure['id']?.toString() ?? structure['codeStructure']?.toString() ?? '';

        if (structIdentifier.isEmpty) continue;

        debugPrint("📥 [SyncService] Synchronisation des tables connexes pour la structure : $structIdentifier");
        await refreshLocalDataForStructure(structIdentifier);
      }
    } catch (e) {
      debugPrint("❌ [SyncService] Erreur lors de la synchronisation des structures en boucle : $e");
    } finally {
      _isSyncing = false;
    }
  }

  /// Traite la file d'attente locale (`sync_queue`) pour envoyer les actions PENDING au serveur.
  Future<void> processQueue() async {
    if (!(await NetworkChecker.isBackendAccessible())) {
      debugPrint("ℹ️ [SyncService] Pas de réseau, traitement de la file d'attente reporté.");
      return;
    }

    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> queue = await db.query(
      'sync_queue',
      where: "status = ?",
      whereArgs: ['PENDING'],
      orderBy: 'timestamp ASC',
    );

    if (queue.isEmpty) {
      debugPrint("ℹ️ [SyncService] File d'attente (sync_queue) vide.");
      return;
    }

    debugPrint("📤 [SyncService] Traitement de ${queue.length} action(s) en attente dans la file.");

    for (var task in queue) {
      int taskId = task['id'];
      String tableName = task['tableName'];
      String action = task['action'];
      String entityId = task['entityId'];
      Map<String, dynamic> data = jsonDecode(task['data']);

      bool success = false;
      debugPrint("🔄 [SyncService] Envoi tâche ID $taskId -> Table: $tableName | Action: $action");

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
      }

      if (success) {
        // Suppression de la tâche de la file d'attente après succès
        await db.delete('sync_queue', where: 'id = ?', whereArgs: [taskId]);

        // Mise à jour du statut de synchronisation sur l'entité locale correspondante
        if (tableName == 'commands') {
          await db.update('commands', {'isSynced': 1}, where: 'id = ?', whereArgs: [entityId]);
        } else if (tableName == 'customers') {
          await db.update('customers', {'isSynced': 1}, where: 'id = ?', whereArgs: [entityId]);
        }
        debugPrint("✅ [SyncService] Tâche ID $taskId synchronisée et purgée avec succès.");
      } else {
        debugPrint("⚠️ [SyncService] Échec de l'envoi pour la tâche ID $taskId. Conservée dans la file.");
      }
    }
  }

  /// Rafraîchit les données métiers connexes (Catégories, Produits, Commandes, Clients)
  /// pour une structure spécifique en respectant l'ordre logique d'intégrité.
  Future<void> refreshLocalDataForStructure(String codeStructure) async {
    try {
      final headers = {'Content-Type': 'application/json'};
      debugPrint("📥 [SyncService] Récupération des données distantes pour la structure: $codeStructure");

      // A. Catégories (Table dépendante de la structure)
      final catResp = await http.get(Uri.parse("$_categoryUrl/structure/$codeStructure"), headers: headers);
      if (catResp.statusCode == 200) {
        await _dbHelper.syncCategoriesLocal(jsonDecode(utf8.decode(catResp.bodyBytes)));
        debugPrint("✔️ [SyncService] Catégories synchronisées pour $codeStructure");
      }

      // B. Produits (Dépend des catégories et de la structure)
      final prodResp = await http.get(Uri.parse("$_productUrl/structure/$codeStructure"), headers: headers);
      if (prodResp.statusCode == 200) {
        await _dbHelper.syncProductsLocal(jsonDecode(utf8.decode(prodResp.bodyBytes)));
        debugPrint("✔️ [SyncService] Produits synchronisés pour $codeStructure");
      }

      // C. Commandes (Dépend des produits, clients et de la structure)
      final cmdResp = await http.get(Uri.parse("$_commandUrl/structure/$codeStructure"), headers: headers);
      if (cmdResp.statusCode == 200) {
        await _dbHelper.syncCommandsLocal(jsonDecode(utf8.decode(cmdResp.bodyBytes)));
        debugPrint("✔️ [SyncService] Commandes synchronisées pour $codeStructure");
      }

      // D. Clients par structure
      final custResp = await http.get(Uri.parse("$_customerUrl/structure/$codeStructure"), headers: headers);
      if (custResp.statusCode == 200) {
        final List<dynamic> customersData = jsonDecode(utf8.decode(custResp.bodyBytes));
        await _dbHelper.syncCustomersLocal(customersData);
        debugPrint("✔️ [SyncService] Clients synchronisés pour $codeStructure");
      } else {
        debugPrint("⚠️ [SyncService] Échec synchro clients pour $codeStructure - Code HTTP : ${custResp.statusCode}");
      }

      debugPrint("✅ [SyncService] Cache local de la structure $codeStructure rafraîchi avec succès.");
    } catch (e) {
      debugPrint("❌ [SyncService] Erreur critique refreshLocalDataForStructure pour $codeStructure : $e");
    }
  }

  /// Synchronise le profil utilisateur et ses structures associées (Tables mères / références)
  Future<void> _syncUserProfile(String userId) async {
    try {
      debugPrint("👤 [SyncService] Synchronisation du profil utilisateur : $userId");
      final response = await http.get(Uri.parse("$_userUrl/$userId"));

      if (response.statusCode == 200) {
        final Map<String, dynamic> userData = jsonDecode(utf8.decode(response.bodyBytes));

        // 1. Sauvegarde des informations utilisateur
        await _dbHelper.saveOrUpdateUserLocal(userData);

        // 2. Synchronisation des relations structures de l'utilisateur
        if (userData.containsKey('structures') && userData['structures'] is List) {
          List<Map<String, dynamic>> relations = (userData['structures'] as List)
              .map((s) => {
            'id': s['id']?.toString() ?? DateTime.now().microsecondsSinceEpoch.toString(),
            'user_id': userId,
            'structure_id': s['structureId']?.toString() ?? s['idStructure']?.toString(),
            'role_in_structure': s['roleInStructure'] ?? 'COLLABORATEUR',
            'updated_at': DateTime.now().toIso8601String(),
          })
              .toList();

          await _dbHelper.syncUserStructuresLocal(relations);

          // 3. Synchronisation des entités structures elles-mêmes (Tables mères avant les tables connexes)
          List<dynamic> structuresData = userData['structures'];
          await _dbHelper.syncStructuresLocal(structuresData);

          debugPrint("✅ [SyncService] Structures utilisateur et liens associés synchronisés : ${relations.length}");
        }
      }
    } catch (e) {
      debugPrint("❌ [SyncService] Échec récupération profil serveur : $e");
    }
  }

  // --- Méthodes d'appels API (Helpers) ---

  Future<bool> _sendPasswordUpdateToServer(String userId, Map<String, dynamic> data) async {
    try {
      final response = await http.patch(
        Uri.parse('$_userUrl/reset-password/$userId'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(data),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _sendOrderToServer(Map<String, dynamic> data) async {
    try {
      final response = await http.post(
        Uri.parse(_commandUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(data),
      );
      return response.statusCode == 201 || response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _sendCustomerToServer(Map<String, dynamic> data, {bool isUpdate = false}) async {
    try {
      final url = isUpdate ? "$_customerUrl/update" : _customerUrl;
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(data),
      );
      return response.statusCode == 201 || response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _sendStockUpdateToServer(Map<String, dynamic> data) async {
    try {
      final response = await http.post(
        Uri.parse(_stockUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(data),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _sendCancelToServer(String orderId) async {
    try {
      final response = await http.put(Uri.parse("$_commandUrl/$orderId/cancel"));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _sendStructureUpdateToServer(String id, Map<String, dynamic> data) async {
    try {
      final response = await http.put(
        Uri.parse("$_structureUrl/$id"),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(data),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<void> _notifySyncCompletion(String userId) async {
    try {
      await http.post(Uri.parse("$_userUrl/$userId/update-sync-date"));
      debugPrint("🔔 [SyncService] Notification de fin de synchronisation envoyée au serveur pour l'utilisateur $userId.");
    } catch (e) {
      debugPrint("⚠️ [SyncService] Notification sync échouée : $e");
    }
  }


  Future<bool> updatePasswordOnline({
    required String userId,
    required String oldPassword,
    required String newPassword,
  }) async {
    try {
      final response = await http.patch(
        Uri.parse('$baseUrl/user/reset-password/$userId'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'oldPassword': oldPassword,
          'newPassword': newPassword,
        }),
      );

      if (response.statusCode == 200) {
        return true;
      }

      throw Exception("HTTP_${response.statusCode}|Échec de la réinitialisation du mot de passe.");
    } catch (e) {
      debugPrint("Erreur réinitialisation mot de passe : $e");
      rethrow;
    }
  }
}