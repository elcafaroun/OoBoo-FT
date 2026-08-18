import 'dart:convert';
import 'dart:io';
import 'package:fada/services/database/database_helper.dart';
import 'package:fada/utils/constants.dart';
import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;
import 'network_checker.dart';

class ProductService {
  final apiUrl = '$baseUrl/product';
  final DatabaseHelper _dbHelper = DatabaseHelper();

  // --- 1. FONCTIONNALITÉS PAR SCAN (QR CODE) ---

  /// Vérifie si un code QR existe déjà pour la structure donnée
  Future<Map<String, dynamic>> checkProductByQrCode({
    required String qrCode,
    required String codeStructure,
  }) async {
    if (!(await NetworkChecker.isBackendAccessible())) {
      return {'exists': false, 'message': 'Serveur hors-ligne', 'product': null};
    }

    try {
      final url = Uri.parse('$apiUrl/scan-check').replace(
        queryParameters: {
          'qrCode': qrCode.trim(),
          'codeStructure': codeStructure.trim(),
        },
      );

      final response = await http.get(
        url,
        headers: {"Content-Type": "application/json"},
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return {'exists': false, 'message': 'Erreur serveur', 'product': null};
    } catch (e) {
      debugPrint("Erreur lors de la vérification du code QR: $e");
      return {'exists': false, 'message': 'Exception: $e', 'product': null};
    }
  }

  /// Réalise une entrée rapide en stock via le code QR
  Future<Map<String, dynamic>> addStockByQrCode({
    required String productQrCode,
    required String codeStructure,
    required double quantity,
  }) async {
    if (!(await NetworkChecker.isBackendAccessible())) {
      throw Exception('📡 Impossible de mettre à jour le stock : Serveur hors-ligne.');
    }

    try {
      final url = Uri.parse('$apiUrl/stock-entry');
      final payload = {
        "productQrCode": productQrCode.trim(),
        "codeStructure": codeStructure.trim(),
        "quantity": quantity,
      };

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final updatedProduct = jsonDecode(response.body) as Map<String, dynamic>;
        await _dbHelper.syncProductsLocal([updatedProduct]);
        return updatedProduct;
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? error['message'] ?? 'Erreur lors de l\'entrée en stock');
      }
    } catch (e) {
      debugPrint("🚨 Exception lors de l'entrée rapide en stock : $e");
      rethrow;
    }
  }

  // --- 2. MÉTHODES DE COMPATIBILITÉ (OPTION 1) ---

  /// Recherche un produit par son QR Code et retourne la Map du produit ou null
  Future<Map<String, dynamic>?> getProductByQrCode({
    required String qrCode,
    required String codeStructure,
  }) async {
    final result = await checkProductByQrCode(
      qrCode: qrCode,
      codeStructure: codeStructure,
    );

    if (result['exists'] == true && result['product'] != null) {
      return result['product'] as Map<String, dynamic>;
    }
    return null;
  }

  /// Met à jour le stock via l'API `/stock-entry` du backend Spring Boot
  Future<void> updateStock(String qrCode, double quantityToAdd, {String? codeStructure}) async {
    final structure = codeStructure ?? "DEFAUT";

    if (await NetworkChecker.isBackendAccessible()) {
      await addStockByQrCode(
        productQrCode: qrCode,
        codeStructure: structure,
        quantity: quantityToAdd,
      );
    } else {
      // Gestion du mode offline avec mise en file d'attente SQLite
      final payload = {
        "productQrCode": qrCode,
        "codeStructure": structure,
        "quantity": quantityToAdd,
      };

      await _dbHelper.addToSyncQueue(
        'STOCK_ENTRY',
        'products',
        qrCode,
        payload,
      );
    }
  }

  // --- 3. GESTION DU STOCK (DÉDUCTION / VENTE) ---
  Future<bool> updateProductStock(String productId, int quantityToDeduct) async {
    final Map<String, dynamic> payload = {
      "productId": productId,
      "deductQuantity": quantityToDeduct,
    };

    try {
      await _dbHelper.updateProductStock(productId, quantityToDeduct.toDouble());

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
      }
    } catch (e) {
      debugPrint("❌ Erreur lors de la mise à jour réseau : $e");
    }

    try {
      await _dbHelper.addToSyncQueue(
        'UPDATE_STOCK',
        'products',
        productId,
        payload,
      );
    } catch (queueError) {
      debugPrint("🚨 Échec d'écriture dans la file SQLite : $queueError");
    }
    return true;
  }

  // --- 4. CRÉATION ET MODIFICATION ---
  Future<Map<String, dynamic>> createProduct(Map<String, dynamic> productData) async {
    if (!(await NetworkChecker.isBackendAccessible())) {
      throw Exception('📡 Impossible de créer le produit : Micro-services injoignables.');
    }

    try {
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(productData),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 201 || response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Erreur ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
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

  // --- 5. RÉCUPÉRATION DES DONNÉES ---
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

          await _dbHelper.syncProductsLocal(productsList);
          return productsList;
        }
      } catch (e) {
        debugPrint("⚠️ Erreur réseau getProducts : $e");
      }
    }

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
        debugPrint("⚠️ Erreur réseau fetch produit $id : $e");
      }
    }

    final localProduct = await _dbHelper.getProductById(id);
    if (localProduct != null) {
      return Map<String, dynamic>.from(localProduct);
    }
    throw Exception('Produit introuvable.');
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
        debugPrint("⚠️ Erreur réseau catégorie $categoryId : $e");
      }
    }

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

          await _dbHelper.syncProductsLocal(serverProducts);
          return serverProducts;
        }
      } catch (e) {
        debugPrint("Erreur produits structure réseau : $e");
      }
    }

    try {
      final List<dynamic> localData = await _dbHelper.getLocalEntities('products', structureId);
      return localData.map((e) => e as Map<String, dynamic>).toList();
    } catch (e) {
      return [];
    }
  }

  // --- 6. SUPPRESSION ET MEDIAS ---
  Future<Map<String, dynamic>> deleteProduct(String id) async {
    if (!(await NetworkChecker.isBackendAccessible())) {
      throw Exception('📡 Impossible de supprimer le produit : Serveur hors-ligne.');
    }

    try {
      final response = await http.delete(Uri.parse('$apiUrl/$id')).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Erreur suppression : ${response.statusCode}');
      }
    } catch (e) {
      rethrow;
    }
  }

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
        throw Exception("Erreur upload photo : ${response.statusCode}");
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
        return await File('${Directory.systemTemp.path}/$filename').writeAsBytes(bytes);
      } else {
        throw Exception('Erreur photo : Statut ${response.statusCode}');
      }
    } catch (e) {
      rethrow;
    }
  }

  // --- 7. ALERTES ET REQUÊTES MÉTIERS ---
  Future<List<Map<String, dynamic>>> fetchStockAlerts(String codeStructure) async {
    if (await NetworkChecker.isBackendAccessible()) {
      try {
        final response = await http.get(Uri.parse('$apiUrl/status/low-stock/$codeStructure')).timeout(const Duration(seconds: 5));
        if (response.statusCode == 200) {
          List<dynamic> data = jsonDecode(response.body);
          return data.map((e) => e as Map<String, dynamic>).toList();
        }
      } catch (e) {
        debugPrint("Erreur récupération alertes réseau: $e");
      }
    }
    return [];
  }

  Future<Map<String, dynamic>> updateStatus({
    required String categoryId,
    required bool isActive,
  }) async {
    if (!(await NetworkChecker.isBackendAccessible())) {
      throw Exception('📡 Changement de statut impossible : Serveur hors-ligne.');
    }

    final url = Uri.parse('$baseUrl/product/updateStatus/$categoryId');
    final response = await http.patch(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({"active": isActive}),
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
      return false;
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
      return false;
    }
  }

  Future<int> countProductsByStructure(String structureId) async {
    if (await NetworkChecker.isBackendAccessible()) {
      try {
        final url = Uri.parse('$apiUrl/count/structure/$structureId');
        final response = await http.get(url).timeout(const Duration(seconds: 5));

        if (response.statusCode == 200) {
          final count = jsonDecode(response.body);
          if (count is int) return count;
          if (count is num) return count.toInt();
        }
      } catch (e) {
        debugPrint("⚠️ Erreur réseau comptage produits : $e");
      }
    }

    try {
      final localProducts = await _dbHelper.getLocalEntities('products', structureId);
      return localProducts.length;
    } catch (e) {
      return 0;
    }
  }


  // En haut du fichier ou dans ProductService
  Future<bool> checkBarcodeExists(String barcode, {String? excludeProductId}) async {
    try {
      final response = await http.get(
        Uri.parse('$apiUrl/products/check-barcode?barcode=$barcode'),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // Retourne vrai si le code existe déjà sur UN AUTRE produit
        return data['exists'] == true && data['productId'] != excludeProductId;
      }
      return false;
    } catch (e) {
      debugPrint("Erreur vérification barcode : $e");
      return false;
    }
  }
}