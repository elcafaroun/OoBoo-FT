import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../utils/constants.dart';
import 'database/database_helper.dart';
import 'network_checker.dart';

class SyncService {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  // Endpoints
  final String _commandUrl = "$baseUrl/command";
  final String _stockUrl = "$baseUrl/update-stock";
  final String _productUrl = "$baseUrl/product";
  final String _categoryUrl = "$baseUrl/category";
  final String _structureUrl = "$baseUrl/structure";
  final String _userUrl = "$baseUrl/user";
  // Cycle complet : Pousse les modifs locales puis télécharge les données globales
  Future<void> fullSynchronization(String codeStructure, String userId) async {
    bool serverIsUp = await NetworkChecker.isBackendAccessible();

    if (!serverIsUp) {
      debugPrint("📡 Micro-services indisponibles. Synchronisation annulée.");
      return;
    }

    debugPrint("🔄 Début de la synchronisation bidirectionnelle...");
    await processQueue();
    await refreshLocalData(userId);
    debugPrint("✅ Synchronisation terminée.");
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

    debugPrint("📋 File d'attente : ${queue.length} tâches en attente.");

    for (var task in queue) {
      int taskId = task['id'];
      String tableName = task['tableName'];
      String action = task['action'];
      String entityId = task['entityId'];
      Map<String, dynamic> data = jsonDecode(task['data']);

      bool success = false;

      debugPrint("➡️ Traitement tâche : $action sur $tableName (ID: $entityId)");

      // 1. Gestion des mots de passe
      if (action == 'UPDATE_PASSWORD') {
        success = await _sendPasswordUpdateToServer(entityId, data);
      }
      // 2. Gestion des Commandes
      else if (tableName == 'commands') {
        if (action == 'INSERT') {
          success = await _sendOrderToServer(data);
        } else if (action == 'UPDATE' && data['status'] == 'CANCELLED') {
          success = await _sendCancelToServer(entityId);
        }
      }
      // 3. Gestion des Stocks
      else if (action == 'UPDATE_STOCK') {
        success = await _sendStockUpdateToServer(data);
      }
      // 4. Gestion des Structures
      else if (tableName == 'structures' && action == 'UPDATE') {
        success = await _sendStructureUpdateToServer(entityId, data);
      }

      if (success) {
        await db.delete('sync_queue', where: 'id = ?', whereArgs: [taskId]);
        if (tableName == 'commands') {
          await db.update('commands', {'isSynced': 1}, where: 'id = ?', whereArgs: [entityId]);
        }
        debugPrint("✅ Tâche $taskId réussie et supprimée.");
      } else {
        debugPrint("⚠️ Échec tâche ID $taskId. Passage à la suivante.");
        continue; // On continue vers la prochaine tâche même si celle-ci échoue
      }
    }
  }

  // Ajoutez cette variable dans votre classe SyncService
  // Ajoutez cette variable dans votre classe SyncService
  bool _isSyncing = false;

