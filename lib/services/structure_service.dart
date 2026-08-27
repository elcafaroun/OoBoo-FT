import 'dart:convert';
import 'dart:io';
import 'package:fada/models/subscription_plan.dart';
import 'package:fada/services/database/database_helper.dart';
import 'package:fada/services/subscription_service.dart';
import 'package:fada/utils/constants.dart';
import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'network_checker.dart';

class StructureService {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SubscriptionService _subscriptionService = SubscriptionService();

  /// 🔹 Copie les attributs et quotas d'un plan vers la Map de données de la structure
  void _applyPlanDetailsToStructureData(Map<String, dynamic> data, SubscriptionPlan plan) {
    data['planStructure'] = plan.name;
    data['cout'] = plan.cout ?? double.tryParse(plan.price.toString()) ?? 0.0;
    data['priorite'] = plan.priorite ?? 0;
    data['smsAlerte'] = plan.smsAlerte ?? false;
    data['stockAlerte'] = plan.stockAlerte ?? false;
    data['emailAlerte'] = plan.emailAlerte ?? false;
    data['dashboard'] = plan.dashboard ?? false;
    data['loyaltyAccess'] = plan.loyaltyAccess ?? false;
    data['gracePeriode'] = plan.gracePeriode ?? 0;
    data['nombreJourSouscription'] = plan.nombreJourSouscription ?? 0;
    data['nombreCategorieParBusiness'] = plan.nombreCategorieParBusiness ?? 0;
    data['nombreProdParBusiness'] = plan.nombreProdParBusiness ?? 0;
    data['nombreBusiness'] = plan.nombreBusiness ?? 1;
  }

  /// 🔹 Sauvegarde physique d'une image dans le stockage de l'appareil
  Future<String> _saveImageLocally(File imageFile) async {
    final directory = await getApplicationDocumentsDirectory();
    final String fileName = "struct_${DateTime.now().millisecondsSinceEpoch}${p.extension(imageFile.path)}";
    final File localImage = await imageFile.copy('${directory.path}/$fileName');
    return localImage.path;
  }

