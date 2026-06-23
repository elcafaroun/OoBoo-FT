class UserStructure {
  final String id;
  final String? userId;      // Doit être nullable
  final String? structureId; // Doit être nullable
  final String roleInStructure;

  UserStructure({required this.id, this.userId, this.structureId, required this.roleInStructure});

  // C'EST ICI QUE LE LIEN SE FAIT
  factory UserStructure.fromJson(Map<String, dynamic> json) {
    return UserStructure(
      id: json['id'],
      userId: json['userId'],          // <--- Vérifiez que cette clé est bien présente
      structureId: json['structureId'],// <--- Vérifiez que cette clé est bien présente
      roleInStructure: json['roleInStructure'] ?? 'COLLABORATEUR',
    );
  }
}