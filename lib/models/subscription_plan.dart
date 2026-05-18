import 'package:flutter/material.dart';

class SubscriptionPlan {
  final int id;
  final String name;
  final String price;
  final String colorHex;
  final String iconKey;
  final String features;
  final int priorite; // <-- CHAMP AJOUTÉ

  SubscriptionPlan({
    required this.id,
    required this.name,
    required this.price,
    required this.colorHex,
    required this.iconKey,
    required this.features,
    required this.priorite,
  });

  factory SubscriptionPlan.fromJson(Map<String, dynamic> json) {
    return SubscriptionPlan(
      // Conversion sécurisée : on force en int même si le JSON envoie un String
      id: int.tryParse(json['id'].toString()) ?? 0,
      name: json['name'] ?? 'Plan',
      price: json['price'] ?? '0',
      colorHex: json['colorHex'] ?? '#FF9800',
      iconKey: json['iconKey'] ?? 'star',
      features: json['features'] ?? '',
      // Conversion sécurisée pour la priorité
      priorite: int.tryParse(json['priorite']?.toString() ?? '0') ?? 0,
    );
  }

  // Convertit la chaîne Hex de l'API en objet Color Flutter
  Color get color {
    try {
      return Color(int.parse(colorHex.replaceFirst('#', '0xff')));
    } catch (e) {
      return Colors.orange; // Couleur par défaut en cas d'erreur
    }
  }

  // Convertit la chaîne des fonctionnalités en List<String>
  List<String> get featuresList => features.split(',');

  // Mappe les clés de l'API vers les icônes Flutter
  IconData get icon => iconKey == "star_border" ? Icons.star_border :
  iconKey == "star_half" ? Icons.star_half :
  Icons.star;
}