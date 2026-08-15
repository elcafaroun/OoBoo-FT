import 'dart:convert';
import 'package:http/http.dart' as http;
import '../utils/constants.dart';

class DashboardService {

  /// Récupère le résumé global quotidien (Ventes, Dépenses, Bénéfice)
  Future<Map<String, dynamic>> getDailySummary(String date, String codeStructure) async {
    try {
      final response = await http.get(
        Uri.parse("$baseUrl/command/dashboard/summary?date=$date&code=$codeStructure"),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      print("Erreur Daily Summary: $e");
    }
    return {"totalDepenses": 0.0, "totalCommandes": 0.0, "benefice": 0.0};
  }

  /// Récupère la répartition quotidienne par mode de paiement
  Future<Map<String, dynamic>> getPaymentMethodsStats(String date, String codeStructure) async {
    try {
      final response = await http.get(
        Uri.parse("$baseUrl/command/stats/payment-methods?date=$date&code=$codeStructure"),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      print("Erreur PaymentStats: $e");
    }
    return {};
  }

  /// Récupère les ventes groupées par agent
  Future<List<dynamic>> getSalesByUser(String codeStructure) async {
    try {
      final response = await http.get(
        Uri.parse("$baseUrl/command/structure/$codeStructure/sales-by-user"),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as List<dynamic>;
      }
    } catch (e) {
      print("Erreur getSalesByUser: $e");
    }
    return [];
  }

  /// Récupère les totaux journaliers des VENTES pour le mois sélectionné
  Future<Map<String, double>> getMonthlyDailySales(String codeStructure, String yearMonth) async {
    try {
      final response = await http.get(
        Uri.parse("$baseUrl/command/structure/$codeStructure/monthly-daily-sales?period=$yearMonth"),
      );
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        return data.map((key, value) => MapEntry(key, (value as num).toDouble()));
      }
    } catch (e) {
      print("Erreur getMonthlyDailySales: $e");
    }
    return {};
  }

  /// Récupère les totaux journaliers des DÉPENSES pour le mois sélectionné
  // Assurez-vous d'avoir cette méthode dans votre lib/services/depense_service.dart
  Future<List<dynamic>> getExpensesByUser(String structureId) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/depense/structure/$structureId/by-user'));

      if (response.statusCode == 200) {
        return json.decode(response.body) as List<dynamic>;
      } else {
        print("Erreur API Depenses: ${response.statusCode} - ${response.body}");
        return [];
      }
    } catch (e) {
      print("Erreur connexion DepenseService: $e");
      return [];
    }
  }
}