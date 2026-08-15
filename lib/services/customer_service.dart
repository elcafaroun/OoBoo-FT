import 'dart:convert';
import 'package:http/http.dart' as http;
import '../utils/constants.dart';
import 'database/database_helper.dart';
import 'network_checker.dart'; // 👈 IMPORT DU CHECKER UNIQUE

class CustomerService {
  final String apiUrl = "$baseUrl/customer";
  final DatabaseHelper _dbHelper = DatabaseHelper();

  Future<Map<String, dynamic>?> createCustomer(Map<String, dynamic> customerData) async {
    bool serverIsUp = await NetworkChecker.isBackendAccessible();
    print("🌐 Le NetworkChecker dit que le serveur est en ligne ? -> $serverIsUp");
    if (serverIsUp) {
      try {
        print("🚀 Tentative d'envoi au serveur : ${jsonEncode(customerData)}");

        final response = await http.post(
          Uri.parse(apiUrl),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode(customerData),
        ).timeout(const Duration(seconds: 5));

        print("📥 Réponse du serveur (Code ${response.statusCode}) : ${response.body}");

        if (response.statusCode == 201 || response.statusCode == 200) {
          final savedCustomer = jsonDecode(response.body);
          await _dbHelper.saveCustomerLocal(savedCustomer);
          return savedCustomer;
        } else {
          print("❌ Le serveur a refusé la requête avec le code : ${response.statusCode}");
        }
      } catch (e) {
        print("🔥 EXCEPTION RÉSEAU / PARSING : $e"); // <-- C'est ici qu'on verra la vraie raison !
      }
    }

    print("🔄 Fallback : Sauvegarde du client en local uniquement...");
    await _dbHelper.saveCustomerLocal(customerData);
    return customerData;
  }

  Future<Map<String, dynamic>?> updateCustomer(Map<String, dynamic> customerData) async {
    bool serverIsUp = await NetworkChecker.isBackendAccessible();

    if (serverIsUp) {
      try {
        final response = await http.post(
          Uri.parse("$baseUrl/customer/update"),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode(customerData),
        ).timeout(const Duration(seconds: 5));

        if (response.statusCode == 201 || response.statusCode == 200) {
          final updated = jsonDecode(response.body);
          await _dbHelper.saveCustomerLocal(updated);
          return updated;
        }
      } catch (e) {
        print("⚠️ Erreur réseau lors de la mise à jour, application en local : $e");
      }
    }

    // En cas d'échec ou serveur DOWN, on met à jour le local quand même
    print("💾 Mise à jour appliquée uniquement dans la base locale SQLite");
    await _dbHelper.saveCustomerLocal(customerData);
    return customerData;
  }

  // --- RÉCUPÉRER TOUS LES CLIENTS (HYBRIDE) ---
  Future<Map<String, dynamic>?> getAllCustomers({int page = 0, int size = 10}) async {
    bool serverIsUp = await NetworkChecker.isBackendAccessible();

    if (serverIsUp) {
      try {
        final Uri url = Uri.parse(apiUrl).replace(queryParameters: {
          'page': page.toString(),
          'size': size.toString(),
        });

        final response = await http.get(url).timeout(const Duration(seconds: 5));
        if (response.statusCode == 200) {
          return jsonDecode(response.body);
        }
      } catch (e) {
        print("Erreur chargement clients réseau : $e");
      }
    }

    // Si pas de réseau ou serveur arrêté, vous pouvez brancher votre méthode locale
    print("📥 Mode Offline : Récupération des clients depuis le cache local");
    // return await _dbHelper.getCustomersLocal(); // Décommentez si la méthode existe dans votre DatabaseHelper
    return null;
  }

  // --- RÉCUPÉRER UN CLIENT PAR ID (CHECK LOCAL D'ABORD) ---
  Future<Map<String, dynamic>?> getCustomerById(String id) async {
    // On regarde d'abord dans le téléphone (plus rapide, évite une requête réseau inutile)
    final localCustomer = await _dbHelper.getCustomerById(id);
    if (localCustomer != null) return localCustomer;

    // Si pas trouvé en local, on tente de le chercher sur le serveur si celui-ci est en ligne
    bool serverIsUp = await NetworkChecker.isBackendAccessible();
    if (serverIsUp) {
      try {
        final response = await http.get(Uri.parse("$apiUrl/$id")).timeout(const Duration(seconds: 5));
        if (response.statusCode == 200) {
          final customer = jsonDecode(response.body);
          await _dbHelper.saveCustomerLocal(customer);
          return customer;
        }
      } catch (e) {
        print("Erreur réseau client $id : $e");
      }
    }
    return null;
  }

  // --- SUPPRIMER UN CLIENT ---
  Future<bool> deleteCustomer(String id) async {
    try {
      // Supprimer du téléphone d'abord pour que l'interface utilisateur soit réactive immédiatement
      await _dbHelper.deleteCustomerLocal(id);

      bool serverIsUp = await NetworkChecker.isBackendAccessible();
      if (serverIsUp) {
        final response = await http.delete(Uri.parse("$apiUrl/$id")).timeout(const Duration(seconds: 5));
        return response.statusCode == 200;
      }

      // Si le serveur est hors-ligne, vous pouvez ajouter une tâche de suppression à votre file d'attente
      print("💾 Suppression locale effectuée. Serveur indisponible pour répercuter la suppression.");
      return true;
    } catch (e) {
      print("Erreur suppression client : $e");
      return false;
    }
  }


  Future<Map<String, dynamic>?> getCustomerByNumCust(String numCust) async {
    final localCustomer = await _dbHelper.getCustomerByNumCustLocal(numCust);
    if (localCustomer != null) {
      print("📥 Client trouvé en local (SQLite)");
      return localCustomer;
    }

    // 2. Si non trouvé en local, tenter le réseau si le serveur est accessible
    bool serverIsUp = await NetworkChecker.isBackendAccessible();
    if (serverIsUp) {
      try {
        final response = await http.get(
          Uri.parse("$apiUrl/number/$numCust"),
        ).timeout(const Duration(seconds: 5));

        if (response.statusCode == 200) {
          final customer = jsonDecode(response.body);
          // Sauvegarder en local pour les prochaines fois
          await _dbHelper.saveCustomerLocal(customer);
          return customer;
        }
      } catch (e) {
        print("⚠️ Erreur réseau recherche client par numéro $numCust : $e");
      }
    }
    return null;
  }
}