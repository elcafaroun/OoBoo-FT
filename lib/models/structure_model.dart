class StructureModel {
  final String idStructure;
  final String nomStructure;
  final String? planStructure;
  final DateTime? endSub;
  final bool isActive;
  final int priorite;

  // 🔹 Flags du Plan (Snapshot)
  final bool smsAlerte;
  final bool stockAlerte;
  final bool emailAlerte;
  final bool dashboard;
  final bool miniDashboard; // 👈 NOUVEAU
  final bool iaActive;
  final bool dashboardWeb; // 👈 NOUVEAU
  final bool userManagement;  // 👈 NOUVEAU
  final bool loyaltyAccess;
  final int nombreUsers;
  final int nombreCategorieParBusiness;
  final int nombreProdParBusiness;

  StructureModel({
    required this.idStructure,
    required this.nomStructure,
    this.planStructure,
    this.endSub,
    required this.isActive,
    required this.priorite,
    required this.smsAlerte,
    required this.stockAlerte,
    required this.emailAlerte,
    required this.dashboard,
    required this.miniDashboard,
    required this.iaActive,
    required this.loyaltyAccess,
    required this.nombreUsers,
    required this.nombreCategorieParBusiness,
    required this.nombreProdParBusiness,
    required this.dashboardWeb,
    required this.userManagement
  });

  factory StructureModel.fromJson(Map<String, dynamic> json) {
    return StructureModel(
      idStructure: json['idStructure'] ?? json['id'] ?? '',
      nomStructure: json['nomStructure'] ?? '',
      planStructure: json['planStructure'],
      endSub: json['endSub'] != null ? DateTime.tryParse(json['endSub'].toString()) : null,
      isActive: json['active'] ?? json['isActive'] ?? true,
      priorite: int.tryParse(json['priorite']?.toString() ?? '0') ?? 0,

      // Extraction explicite
      smsAlerte: json['smsAlerte'] == true,
      stockAlerte: json['stockAlerte'] == true,
      emailAlerte: json['emailAlerte'] == true,
      dashboard: json['dashboard'] == true,
      miniDashboard: json['miniDashboard'] == true, // 👈 NOUVEAU
      iaActive: json['iaActive'] == true,           // 👈 NOUVEAU
      loyaltyAccess: json['loyaltyAccess'] == true,
      dashboardWeb: json['dashboardWeb']==true,
      userManagement: json['userManagement']==true,

      nombreUsers: int.tryParse(json['nombreUsers']?.toString() ?? '1') ?? 1,
      nombreCategorieParBusiness: int.tryParse(json['nombreCategorieParBusiness']?.toString() ?? '0') ?? 0,
      nombreProdParBusiness: int.tryParse(json['nombreProdParBusiness']?.toString() ?? '0') ?? 0,
    );
  }

  bool get isSubscriptionValid {
    if (!isActive) return false;
    if (endSub == null) return true;
    return DateTime.now().isBefore(endSub!);
  }
}