  Future<void> refreshLocalData(String userId) async {
    // 1. Protection contre les appels multiples
    if (_isSyncing) {
      debugPrint("⚠️ Synchro déjà en cours, annulation du doublon.");
      return;
    }

    if (!(await NetworkChecker.isBackendAccessible())) {
      debugPrint("📡 Mode hors-ligne : synchro annulée.");
      return;
    }

    _isSyncing = true; // Verrouillage
    try {
      debugPrint("📥 Début de la synchronisation hiérarchique...");
      final headers = {'Content-Type': 'application/json'};

      final structUri = Uri.parse("$_structureUrl/user/$userId");
      final linkUri = Uri.parse("$_userUrl/user-structures/$userId");

      final responses = await Future.wait([
        http.get(structUri, headers: headers),
        http.get(linkUri, headers: headers),
      ]);

      // 2. Traitement des Structures
      if (responses[0].statusCode == 200) {
        final dynamic decodedData = jsonDecode(utf8.decode(responses[0].bodyBytes));

        // 🔬 LOG DE SÉCURITÉ : Afficher ce que le serveur renvoie réellement
        debugPrint("👉 Réponse brute API structures : $decodedData");

        List<dynamic> structures = [];

        // Sécurité si l'API renvoie un objet avec une clé 'content' ou 'data'
        if (decodedData is List) {
          structures = decodedData;
        } else if (decodedData is Map && decodedData.containsKey('structures')) {
          structures = decodedData['structures'];
        } else if (decodedData is Map && decodedData.containsKey('data')) {
          structures = decodedData['data'];
        } else if (decodedData is Map) {
          // Si c'est un seul objet, on l'encapsule dans une liste
          structures = [decodedData];
        }

        debugPrint("🏢 Nombre de structures détectées à traiter : ${structures.length}");

        if (structures.isNotEmpty) {
          await _dbHelper.syncStructuresLocal(structures);
        }

        // 3. Traitement des Relations (User <-> Structures)
        if (responses[1].statusCode == 200) {
          List<dynamic> rawData = jsonDecode(utf8.decode(responses[1].bodyBytes));

          List<Map<String, dynamic>> processedList = rawData.map((item) {
            return {
              'id': item['id']?.toString() ?? DateTime.now().microsecondsSinceEpoch.toString(),
              'user_id': (item['userId'] ?? item['user_id'] ?? item['id_user'] ?? userId).toString(),
              'structure_id': (item['structureId'] ?? item['structure_id'] ?? item['id_structure'] ?? item['idStructure']).toString(),
              'role_in_structure': (item['roleInStructure'] ?? item['role_in_structure'] ?? 'COLLABORATEUR').toString(),
              'updated_at': (item['updatedAt'] ?? item['updated_at'] ?? DateTime.now().toIso8601String()).toString(),
            };
          }).toList();

          await _dbHelper.syncUserStructuresLocal(processedList);
        }

        // 4. Synchronisation des dépendances (Produits/Catégories/Commandes)
        for (var structure in structures) {
          // 🛠️ MULTI-MAPPING DES CLÉS : s'adapte à 'id', 'codeStructure' ou 'structureId'
          String? code = structure['idStructure']?.toString() ??
              structure['codeStructure']?.toString() ??
              structure['structureId']?.toString();

          if (code == null || code.isEmpty) {
            debugPrint("⚠️ Structure ignorée car aucun ID ou code valide n'a été trouvé : $structure");
            continue;
          }

          debugPrint("🔄 Synchronisation pour la structure : $code");

          try {
            // A. Catégories d'abord
            final catResp = await http.get(Uri.parse("$_categoryUrl/structure/$code"), headers: headers);
            if (catResp.statusCode == 200) {
              await _dbHelper.syncCategoriesLocal(jsonDecode(utf8.decode(catResp.bodyBytes)));
              debugPrint("✅ Catégories synchronisées pour $code");
            }

            // B. Produits ensuite
            final prodResp = await http.get(Uri.parse("$_productUrl/structure/$code"), headers: headers);
            if (prodResp.statusCode == 200) {
              await _dbHelper.syncProductsLocal(jsonDecode(utf8.decode(prodResp.bodyBytes)));
              debugPrint("✅ Produits synchronisés pour $code");
            }

            // C. Commandes en dernier
            final cmdResp = await http.get(Uri.parse("$_commandUrl/structure/$code"), headers: headers);
            if (cmdResp.statusCode == 200) {
              await _dbHelper.syncCommandsLocal(jsonDecode(utf8.decode(cmdResp.bodyBytes)));
              debugPrint("✅ Commandes synchronisées pour $code");
            }

          } catch (e) {
            debugPrint("⚠️ Erreur lors de la synchronisation de la structure $code : $e");
          }
        }
      } else {
        debugPrint("❌ Code d'erreur API structures : ${responses[0].statusCode}");
      }

      debugPrint("✅ Cache local rafraîchi.");
    } catch (e, stackTrace) {
      debugPrint("❌ Erreur critique : $e");
      debugPrint("📜Trace : $stackTrace");
    } finally {
      _isSyncing = false; // Libération du verrou
    }
  }

  Future<bool> _sendPasswordUpdateToServer(String userId, Map<String, dynamic> data) async {
    try {
      debugPrint("🚀 [API PATCH] Envoi vers /reset-password/$userId avec body: ${jsonEncode(data)}");

      final response = await http.patch(
        Uri.parse('$_userUrl/reset-password/$userId'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(data),
      ).timeout(const Duration(seconds: 10));

      debugPrint("🚨 [BACKEND RESP] Statut: ${response.statusCode} | Body: ${response.body}");

      return response.statusCode == 200;
    } catch (e) {
      debugPrint("❌ Erreur API Mot de passe : $e");
      return false;
    }
  }

  Future<bool> _sendOrderToServer(Map<String, dynamic> data) async {
    try {
      final response = await http.post(Uri.parse(_commandUrl), headers: {'Content-Type': 'application/json'}, body: jsonEncode(data)).timeout(const Duration(seconds: 10));
      return response.statusCode == 201 || response.statusCode == 200;
    } catch (_) { return false; }
  }

  Future<bool> _sendStockUpdateToServer(Map<String, dynamic> data) async {
    try {
      final response = await http.post(Uri.parse(_stockUrl), headers: {'Content-Type': 'application/json'}, body: jsonEncode(data)).timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (_) { return false; }
  }

  Future<bool> _sendCancelToServer(String orderId) async {
    try {
      final response = await http.put(Uri.parse("$_commandUrl/$orderId/cancel")).timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (_) { return false; }
  }

  Future<bool> _sendStructureUpdateToServer(String id, Map<String, dynamic> data) async {
    try {
      final response = await http.put(Uri.parse("$_structureUrl/$id"), headers: {'Content-Type': 'application/json'}, body: jsonEncode(data)).timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (_) { return false; }
  }


}