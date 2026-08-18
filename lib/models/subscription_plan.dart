import 'package:flutter/material.dart';

class SubscriptionPlan {
  final int? id;
  final String name;
  final String price;
  final String? colorHex;
  final String? iconKey;
  final int? priorite;
  final String? features;

  // --- NOUVEAUX CHAMPS METIER ---
  final bool? smsAlerte;
  final bool? stockAlerte;
  final int? nombreBusiness;
  final double? cout;
  final int? gracePeriode;
  final int? nombreJourSouscription;
  final bool? dashboard;
  final bool? emailAlerte;
  final bool? loyaltyAccess;
  final bool? isActive;
  final int? nombreCategorieParBusiness;
  final int? nombreProdParBusiness;

  SubscriptionPlan({
    this.id,
    required this.name,
    required this.price,
    this.colorHex,
    this.iconKey,
    this.priorite,
    this.features,
    this.smsAlerte,
    this.stockAlerte,
    this.nombreBusiness,
    this.cout,
    this.gracePeriode,
    this.nombreJourSouscription,
    this.dashboard,
    this.emailAlerte,
    this.loyaltyAccess,
    this.isActive,
    this.nombreCategorieParBusiness,
    this.nombreProdParBusiness,
  });

  /// Factory pour deserialiser le JSON renvoyé par Spring Boot
  factory SubscriptionPlan.fromJson(Map<String, dynamic> json) {
    return SubscriptionPlan(
      id: json['id'],
      name: json['name'] ?? '',
      price: json['price'] ?? '',
      colorHex: json['colorHex'],
      iconKey: json['iconKey'],
      priorite: json['priorite'],
      features: json['features'],
      smsAlerte: json['smsAlerte'],
      stockAlerte: json['stockAlerte'],
      nombreBusiness: json['nombreBusiness'],
      cout: json['cout'] != null ? (json['cout'] as num).toDouble() : null,
      gracePeriode: json['gracePeriode'],
      nombreJourSouscription: json['nombreJourSouscription'],
      dashboard: json['dashboard'],
      emailAlerte: json['emailAlerte'],
      loyaltyAccess: json['loyaltyAccess'],
      isActive: json['isActive'],
      nombreCategorieParBusiness: json['nombreCategorieParBusiness'],
      nombreProdParBusiness: json['nombreProdParBusiness'],
    );
  }

  /// Convertir en JSON si besoin
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'price': price,
      'colorHex': colorHex,
      'iconKey': iconKey,
      'priorite': priorite,
      'features': features,
      'smsAlerte': smsAlerte,
      'stockAlerte': stockAlerte,
      'nombreBusiness': nombreBusiness,
      'cout': cout,
      'gracePeriode': gracePeriode,
      'nombreJourSouscription': nombreJourSouscription,
      'dashboard': dashboard,
      'emailAlerte': emailAlerte,
      'loyaltyAccess': loyaltyAccess,
      'isActive': isActive,
      'nombreCategorieParBusiness': nombreCategorieParBusiness,
      'nombreProdParBusiness': nombreProdParBusiness,
    };
  }

  /// Getters utilitaires pour l'affichage (Couleur & Icone)
  Color? get color {
    if (colorHex == null || colorHex!.isEmpty) return null;
    try {
      final hex = colorHex!.replaceAll('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return null;
    }
  }

  IconData? get icon {
    switch (iconKey) {
      case 'star':
        return Icons.star;
      case 'workspace_premium':
        return Icons.workspace_premium;
      case 'bolt':
        return Icons.flash_on;
      default:
        return Icons.card_membership;
    }
  }
}