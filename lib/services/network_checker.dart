import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';
import '../utils/constants.dart';

class NetworkChecker {
  /// Vérifie si le smartphone a un accès matériel au réseau
  /// ET si l'instance Spring Boot (Actuator) répond correctement.
  static Future<bool> isBackendAccessible() async {
    try {
      // 1. Vérification matérielle de la connectivité
      final List<ConnectivityResult> connectivityResults = await Connectivity().checkConnectivity();

      if (connectivityResults.contains(ConnectivityResult.none)) {
        debugPrint("🛰️ [NetworkChecker] Aucun réseau matériel détecté.");
        return false;
      }

      // 2. Vérification applicative (Ping Actuator)
      final response = await http
          .get(Uri.parse('$baseUrl/actuator/health'))
          .timeout(const Duration(seconds: 3));

      // Renvoie true si le statut est OK (200-499) pour éviter de bloquer sur des 401/403
      return response.statusCode >= 200 && response.statusCode < 500;

    } on SocketException catch (e) {
      debugPrint("📡 [NetworkChecker] Serveur injoignable (SocketException) : $e");
      return false;
    } on Exception catch (e) {
      debugPrint("⚠️ [NetworkChecker] Erreur réseau générale : $e");
      return false;
    }
  }
}