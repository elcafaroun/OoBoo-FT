import 'dart:convert';
import 'dart:io';
import 'package:fada/utils/constants.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class CatService {

  // 🔹 1. Vérifier si le nom existe déjà (Validation en temps réel)
  Future<bool> checkCategoryNameExists(String name, String codeStructure) async {
    try {
      final url = Uri.parse('$baseUrl/category/exists').replace(
        queryParameters: {
          'name': name.trim(),
          'codeStructure': codeStructure,
        },
      );

      final response = await http.get(
        url,
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as bool;
      } else {
        debugPrint("Erreur validation existence: ${response.statusCode}");
        return false;
      }
    } catch (e) {
      debugPrint("Erreur lors de la vérification de la catégorie: $e");
      return false;
    }
  }

  // 🔹 2. Récupérer toutes les catégories d'une structure
  Future<List<dynamic>> getCategoriesByStructure(String structureId) async {
    final url = Uri.parse('$baseUrl/category/structure/$structureId');
    final response = await http.get(url);

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      if (body is List) return body;
      if (body is Map) return [body];
      return [];
    } else {
      throw Exception('Erreur serveur: ${response.statusCode} ${response.reasonPhrase}');
    }
  }

  // 🔹 3. Créer une catégorie
  Future<Map<String, dynamic>> createCategory({
    required String name,
    required String description,
    required String structureId,
  }) async {
    final url = Uri.parse('$baseUrl/category');
    final body = jsonEncode({
      "nameCat": name,
      "description": description,
      "codeStructure": structureId,
    });

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: body,
    );

    if (response.statusCode == 201 || response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Erreur création catégorie: ${response.statusCode}');
    }
  }

  // 🔹 4. Mettre à jour une catégorie
  Future<Map<String, dynamic>> updateCategory({
    required String categoryId,
    required String name,
    required String description,
    required String structureId,
  }) async {
    final url = Uri.parse('$baseUrl/category/$categoryId');
    final body = jsonEncode({
      "nameCat": name,
      "description": description,
      "codeStructure": structureId,
    });

    final response = await http.put(
      url,
      headers: {'Content-Type': 'application/json'},
      body: body,
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Erreur mise à jour catégorie: ${response.statusCode}');
    }
  }

  // 🔹 5. Supprimer une catégorie
  Future<void> deleteCategory(String categoryId) async {
    final url = Uri.parse('$baseUrl/category/$categoryId');
    final response = await http.delete(url);

    if (response.statusCode != 200) {
      throw Exception('Erreur suppression catégorie: ${response.statusCode}');
    }
  }

  // 🔹 6. Envoyer la photo (PUT)
  Future<String> uploadPhoto(String idCategory, File imageFile) async {
    final url = Uri.parse("$baseUrl/category/photo");

    final request = http.MultipartRequest('PUT', url)
      ..fields['id'] = idCategory
      ..files.add(await http.MultipartFile.fromPath('file', imageFile.path));

    debugPrint('📤 Upload photo => Category ID: $idCategory');

    final response = await request.send();

    if (response.statusCode == 200) {
      final respStr = await response.stream.bytesToString();
      debugPrint('✅ Photo envoyée avec succès');
      return respStr;
    } else {
      final error = await response.stream.bytesToString();
      debugPrint('❌ Erreur upload (${response.statusCode}) : $error');
      throw Exception("Erreur upload photo : $error");
    }
  }

  // 🔹 7. Mettre à jour le statut actif/inactif
  Future<Map<String, dynamic>> updateStatus({
    required String categoryId,
    required bool isActive,
  }) async {
    final url = Uri.parse('$baseUrl/category/updateStatus/$categoryId');
    final body = jsonEncode({"active": isActive});

    final response = await http.patch(
      url,
      headers: {'Content-Type': 'application/json'},
      body: body,
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Erreur mise à jour statut: ${response.statusCode}');
    }
  }
}