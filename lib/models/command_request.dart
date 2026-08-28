import 'command_item_request.dart';

class CommandRequest {
  final String id;
  final String customerName;
  final String? customerNum;
  final double totalAmount;
  final String paymentMethod;
  final String codeStructure;
  final String status;
  final String userId;      // ID de l'agent qui a fait la vente
  final String userName;    // Nom de l'agent qui a fait la vente
  final List<CommandItemRequest> items;

  CommandRequest({
    required this.id,
    required this.customerName,
    required this.customerNum,
    required this.totalAmount,
    required this.paymentMethod,
    required this.codeStructure,
    required this.status,
    required this.userId,
    required this.userName,
    required this.items,
  });

  /// Convertit l'objet Dart en Map (JSON) pour l'envoyer au serveur Java Spring Boot
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'customerName': customerName,
      'customerNum': customerNum,
      'totalAmount': totalAmount,
      'paymentMethod': paymentMethod,
      'codeStructure': codeStructure,
      'status': status,
      'userId': userId,
      'userName': userName,
      'items': items.map((item) => item.toJson()).toList(),
    };
  }

  /// Permet de reconstruire l'objet à partir d'un JSON (utile pour la base de données SQLite ou l'API)
  factory CommandRequest.fromJson(Map<String, dynamic> json) {
    return CommandRequest(
      id: json['id'] as String,
      customerName: json['customerName'] as String? ?? '',
      customerNum: json['customerNum'],
      totalAmount: (json['totalAmount'] as num?)?.toDouble() ?? 0.0,
      paymentMethod: json['paymentMethod'] as String? ?? 'CASH',
      codeStructure: json['codeStructure'] as String? ?? '',
      status: json['status'] as String? ?? 'PENDING',
      userId: json['userId'] as String? ?? 'agent_inconnu',
      userName: json['userName'] as String? ?? 'Agent',
      items: (json['items'] as List<dynamic>?)
          ?.map((item) => CommandItemRequest.fromJson(item as Map<String, dynamic>))
          .toList() ??
          [],
    );
  }
}