import 'dart:convert';
import 'package:http/http.dart' as http;
import '../utils/constants.dart';
import '../models/subscription_plan.dart';

class SubscriptionService {

  Future<List<SubscriptionPlan>> getAllPlans() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/souscriptions'), // Correspond à votre @RequestMapping("/api/plans")
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        List<dynamic> body = jsonDecode(utf8.decode(response.bodyBytes));

        // Conversion de la liste dynamique en liste de modèles SubscriptionPlan
        List<SubscriptionPlan> plans = body.map((dynamic item) => SubscriptionPlan.fromJson(item)).toList();
        return plans;
      } else {
        throw Exception("Erreur de chargement : ${response.statusCode}");
      }
    } catch (e) {
      print("Erreur service plans : $e");
      return []; // Retourne une liste vide en cas d'erreur pour éviter le crash
    }
  }
}