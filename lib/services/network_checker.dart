import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';
import '../utils/constants.dart';

class NetworkChecker {
  /// Teste si le smartphone a Internet ET si les micro-services répondent
  static Future<bool> isBackendAccessible() async {
    // 1. Vérification matérielle (Wi-Fi / Data)
    var connectivityResult = await (Connectivity().checkConnectivity());
    if (connectivityResult.contains(ConnectivityResult.none)) {
      return false; // Pas du tout de réseau
    }

    // 2. Vérification logicielle (Le micro-service répond-il ?)
    try {
      // On utilise une requête HEAD ou un endpoint de ping léger pour ne pas surcharger le serveur
      final response = await http.get(Uri.parse('$baseUrl/actuator/health')) // Ou juste Uri.parse('$baseUrl/')
          .timeout(const Duration(seconds: 3)); // Timeout très court pour ne pas bloquer l'utilisateur

      // Si le serveur répond (peu importe le code, même 404 ou 401, tant qu'il répond), c'est qu'il est vivant
      return response.statusCode >= 200 && response.statusCode < 500;
    } on SocketException catch (_) {
      print("📡 Le serveur à l'adresse $baseUrl est injoignable (Micro-service DOWN).");
      return false;
    } catch (_) {
      return false;
    }
  }
}