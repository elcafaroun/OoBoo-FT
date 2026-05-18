import 'dart:convert';
import 'dart:io';
import 'package:fada/services/database/database_helper.dart';
import 'package:fada/utils/constants.dart';
import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;
import 'network_checker.dart'; // 👈 Centralise la source de vérité pour l'état du backend

class ProductService {
  final apiUrl = '$baseUrl/product';
  final DatabaseHelper _dbHelper = DatabaseHelper();

  // --- 1. GESTION DU STOCK ---
  Future<bool> updateProductStock(String productId, int quantityToDeduct) async {
    final Map<String, dynamic> payload = {
      "productId": productId,
      "deductQuantity": quantityToDeduct,
    };

    try {
      // 1. Mise à jour LOCALE immédiate (Priorité Fasogestion)
      await _dbHelper.updateProductStock(productId, quantityToDeduct.toDouble());

      // 2. VRAIE vérification de la disponibilité du micro-service
      bool serverIsUp = await NetworkChecker.isBackendAccessible();

      if (serverIsUp) {
        final url = Uri.parse("$apiUrl/update-stock");

        final response = await http.post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        ).timeout(const Duration(seconds: 5));

        if (response.statusCode == 200) {
          debugPrint("✅ Stock synchronisé avec le backend");
          return true;
        }
        debugPrint("⚠️ Statut serveur anormal (${response.statusCode}) lors de l'update stock. Envoi en file d'attente.");
      }
    } catch (e) {
      debugPrint("❌ Erreur lors de la tentative de mise à jour réseau : $e");
    }

