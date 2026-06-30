import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:http/http.dart' as http;

class FileStorageHelper {
  // Récupère le dossier où stocker les images
  static Future<Directory> _getImagesDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final imagesDir = Directory(path.join(appDir.path, 'product_images'));
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }
    return imagesDir;
  }

  // Télécharge et enregistre l'image avec l'ID du produit
  static Future<String?> saveImageLocally(String imageUrl, String productId) async {
    try {
      final response = await http.get(Uri.parse(imageUrl));
      if (response.statusCode == 200) {
        final dir = await _getImagesDir();
        final file = File(path.join(dir.path, '$productId.jpg'));
        await file.writeAsBytes(response.bodyBytes);
        return file.path;
      }
    } catch (e) {
      print("Erreur lors de la sauvegarde de l'image : $e");
    }
    return null;
  }
}