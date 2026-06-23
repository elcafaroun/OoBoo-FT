import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';
import '../utils/constants.dart';

class NetworkChecker {
  static Future<bool> isBackendAccessible() async {
    try {
      // 1. Vérification matérielle moderne
      final List<ConnectivityResult> connectivityResults = await Connectivity().checkConnectivity();

      // Si on est déconnecté (aucune connexion dans la liste)
      if (connectivityResults.contains(ConnectivityResult.none)) {
        return false;
      }

      // 2. Vérification logicielle (Ping)
      // Note : utilisez un endpoint simple qui ne nécessite pas de token
      final response = await http.get(Uri.parse('$baseUrl/actuator/health'))
          .timeout(const Duration(seconds: 3));

      return response.statusCode >= 200 && response.statusCode < 500;

    } on SocketException catch (e) {
      print("📡 Serveur injoignable : $e");
      return false;
    } on Exception catch (e) {
      print("⚠️ Erreur réseau : $e");
      return false;
    }
  }
}