  /// 🔹 Création d’une structure (Uniquement Online)
  Future<void> createStructure(Map<String, dynamic> data, {File? imageFile}) async {
    bool serverIsUp = await NetworkChecker.isBackendAccessible();
    if (!serverIsUp) {
      throw Exception("📡 Action impossible hors-ligne : La création d'une structure requiert une connexion Internet.");
    }

    if (data['planStructure'] != null && data['planStructure'].toString().isNotEmpty) {
      try {
        List<SubscriptionPlan> plans = await _subscriptionService.getAllPlans();
        SubscriptionPlan? selectedPlan = plans.firstWhere(
              (p) => p.name.toLowerCase() == data['planStructure'].toString().toLowerCase(),
          orElse: () => SubscriptionPlan(name: data['planStructure'], price: '0'),
        );
        _applyPlanDetailsToStructureData(data, selectedPlan);
      } catch (e) {
        debugPrint("⚠️ Impossible de charger les détails complets du plan : $e");
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final String? userId = prefs.getString('userId');

    if (userId == null || userId.trim().isEmpty) {
      throw Exception("Votre session d'authentification a expiré. Veuillez vous reconnecter.");
    }

    String? localPath;
    if (imageFile != null) {
      localPath = await _saveImageLocally(imageFile);
      data['photoPath'] = localPath;
    }

    try {
      final String finalUrl = '$baseUrl/structure?userId=${Uri.encodeComponent(userId.trim())}';
      debugPrint("📡 Envoi POST vers l'API : $finalUrl");

      final response = await http.post(
        Uri.parse(finalUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(data),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint("✅ Structure créée avec succès sur le serveur");

        final createdData = jsonDecode(utf8.decode(response.bodyBytes));

        if (createdData is Map<String, dynamic>) {
          await _dbHelper.syncStructuresLocal([createdData]);
        } else {
          data['createdUserId'] = userId.trim();
          await _dbHelper.syncStructuresLocal([data]);
        }
      } else {
        throw Exception("Erreur serveur (${response.statusCode}) : ${response.body}");
      }
    } catch (e) {
      debugPrint("❌ Échec de la création de structure : $e");
      rethrow;
    }
  }

  /// 🔹 Mise à jour d'une structure (Uniquement Online)
  Future<bool> updateStructure(String id, Map<String, dynamic> data, {File? imageFile}) async {
    bool serverIsUp = await NetworkChecker.isBackendAccessible();

    if (!serverIsUp) {
      throw Exception("📡 Action impossible hors-ligne : La mise à jour d'une structure requiert une connexion Internet.");
    }

    if (data['planStructure'] != null && data['planStructure'].toString().isNotEmpty) {
      try {
        List<SubscriptionPlan> plans = await _subscriptionService.getAllPlans();
        SubscriptionPlan? selectedPlan = plans.firstWhere(
              (p) => p.name.toLowerCase() == data['planStructure'].toString().toLowerCase(),
          orElse: () => SubscriptionPlan(name: data['planStructure'], price: '0'),
        );
        _applyPlanDetailsToStructureData(data, selectedPlan);
      } catch (e) {
        debugPrint("⚠️ Impossible de mettre à jour les détails du plan : $e");
      }
    }

    String? localImagePath;
    if (imageFile != null) {
      localImagePath = await _saveImageLocally(imageFile);
      data['photoPath'] = localImagePath;
      data['structPhotoUrl'] = localImagePath;
    }

    try {
      final url = Uri.parse('$baseUrl/structure/$id');
      var request = http.MultipartRequest('PUT', url);

      if (imageFile != null) {
        var stream = http.ByteStream(imageFile.openRead());
        var length = await imageFile.length();
        request.files.add(http.MultipartFile('file', stream, length, filename: p.basename(imageFile.path)));
      }

      data.forEach((key, value) {
        if (value != null) {
          request.fields[key] = value.toString();
        }
      });

      var streamedResponse = await request.send().timeout(const Duration(seconds: 15));
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200 || response.statusCode == 204) {
        Map<String, dynamic> responseData = data;
        if (response.body.isNotEmpty) {
          try {
            final decodedBody = jsonDecode(utf8.decode(response.bodyBytes));
            if (decodedBody is Map<String, dynamic>) {
              responseData = decodedBody;
            }
          } catch (_) {}
        }

        Map<String, dynamic> cleanData = Map.from(responseData);
        cleanData.remove('users');
        cleanData.remove('userStructures');

        final db = await _dbHelper.database;
        await db.update(
          'structures',
          {
            ...cleanData,
            'lastUpdated': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [id],
        );
        return true;
      } else {
        throw Exception("Erreur serveur (${response.statusCode}) : ${response.body}");
      }
    } catch (e) {
      debugPrint("❌ Erreur lors de la mise à jour de la structure : $e");
      rethrow;
    }
  }

  /// 🔹 Mise à jour de la photo uniquement (Uniquement Online)
  Future<void> updatePhoto(String structureId, File imageFile) async {
    bool serverIsUp = await NetworkChecker.isBackendAccessible();
    if (!serverIsUp) {
      throw Exception("📡 Action impossible hors-ligne : La mise à jour de la photo requiert une connexion Internet.");
    }

    String localPath = await _saveImageLocally(imageFile);
    await updateStructure(structureId, {'id': structureId}, imageFile: imageFile);
    await _dbHelper.updateEntityPhotoPath('structures', structureId, localPath);
  }

  /// 🔹 Mise à jour du plan d'abonnement (Uniquement Online)
  Future<void> updateStructurePlan(String id, SubscriptionPlan plan) async {
    if (!(await NetworkChecker.isBackendAccessible())) {
      throw Exception("📡 Action impossible hors-ligne : Serveur de gestion des abonnements inaccessible.");
    }

    final url = Uri.parse('$baseUrl/structure/update-plan').replace(
      queryParameters: {
        'id': id,
        'plan': plan.name,
      },
    );

    try {
      final response = await http.put(
        url,
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) {
        throw Exception("Erreur serveur (${response.statusCode}) : ${response.body}");
      }

      debugPrint("✅ Plan de la structure $id mis à jour vers '${plan.name}' sur le serveur.");
    } catch (e) {
      debugPrint("❌ Erreur lors de la mise à jour du plan : $e");
      rethrow;
    }
  }

  /// 🔹 Mise à jour du statut Activé/Désactivé (Uniquement Online)
  Future<void> updateStructureStatus(String id, bool isActive) async {
    bool serverIsUp = await NetworkChecker.isBackendAccessible();

    if (!serverIsUp) {
      throw Exception("📡 Action impossible hors-ligne : La mise à jour du statut requiert une connexion Internet.");
    }

    try {
      final url = Uri.parse('$baseUrl/structure/updateStatus/$id');

      final response = await http.patch(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"active": isActive}),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        debugPrint("✅ Statut de la structure $id mis à jour avec succès sur le serveur.");
      } else {
        throw Exception("Erreur serveur (${response.statusCode}) : ${response.body}");
      }
    } catch (e) {
      debugPrint("❌ Erreur lors de la mise à jour du statut : $e");
      rethrow;
    }
  }

  /// 🗑️ Suppression d'une structure (Uniquement Online)
  Future<void> deleteStructure(String id) async {
    bool serverIsUp = await NetworkChecker.isBackendAccessible();

    if (!serverIsUp) {
      throw Exception("📡 Action impossible hors-ligne : La suppression d'une structure requiert une connexion Internet.");
    }

    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/structure/$id'),
        headers: {"Content-Type": "application/json"},
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200 || response.statusCode == 204) {
        final db = await _dbHelper.database;
        await db.delete('structures', where: 'id = ?', whereArgs: [id]);
        debugPrint("🗑️ Structure supprimée sur le serveur et purgée localement.");
      } else {
        throw Exception("Erreur serveur (${response.statusCode}) : ${response.body}");
      }
    } catch (e) {
      debugPrint("❌ Erreur lors de la suppression de la structure : $e");
      rethrow;
    }
  }

  /// 🔹 Récupérer une structure par son Code (Online -> Local Fallback)
  Future<List<dynamic>> getStructuresByCode(String codeStructure) async {
    bool serverIsUp = await NetworkChecker.isBackendAccessible();

    if (serverIsUp) {
      try {
        final response = await http.get(
          Uri.parse('$baseUrl/structure/structure/$codeStructure'),
          headers: {'Content-Type': 'application/json'},
        ).timeout(const Duration(seconds: 5));

        if (response.statusCode == 200) {
          final dynamic data = jsonDecode(utf8.decode(response.bodyBytes));
          List<dynamic> listData = data is List ? data : [data];
          await _dbHelper.syncStructuresLocal(listData);
          return listData;
        }
      } catch (e) {
        debugPrint("⚠️ Erreur réseau getByCode, bascule SQLite : $e");
      }
    }

    debugPrint("📥 Mode Offline : Récupération de la structure par code depuis SQLite");
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> localData = await db.query(
      'structures',
      where: 'codeStructure = ?',
      whereArgs: [codeStructure],
    );
    return localData;
  }

  /// 🔹 Récupérer les structures par Utilisateur (Online -> Local Fallback)
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

    final localData = await _dbHelper.getLocalStructuresByUser(userId);
    debugPrint("📂 [OFFLINE] Structures trouvées en local : ${localData.length}");
    return localData;
  }

  /// 🔹 Récupération d'une structure par son ID (Uniquement Online)
  Future<Map<String, dynamic>?> getStructureById(String idStructure) async {
    bool serverIsUp = await NetworkChecker.isBackendAccessible();

    if (!serverIsUp) {
      debugPrint("📡 Mode hors-ligne : Action getStructureById impossible sans connexion.");
      return null;
    }

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/structure/$idStructure'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      } else {
        debugPrint("⚠️ Erreur serveur getStructureById (${response.statusCode})");
        return null;
      }
    } catch (e) {
      debugPrint("❌ Erreur réseau / timeout getStructureById : $e");
      return null;
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
    return [];
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
      return false;
    }

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/structure/exists?nom=${Uri.encodeComponent(nom.trim())}'),
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as bool;
      }
    } catch (e) {
      debugPrint("Erreur checkName : $e");
    }
    return false;
  }

  /// 🔹 Upload d'une photo sur le serveur
  Future<String> uploadPhoto(String idProduit, File imageFile) async {
    if (!(await NetworkChecker.isBackendAccessible())) {
      throw Exception('📡 Téléversement impossible : Mode hors-ligne actif.');
    }

    try {
      final url = Uri.parse("$baseUrl/structure/photo");
      final request = http.MultipartRequest('PUT', url)
        ..fields['id'] = idProduit
        ..files.add(await http.MultipartFile.fromPath('file', imageFile.path));

      final response = await request.send().timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        return await response.stream.bytesToString();
      } else {
        throw Exception("Erreur upload photo : Code statut ${response.statusCode}");
      }
    } catch (e) {
      rethrow;
    }
  }
}