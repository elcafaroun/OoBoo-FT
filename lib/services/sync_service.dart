import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../utils/constants.dart';
import 'database/database_helper.dart';
import 'network_checker.dart'; // 👈 IMPORT DU CHECKER GLOBAL

class SyncService {
  final DatabaseHelper _dbHelper = DatabaseHelper();

  // Endpoints
  final String _commandUrl = "$baseUrl/command";
  final String _stockUrl = "$baseUrl/update-stock";
  final String _productUrl = "$baseUrl/product";
  final String _categoryUrl = "$baseUrl/category";
  final String _structureUrl = "$baseUrl/structure";

  /// Cycle complet : Pousse les modifs locales puis télécharge les données globales
  Future<void> fullSynchronization(String codeStructure, String userId) async {
    // 1. VRAIE vérification de la disponibilité des micro-services
    bool serverIsUp = await NetworkChecker.isBackendAccessible();

    if (!serverIsUp) {
      debugPrint("📡 Micro-services indisponibles. Synchronisation annulée pour le moment.");
      return;
    }

    debugPrint("🔄 Début de la synchronisation bidirectionnelle en ligne...");

    // 2. Envoi des données locales (Push)
    await processQueue();

    // 3. Récupération des données serveurs (Pull)
    await refreshLocalData(codeStructure, userId);

    debugPrint("✅ Synchronisation terminée avec succès.");
  }

  /// Pousse les actions en attente vers le serveur
  Future<void> processQueue() async {
    // Double vérification par sécurité avant d'attaquer la file
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

      // Gestion des Commandes
      if (tableName == 'commands') {
        if (action == 'INSERT') {
          success = await _sendOrderToServer(data);
        } else if (action == 'UPDATE' && data['status'] == 'CANCELLED') {
          success = await _sendCancelToServer(entityId);
        }
      }
      // Gestion des Stocks
      else if (action == 'UPDATE_STOCK') {
        success = await _sendStockUpdateToServer(data);
      }
      // Gestion des Structures
      else if (tableName == 'structures' && action == 'UPDATE') {
        success = await _sendStructureUpdateToServer(entityId, data);
      }

      if (success) {
        await db.delete('sync_queue', where: 'id = ?', whereArgs: [taskId]);
        if (tableName == 'commands') {
          await db.update('commands', {'isSynced': 1}, where: 'id = ?', whereArgs: [entityId]);
        }
      } else {
        // Si une requête échoue au milieu de la boucle (ex: micro-coupure réseau),
        // on arrête le traitement de la file pour éviter de bloquer l'application sur les tâches suivantes.
        debugPrint("⚠️ Interruption de la file d'attente : Échec de la tâche ID $taskId");
        break;
      }
    }
  }

  /// Télécharge les dernières données (Produits, Catégories, Commandes, Structures)
  Future<void> refreshLocalData(String codeStructure, String userId) async {
    // Triple vérification (utile si appelée indépendamment de fullSynchronization)
    if (!(await NetworkChecker.isBackendAccessible())) return;

    try {
      final headers = {'Content-Type': 'application/json'};

      debugPrint("📥 Téléchargement des dernières données depuis le serveur...");

      // Récupération parallèle optimisée
      final responses = await Future.wait([
        http.get(Uri.parse("$_productUrl/structure/$codeStructure"), headers: headers),
        http.get(Uri.parse("$_categoryUrl/structure/$codeStructure"), headers: headers),
        http.get(Uri.parse("$_commandUrl/structure/$codeStructure"), headers: headers),
        http.get(Uri.parse("$_structureUrl/user/$userId"), headers: headers),
      ]).timeout(const Duration(seconds: 15)); // Timeout réduit à 15s car le checker valide l'accès en amont

      // 1. Produits
      if (responses[0].statusCode == 200) {
        await _dbHelper.syncProductsLocal(jsonDecode(utf8.decode(responses[0].bodyBytes)));
      }

      // 2. Catégories
      if (responses[1].statusCode == 200) {
        await _dbHelper.syncCategoriesLocal(jsonDecode(utf8.decode(responses[1].bodyBytes)));
      }

      // 3. Commandes
      if (responses[2].statusCode == 200) {
        await _dbHelper.syncCommandsLocal(jsonDecode(utf8.decode(responses[2].bodyBytes)));
      }

      // 4. Structures
      if (responses[3].statusCode == 200) {
        final List<dynamic> userStructures = jsonDecode(utf8.decode(responses[3].bodyBytes));
        await _dbHelper.syncStructuresLocal(userStructures);
        debugPrint("🏢 Structures mises à jour pour l'utilisateur $userId");
      }

      debugPrint("📥 Cache local entièrement rafraîchi.");
    } catch (e) {
      debugPrint("❌ Erreur lors du rafraîchissement des données : $e");
    }
  }

  // --- Méthodes API ---

  Future<bool> _sendOrderToServer(Map<String, dynamic> data) async {
    try {
      final response = await http.post(
        Uri.parse(_commandUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(data),
      ).timeout(const Duration(seconds: 10));
      return response.statusCode == 201 || response.statusCode == 200;
    } catch (_) { return false; }
  }

  Future<bool> _sendStockUpdateToServer(Map<String, dynamic> data) async {
    try {
      final response = await http.post(
        Uri.parse(_stockUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(data),
      ).timeout(const Duration(seconds: 10));
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
      final response = await http.put(
        Uri.parse("$_structureUrl/$id"),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(data),
      ).timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (_) { return false; }
  }
}