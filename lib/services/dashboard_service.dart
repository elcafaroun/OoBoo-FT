import 'dart:convert';
import 'package:http/http.dart' as http;
import '../utils/constants.dart';

class DashboardService {
  // Récupère le résumé global (Total Commandes, Dépenses, Bénéfice)
  Future<Map<String, dynamic>> getDailySummary(String date, String codeStructure) async {
    try {
      final response = await http.get(
        Uri.parse("$baseUrl/command/dashboard/summary?date=$date&code=$codeStructure"),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      print("Erreur Summary: $e");
    }
    return {"totalDepenses": 0.0, "totalCommandes": 0.0, "benefice": 0.0};
  }

  // Récupère la répartition par mode de paiement
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
}