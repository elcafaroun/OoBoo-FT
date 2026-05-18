import 'dart:convert';
import 'package:http/http.dart' as http;
import '../utils/constants.dart'; // Assure-toi que baseUrl est ici

class DepenseService {
  final String apiUrl = "$baseUrl/depense";

  // 1. Enregistrer une nouvelle dépense
  Future<bool> createDepense(Map<String, dynamic> depenseData) async {
    try {
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(depenseData),
      );
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      print("Erreur createDepense: $e");
      return false;
    }
  }

  // 2. Supprimer une dépense
  Future<bool> deleteDepense(int id) async {
    try {
      final response = await http.delete(Uri.parse("$apiUrl/$id"));
      return response.statusCode == 200 || response.statusCode == 204;
    } catch (e) {
      print("Erreur deleteDepense: $e");
      return false;
    }
  }

  // 3. Lister les dépenses d'une structure
  Future<List<dynamic>> getDepensesByStructure(String codeStructure) async {
    try {
      final response = await http.get(Uri.parse("$apiUrl/structure/$codeStructure"));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return [];
    } catch (e) {
      print("Erreur getDepenses: $e");
      return [];
    }
  }

  // 4. Somme des dépenses pour un jour précis
  Future<double> getSumByDay(String date, String codeStructure) async {
    try {
      // Format attendu de date: YYYY-MM-DD
      final response = await http.get(
        Uri.parse("$apiUrl/sum/day?date=$date&code=$codeStructure"),
      );
      if (response.statusCode == 200) {
        return double.parse(response.body.toString());
      }
      return 0.0;
    } catch (e) {
      print("Erreur getSumByDay: $e");
      return 0.0;
    }
  }

  // 5. Somme des dépenses entre deux dates (Période)
  Future<double> getSumByPeriod(String start, String end, String codeStructure) async {
    try {
      final response = await http.get(
        Uri.parse("$apiUrl/sum/period?start=$start&end=$end&code=$codeStructure"),
      );
      if (response.statusCode == 200) {
        return double.parse(response.body.toString());
      }
      return 0.0;
    } catch (e) {
      print("Erreur getSumByPeriod: $e");
      return 0.0;
    }
  }
}