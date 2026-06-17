import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../utils/constants.dart';
import '../models/command_request.dart';
import 'database/database_helper.dart';
import 'network_checker.dart'; // 👈 IMPORT DU CHECKER UNIQUE

class CommandService {
  final String apiUrl = "$baseUrl/command";
  final DatabaseHelper _dbHelper = DatabaseHelper();

  /// Logique Automatique : Tente le serveur, sinon sauvegarde en local.
  /// Cette méthode est le point d'entrée principal pour valider une vente.
  Future<bool> createCommand(CommandRequest commandData) async {
    // 1. VRAIE vérification de la disponibilité du micro-service
    bool serverIsUp = await NetworkChecker.isBackendAccessible();

    if (serverIsUp) {
      try {
        if (kDebugMode) print("➡️ Mode Online : Envoi de la commande au serveur...");

        // Tentative d'envoi au serveur avec un timeout maîtrisé (5s suffisent puisque le serveur répond)
        final response = await http.post(
          Uri.parse(apiUrl),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode(commandData.toJson()),
        ).timeout(const Duration(seconds: 5));

        if (response.statusCode == 201 || response.statusCode == 200) {
          if (kDebugMode) print("✅ Succès Serveur");

          // On prépare la donnée pour le cache local en la marquant comme synchronisée
          Map<String, dynamic> data = commandData.toJson();
          data['isSynced'] = 1;

          // Mise à jour du cache local pour la cohérence des données
          await _dbHelper.syncCommandsLocal([data]);
          return true;
        }
      } catch (e) {
        if (kDebugMode) print("⚠️ Erreur ou micro-coupure lors de l'envoi : $e");
        // On glisse vers la sauvegarde locale en cas d'imprévu
      }
    }

    // 2. Bascule automatique et silencieuse en local (Mode Offline)
    if (kDebugMode) print("🔄 Serveur inaccessible. Bascule : Sauvegarde locale...");
    return await saveOffline(commandData);
  }

  /// Sauvegarde forcée en local (SQLite + File d'attente de synchronisation)
  Future<bool> saveOffline(CommandRequest commandData) async {
    try {
      Map<String, dynamic> data = commandData.toJson();

      // Génération d'un ID temporaire pour le mode hors-ligne si nécessaire
      String syncId = data['id'] ?? "OFF_C4US_${DateTime.now().millisecondsSinceEpoch}";
      data['id'] = syncId;
      data['orderDate'] = data['orderDate'] ?? DateTime.now().toIso8601String();
      data['isSynced'] = 0; // Marqueur indispensable pour la future synchronisation

      // Sécurité : S'assurer que les colonnes 'deleted' et 'version' existent (par défaut 0)
      data['deleted'] = data['deleted'] ?? 0;
      data['version'] = data['version'] ?? 0;

      // 1. Enregistrement dans le cache local (SQFlite)
      await _dbHelper.syncCommandsLocal([data]);

      // 2. Ajout à la file d'attente pour synchronisation ultérieure
      await _dbHelper.addToSyncQueue(
          'INSERT',
          'commands',
          syncId,
          data
      );

      if (kDebugMode) print("💾 Sauvegarde locale réussie (Offline)");
      return true;
    } catch (e) {
      if (kDebugMode) print("❌ Erreur critique SQLite : $e");
      return false;
    }
  }

  /// Récupérer les commandes avec synchronisation automatique
  Future<List<dynamic>> getCommandsByStructure(String structureId) async {
    // 1. Vérification de l'état réel des micro-services
    bool serverIsUp = await NetworkChecker.isBackendAccessible();

    if (serverIsUp) {
      try {
        final response = await http.get(
            Uri.parse("$apiUrl/structure/$structureId")
        ).timeout(const Duration(seconds: 5));

        if (response.statusCode == 200) {
          final List<dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
          // On met à jour le local avec les données fraîches du serveur
          await _dbHelper.syncCommandsLocal(data);
          return data;
        }
      } catch (e) {
        if (kDebugMode) print("⚠️ Erreur fetch : $e");
      }
    }

    // 2. En cas d'échec ou serveur DOWN, on retourne immédiatement les données locales
    if (kDebugMode) print("📥 Mode Offline : Récupération depuis la base locale SQLite");
    return await _dbHelper.getLocalCommands(structureId);
  }

  /// Annulation d'une commande avec gestion hybride online/offline
  Future<bool> cancelOrder(String orderId) async {
    bool onlineSuccess = false;
    bool serverIsUp = await NetworkChecker.isBackendAccessible();

    if (serverIsUp) {
      try {
        final response = await http.put(Uri.parse("$apiUrl/$orderId/cancel")).timeout(const Duration(seconds: 5));
        onlineSuccess = response.statusCode == 200;
      } catch (_) {}
    }

    if (!onlineSuccess) {
      // Si hors-ligne ou erreur, on place l'annulation dans la file d'attente locale
      if (kDebugMode) print("💾 Annulation mise dans la file d'attente de synchronisation.");
      await _dbHelper.addToSyncQueue('UPDATE', 'commands', orderId, {'status': 'CANCELLED'});
    }
    return true;
  }

  /// Règlement d'un crédit client


  /// Règlement d'un crédit client (Mode Hybride : Serveur + File d'attente locale)
  ///
  ///
  Future<bool> settleCredit(String commandId, double amountPaid, String paymentMethod) async {
    bool serverIsUp = await NetworkChecker.isBackendAccessible();
    bool onlineSuccess = false;

    // 1. Tenter l'appel serveur
    if (serverIsUp) {
      try {
        final response = await http.put(
          Uri.parse('$baseUrl/command/settle/$commandId'),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({
            "amountPaid": amountPaid,
            "paymentMethod": paymentMethod
          }),
        ).timeout(const Duration(seconds: 5));

        onlineSuccess = (response.statusCode == 200);
        if (onlineSuccess) return true;
      } catch (e) {
        if (kDebugMode) print("❌ Erreur de connexion au serveur : $e");
      }
    }

    // 2. Si échec ou serveur DOWN, on enregistre en local pour synchroniser plus tard
    if (!onlineSuccess) {
      if (kDebugMode) print("💾 Serveur injoignable, sauvegarde locale...");
      await _dbHelper.addToSyncQueue(
          'UPDATE',
          'commands',
          commandId,
          {'amountPaid': amountPaid, 'paymentMethod': paymentMethod, 'status': 'SETTLED'}
      );
      return true; // On retourne true pour que l'interface confirme l'action
    }

    return false;
  }
}