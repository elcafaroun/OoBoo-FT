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
    data['cout'] = plan.cout ?? 0.0;
    data['priorite'] = plan.priorite;
    data['smsAlerte'] = plan.smsAlerte ?? false;
    data['stockAlerte'] = plan.stockAlerte ?? false;
    data['emailAlerte'] = plan.emailAlerte ?? false;
    data['dashboard'] = plan.dashboard ?? false;
    data['loyaltyAccess'] = plan.loyaltyAccess ?? false;
    data['gracePeriode'] = plan.gracePeriode;
    data['nombreJourSouscription'] = plan.nombreJourSouscription;
    data['nombreCategorieParBusiness'] = plan.nombreCategorieParBusiness;
    data['nombreProdParBusiness'] = plan.nombreProdParBusiness;
  }

  /// 🔹 Sauvegarde physique d'une image dans le stockage de l'appareil
  Future<String> _saveImageLocally(File imageFile) async {
    final directory = await getApplicationDocumentsDirectory();
    final String fileName = "struct_${DateTime.now().millisecondsSinceEpoch}${p.extension(imageFile.path)}";
    final File localImage = await imageFile.copy('${directory.path}/$fileName');
    return localImage.path;
  }

  /// 🔹 Création d’une structure (Enrichissement des détails du Plan + Gestion Photo + Sync Queue)
  Future<void> createStructure(Map<String, dynamic> data, {File? imageFile}) async {
    String? localPath;

    // 1️⃣ Récupération du plan pour injecter tous ses détails dans les données de la structure
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

    // 2️⃣ Récupération sécurisée du userId connecté
    final prefs = await SharedPreferences.getInstance();
    final String? userId = prefs.getString('userId');
    debugPrint("✅ [Login] userId récupéré du serveur : $userId");

    if (userId == null || userId.trim().isEmpty) {
      debugPrint("❌ [StructureService] Erreur : 'userId' introuvable dans SharedPreferences.");
      throw Exception("Votre session d'authentification a expiré. Veuillez vous reconnecter.");
    }

    if (imageFile != null) {
      localPath = await _saveImageLocally(imageFile);
      data['photoPath'] = localPath;
    }

    bool serverIsUp = await NetworkChecker.isBackendAccessible();

    // 3️⃣ MODE ONLINE
    if (serverIsUp) {
      try {
        final String finalUrl = '$baseUrl/structure?userId=${Uri.encodeComponent(userId.trim())}';
        debugPrint("📡 Envoi POST vers l'API : $finalUrl");

        final response = await http.post(
          Uri.parse(finalUrl),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode(data),
        ).timeout(const Duration(seconds: 5));

        if (response.statusCode == 200 || response.statusCode == 201) {
          debugPrint("✅ Structure créée avec succès sur le serveur");

          // 🔹 FIX : On décode la réponse pour récupérer l'ID généré par le serveur
          final createdData = jsonDecode(utf8.decode(response.bodyBytes));

          // 🔹 Sauvegarde immédiate dans la base locale SQLite (structures + lien user)
          if (createdData is Map<String, dynamic>) {
            await _dbHelper.syncStructuresLocal([createdData]);
          } else {
            // Si le serveur renvoie juste 200 sans l'objet complet
            data['createdUserId'] = userId.trim();
            await _dbHelper.syncStructuresLocal([data]);
          }

          return;
        } else {
          debugPrint("⚠️ Serveur a répondu avec le code : ${response.statusCode}. Bascule vers la file d'attente.");
        }
      } catch (e) {
        debugPrint("⚠️ Échec envoi serveur, mise en file d'attente : $e");
      }
    }

    // 4️⃣ MODE OFFLINE : Sauvegarde dans la file d'attente locale SQFlite
    String entityId = (data['idStructure'] ?? data['id'] ?? "TEMP_${DateTime.now().millisecondsSinceEpoch}").toString();

    data['createdUserId'] = userId.trim();

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

  /// 🔹 Mise à jour d'une structure avec gestion du plan
  Future<bool> updateStructure(String id, Map<String, dynamic> data, {File? imageFile}) async {
    String? localImagePath;

    // Si le nom du plan est modifié, on met à jour les détails du plan dans les champs
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

    if (imageFile != null) {
      localImagePath = await _saveImageLocally(imageFile);
      data['photoPath'] = localImagePath;
      data['structPhotoUrl'] = localImagePath;
    }

    bool serverIsUp = await NetworkChecker.isBackendAccessible();

    if (serverIsUp) {
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
        }
      } catch (_) {}
    }

    try {
      final db = await _dbHelper.database;
      Map<String, dynamic> cleanData = Map.from(data);
      cleanData.remove('users');
      cleanData.remove('userStructures');

      await db.update(
        'structures',
        {
          ...cleanData,
          'lastUpdated': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );

      if (localImagePath != null) {
        await _dbHelper.updateEntityPhotoPath('structures', id, localImagePath);
      }

      await _dbHelper.addToSyncQueue('UPDATE', 'structures', id, data);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 🔹 Mise à jour de la photo uniquement
  Future<void> updatePhoto(String structureId, File imageFile) async {
    String localPath = await _saveImageLocally(imageFile);
    await _dbHelper.updateEntityPhotoPath('structures', structureId, localPath);

    bool serverIsUp = await NetworkChecker.isBackendAccessible();
    if (serverIsUp) {
      await updateStructure(structureId, {'id': structureId}, imageFile: imageFile);
    }
  }

  /// 🔹 Mise à jour du plan d'abonnement avec mise à jour locale SQLite
  /// 🔹 Mise à jour du plan d'abonnement (Uniquement Online)
  Future<void> updateStructurePlan(String id, SubscriptionPlan plan) async {
    // 1️⃣ Vérification de la connectivité serveur
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
      // 2️⃣ Envoi de la requête au backend
      final response = await http.put(
        url,
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 5));

      // 3️⃣ Contrôle du code de retour HTTP
      if (response.statusCode != 200) {
        throw Exception("Erreur serveur (${response.statusCode}) : ${response.body}");
      }

      debugPrint("✅ Plan de la structure $id mis à jour vers '${plan.name}' sur le serveur.");
    } catch (e) {
      debugPrint("❌ Erreur lors de la mise à jour du plan : $e");
      throw Exception("Erreur lors de la mise à jour du plan : $e");
    }
  }

  /// 🗑️ Suppression d'une structure
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

  /// 🔹 Mise à jour du statut (Activé/Désactivé)
  /// 🔹 Mise à jour du statut Activé/Désactivé (Uniquement Online)
  Future<void> updateStructureStatus(String id, bool isActive) async {
    // 1️⃣ Contrôle de la connexion serveur
    bool serverIsUp = await NetworkChecker.isBackendAccessible();

    if (!serverIsUp) {
      throw Exception("📡 Action impossible hors-ligne : La mise à jour du statut requiert une connexion.");
    }

    try {
      // 2️⃣ Envoi de la requête PATCH au backend
      final url = Uri.parse('$baseUrl/structure/updateStatus/$id');

      final response = await http.patch(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"active": isActive}),
      ).timeout(const Duration(seconds: 5));

      // 3️⃣ Validation du code de réponse HTTP
      if (response.statusCode == 200) {
        debugPrint("✅ Statut de la structure $id mis à jour avec succès sur le serveur.");
      } else {
        throw Exception("Erreur serveur (${response.statusCode}) : ${response.body}");
      }
    } catch (e) {
      debugPrint("❌ Erreur lors de la mise à jour du statut : $e");
      throw Exception("Impossible de mettre à jour le statut : $e");
    }
  }

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


  /// 🔹 Récupérer une structure unique par son ID (Online -> Local Fallback)
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


}