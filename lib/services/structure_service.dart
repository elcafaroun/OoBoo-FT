import 'dart:convert';
import 'dart:io';
import 'package:fada/services/database/database_helper.dart';
import 'package:fada/utils/constants.dart';
import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'network_checker.dart'; // 👈 IMPORT DU CHECKER UNIQUE

class StructureService {
  final DatabaseHelper _dbHelper = DatabaseHelper();

  /// 🔹 Sauvegarde physique d'une image dans le stockage de l'appareil
  Future<String> _saveImageLocally(File imageFile) async {
    final directory = await getApplicationDocumentsDirectory();
    final String fileName = "struct_${DateTime.now().millisecondsSinceEpoch}${p.extension(imageFile.path)}";
    final File localImage = await imageFile.copy('${directory.path}/$fileName');
    return localImage.path;
  }

  /// 🔹 Création d’une structure (Gestion Photo + Sync Queue)
  Future<void> createStructure(Map<String, dynamic> data, {File? imageFile}) async {
    String? localPath;

    if (imageFile != null) {
      localPath = await _saveImageLocally(imageFile);
      data['photoPath'] = localPath;
    }

    // Vérification de la disponibilité réelle des micro-services
    bool serverIsUp = await NetworkChecker.isBackendAccessible();

    if (serverIsUp) {
      try {
        final response = await http.post(
          Uri.parse('$baseUrl/structure'),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode(data),
        ).timeout(const Duration(seconds: 5));

        if (response.statusCode == 200 || response.statusCode == 201) {
          debugPrint("✅ Structure créée avec succès sur le serveur");
          return;
        }
      } catch (e) {
        debugPrint("⚠️ Échec envoi serveur, mise en file d'attente : $e");
      }
    }

    // 🔄 MODE OFFLINE AUTOMATIQUE : Sauvegarde dans la file d'attente locale SQFlite
    String entityId = (data['idStructure'] ?? data['id'] ?? "TEMP_${DateTime.now().millisecondsSinceEpoch}").toString();

    await _dbHelper.addToSyncQueue(
        'INSERT',
        'structures',
        entityId,
        data
    );

    if (localPath != null) {
      await _dbHelper.updateEntityPhotoPath('structures', entityId, localPath);
    }

    debugPrint("💾 Structure sauvegardée localement dans la file d'attente (Offline)");
  }

  /// 🔹 Récupérer une structure par son Code (Online -> Local Fallback)
  Future<List<dynamic>> getStructuresByCode(String codeStructure) async {
    bool serverIsUp = await NetworkChecker.isBackendAccessible();

    if (serverIsUp) {
      try {
        final response = await http.get(
          Uri.parse('$baseUrl/structure/$codeStructure'),
          headers: {'Content-Type': 'application/json'},
        ).timeout(const Duration(seconds: 5));

        if (response.statusCode == 200) {
          final dynamic data = jsonDecode(utf8.decode(response.bodyBytes));
          await _dbHelper.syncStructuresLocal([data]);
          return [data];
        }
      } catch (e) {
        debugPrint("⚠️ Erreur réseau getByCode, bascule SQLite : $e");
      }
    }

    // 📥 BASCULE LOCALE : Requête directe dans SQLite
    print("📥 Mode Offline : Récupération de la structure par code depuis SQLite");
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> localData = await db.query(
      'structures',
      where: 'codeStructure = ?',
      whereArgs: [codeStructure],
    );
    return localData;
  }

  /// 🔹 Récupérer les structures par Utilisateur (AVEC FILTRAGE LOCAL)
  Future<List<dynamic>> getStructuresByUser(String userId) async {
    debugPrint('🔍 Recherche structures pour User ID: $userId');
    bool serverIsUp = await NetworkChecker.isBackendAccessible();

    if (serverIsUp) {
      try {
        final response = await http.get(
          Uri.parse('$baseUrl/structure/user/$userId'),
          headers: {'Content-Type': 'application/json'},
        ).timeout(const Duration(seconds: 5));

        if (response.statusCode == 200) {
          final List<dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
          await _dbHelper.syncStructuresLocal(data);
          return data;
        }
      } catch (e) {
        debugPrint("⚠️ Erreur réseau getByUser, bascule SQLite : $e");
      }
    }

    // 📥 BASCULE LOCALE : Utilisation de la méthode dédiée du DatabaseHelper
    final localData = await _dbHelper.getLocalStructuresByUser(userId);
    debugPrint("📂 [OFFLINE] Structures trouvées en local : ${localData.length}");
    return localData;
  }