    // 3. Cas Hors-ligne ou Erreur Serveur : On ajoute à la file d'attente
    debugPrint("⚠️ Action de stock ajoutée à la file d'attente SQLite");
    try {
      await _dbHelper.addToSyncQueue(
          'UPDATE_STOCK',
          'products',
          productId,
          payload
      );
    } catch (queueError) {
      debugPrint("🚨 Échec d'écriture dans la file d'attente SQLite : $queueError");
    }
    return true;
  }

  // --- 2. CRÉATION ET MODIFICATION ---
  Future<Map<String, dynamic>> createProduct(Map<String, dynamic> productData) async {
    if (!(await NetworkChecker.isBackendAccessible())) {
      throw Exception('📡 Impossible de créer le produit : Micro-services injoignables (Mode Offline actif).');
    }

    try {
      final bodyEncoded = jsonEncode(productData);
      debugPrint("📤 Envoi payload: $bodyEncoded");

      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: bodyEncoded,
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 201 || response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        debugPrint("🚨 DÉTAIL DE L'ERREUR 400/500 : ${response.body}");
        throw Exception('Erreur ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      debugPrint("🚨 Exception Catch lors de la création : $e");
      rethrow;
    }
  }

  Future<Map<String, dynamic>> updateProduct(String id, Map<String, dynamic> productData) async {
    if (!(await NetworkChecker.isBackendAccessible())) {
      throw Exception('📡 Impossible de modifier le produit : Serveur hors-ligne.');
    }

    try {
      final response = await http.put(
        Uri.parse('$apiUrl/$id'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(productData),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Erreur ${response.statusCode} lors de la mise à jour du produit');
      }
    } catch (e) {
      rethrow;
    }
  }

  // --- 3. RÉCUPÉRATION DES DONNÉES ---

  /// Récupération paginée globale (Retourne le cache SQLite global en fallback)
  Future<List<Map<String, dynamic>>> getProducts({int page = 0, int size = 10}) async {
    if (await NetworkChecker.isBackendAccessible()) {
      try {
        final response = await http.get(
          Uri.parse('$apiUrl?page=$page&size=$size'),
        ).timeout(const Duration(seconds: 5));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final List<dynamic> content = data['content'] ?? [];
          final List<Map<String, dynamic>> productsList = content.map((e) => e as Map<String, dynamic>).toList();

          // Optionnel : Mettre à jour le cache local au fur et à mesure
          await _dbHelper.syncProductsLocal(productsList);
          return productsList;
        }
      } catch (e) {
        debugPrint("⚠️ Erreur réseau getProducts, basculement local : $e");
      }
    }

    // Fallback unifié
    try {
      final List<dynamic> localData = await _dbHelper.getLocalEntities('products', 'ALL');
      return localData.map((e) => e as Map<String, dynamic>).toList();
    } catch (_) {
      return [];
    }
  }

  Future<Map<String, dynamic>> getProduct(String id) async {
    if (await NetworkChecker.isBackendAccessible()) {
      try {
        final response = await http.get(Uri.parse('$apiUrl/$id')).timeout(const Duration(seconds: 5));
        if (response.statusCode == 200) {
          return jsonDecode(response.body);
        }
      } catch (e) {
        debugPrint("⚠️ Erreur réseau lors du fetch produit $id : $e");
      }
    }

    // Fallback Local SQLite
    final localProduct = await _dbHelper.getProductById(id);
    if (localProduct != null) {
      return Map<String, dynamic>.from(localProduct);
    }
    throw Exception('Produit introuvable en ligne et dans le stockage de l\'appareil.');
  }

  Future<List<Map<String, dynamic>>> getProductsByCategory(String categoryId) async {
    if (await NetworkChecker.isBackendAccessible()) {
      try {
        final response = await http.get(Uri.parse('$apiUrl/category/$categoryId')).timeout(const Duration(seconds: 5));
        if (response.statusCode == 200) {
          final List<dynamic> data = jsonDecode(response.body);
          final List<Map<String, dynamic>> products = data.map((e) => e as Map<String, dynamic>).toList();

          await _dbHelper.syncProductsLocal(products);
          return products;
        }
      } catch (e) {
        debugPrint("⚠️ Erreur réseau catégorie $categoryId, basculement local : $e");
      }
    }

    // Récupération locale SQLite unifiée
    try {
      final List<dynamic> localData = await _dbHelper.getLocalEntities('products', categoryId);
      return localData.map((e) => e as Map<String, dynamic>).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getProductsByStructure(String structureId) async {
    if (await NetworkChecker.isBackendAccessible()) {
      try {
        final response = await http.get(Uri.parse('$apiUrl/structure/$structureId')).timeout(const Duration(seconds: 5));
        if (response.statusCode == 200) {
          final List<dynamic> data = jsonDecode(response.body);
          final List<Map<String, dynamic>> serverProducts = data.map((e) => e as Map<String, dynamic>).toList();

          // ✅ Rafraîchit le cache SQLite local
          await _dbHelper.syncProductsLocal(serverProducts);
          return serverProducts;
        }
        debugPrint("⚠️ Le serveur a retourné un statut ${response.statusCode} pour les structures.");
      } catch (e) {
        debugPrint("Erreur produits structure réseau : $e");
      }
    }

    // 📥 DÉTECTION OFFLINE AUTOMATIQUE
    debugPrint("📥 Mode Offline : Récupération des produits depuis SQLite pour la structure : $structureId");
    try {
      final List<dynamic> localData = await _dbHelper.getLocalEntities('products', structureId);
      return localData.map((e) => e as Map<String, dynamic>).toList();
    } catch (e) {
      debugPrint("❌ Impossible de lire les produits locaux de la structure : $e");
      return [];
    }
  }

  // --- 4. SUPPRESSION ---
  Future<Map<String, dynamic>> deleteProduct(String id) async {
    if (!(await NetworkChecker.isBackendAccessible())) {
      throw Exception('📡 Impossible de supprimer le produit : Serveur hors-ligne.');
    }

    try {
      final response = await http.delete(Uri.parse('$apiUrl/$id')).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Erreur suppression : Code statut ${response.statusCode}');
      }
    } catch (e) {
      rethrow;
    }
  }

  // --- 5. PHOTOS ET IMAGES ---
  Future<String> uploadPhoto(String idProduit, File imageFile) async {
    if (!(await NetworkChecker.isBackendAccessible())) {
      throw Exception('📡 Téléversement impossible : Mode hors-ligne actif.');
    }

    try {
      final url = Uri.parse("$apiUrl/photo");
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

  Future<File> getPhoto(String filename) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/image/$filename')).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;
        final tempFile = await File('${Directory.systemTemp.path}/$filename').writeAsBytes(bytes);
        return tempFile;
      } else {
        throw Exception('Erreur photo : Statut ${response.statusCode}');
      }
    } catch (e) {
      rethrow;
    }
  }

  // --- 6. ALERTES ET REQUÊTES MÉTIERS ---
  Future<List<Map<String, dynamic>>> fetchStockAlerts(String codeStructure) async {
    if (await NetworkChecker.isBackendAccessible()) {
      try {
        final response = await http.get(Uri.parse('$apiUrl/status/low-stock/$codeStructure')).timeout(const Duration(seconds: 5));

        if (response.statusCode == 200) {
          List<dynamic> data = jsonDecode(response.body);
          return data.map((e) => e as Map<String, dynamic>).toList();
        }
      } catch (e) {
        debugPrint("Erreur lors de la récupération des alertes réseau: $e");
      }
    }
    return []; // Mode hors-ligne ou erreur : pas de crash UI
  }

  Future<Map<String, dynamic>> updateStatus({
    required String categoryId,
    required bool isActive,
  }) async {
    if (!(await NetworkChecker.isBackendAccessible())) {
      throw Exception('📡 Changement de statut impossible : Serveur hors-ligne.');
    }

    final url = Uri.parse('$baseUrl/product/updateStatus/$categoryId');
    final body = jsonEncode({"active": isActive});

    final response = await http.patch(
      url,
      headers: {'Content-Type': 'application/json'},
      body: body,
    ).timeout(const Duration(seconds: 5));

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Erreur mise à jour statut: ${response.statusCode}');
    }
  }

  Future<bool> checkProductNameExists({
    required String productName,
    required String categoryId,
    required String codeStructure,
  }) async {
    if (!(await NetworkChecker.isBackendAccessible())) {
      return false; // Évite de bloquer la création locale en mode déconnecté
    }

    try {
      final url = Uri.parse('$baseUrl/product/check-duplicate').replace(
        queryParameters: {
          'name': productName.trim(),
          'categoryId': categoryId,
          'codeStructure': codeStructure,
        },
      );

      final response = await http.get(
        url,
        headers: {"Content-Type": "application/json"},
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as bool;
      }
      return false;
    } catch (e) {
      debugPrint("Erreur lors de la vérification du nom du produit: $e");
      return false;
    }
  }
}