  /// 🔹 Mise à jour de la photo d'une structure existante
  Future<void> updatePhoto(String structureId, File imageFile) async {
    String localPath = await _saveImageLocally(imageFile);

    // Persister d'abord l'information localement
    await _dbHelper.updateEntityPhotoPath('structures', structureId, localPath);

    bool serverIsUp = await NetworkChecker.isBackendAccessible();
    if (serverIsUp) {
      debugPrint("📡 Connecté : Prêt pour la synchronisation Multipart ultérieure avec le backend.");
      // Votre MultipartRequest éventuelle viendra s'insérer ici
    }
  }

  /// 🔹 Mise à jour du plan d'abonnement (Action bloquée ou échouée en Offline)
  Future<void> updateStructurePlan(String id, String planName) async {
    if (!(await NetworkChecker.isBackendAccessible())) {
      throw Exception("📡 Action impossible hors-ligne : Serveur de gestion des abonnements inaccessible.");
    }

    final url = Uri.parse('$baseUrl/structure/update-plan').replace(
      queryParameters: {'id': id, 'plan': planName},
    );

    try {
      final response = await http.put(url, headers: {'Content-Type': 'application/json'})
          .timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) {
        throw Exception("Erreur serveur (${response.statusCode})");
      }
    } catch (e) {
      throw Exception("Erreur lors de la mise à jour du plan : $e");
    }
  }

  /// 🗑️ Suppression d'une structure (Online d'abord avec nettoyage local direct)
  Future<void> deleteStructure(String id) async {
    bool serverIsUp = await NetworkChecker.isBackendAccessible();

    if (!serverIsUp) {
      throw Exception("📡 Action impossible hors-ligne : La suppression d'une structure requiert l'aval du serveur principal.");
    }

    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/structure/$id'),
        headers: {"Content-Type": "application/json"},
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200 || response.statusCode == 204) {
        final db = await _dbHelper.database;
        await db.delete('structures', where: 'id = ?', whereArgs: [id]);
        debugPrint("🗑️ Structure supprimée en ligne et en local.");
      } else {
        throw Exception("Échec serveur lors de la suppression.");
      }
    } catch (e) {
      throw Exception("Erreur lors de la suppression : $e");
    }
  }

  /// 🔹 Récupération des types de structures
  Future<List<dynamic>> getAllTypeStructures() async {
    if (await NetworkChecker.isBackendAccessible()) {
      try {
        final response = await http.get(
          Uri.parse('$baseUrl/typestructure'),
          headers: {'Content-Type': 'application/json'},
        ).timeout(const Duration(seconds: 5));

        if (response.statusCode == 200) {
          return jsonDecode(utf8.decode(response.bodyBytes));
        }
      } catch (e) {
        debugPrint("⚠️ Erreur réseau getAllTypeStructures : $e");
      }
    }
    return []; // Liste vide pour sécuriser l'affichage UI
  }

  /// 🔹 Récupération des villes configurées
  Future<List<dynamic>> getAllVilleStructures() async {
    if (await NetworkChecker.isBackendAccessible()) {
      try {
        final response = await http.get(
          Uri.parse('$baseUrl/villestructure'),
          headers: {'Content-Type': 'application/json'},
        ).timeout(const Duration(seconds: 5));

        if (response.statusCode == 200) {
          return jsonDecode(utf8.decode(response.bodyBytes));
        }
      } catch (e) {
        debugPrint("⚠️ Erreur réseau getAllVilleStructures : $e");
      }
    }
    return [];
  }

  /// 🔹 Vérification de l'unicité d'un nom de structure
  Future<bool> checkStructureNameExists(String nom) async {
    if (!(await NetworkChecker.isBackendAccessible())) {
      // En mode déconnecté, on renvoie false pour ne pas bloquer les créations locales temporaires
      return false;
    }

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/structure/exists?nom=${Uri.encodeComponent(nom)}'),
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as bool;
      }
    } catch (e) {
      debugPrint("Erreur checkName : $e");
    }
    return false;
  }
}