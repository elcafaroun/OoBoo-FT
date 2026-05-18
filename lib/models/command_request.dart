import 'package:fada/models/command_item_request.dart';

class CommandRequest {
  final String id;
  final List<CommandItemRequest> items;
  final String paymentMethod;
  final double totalAmount;
  final String codeStructure;
  final String customerName;
  final String status; // <--- Ce champ doit être présent

  CommandRequest({
    required this.id,
    required this.items,
    required this.paymentMethod,
    required this.totalAmount,
    required this.codeStructure,
    required this.customerName,
    required this.status, // <--- Requis ici
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'items': items.map((i) => i.toJson()).toList(),
    'paymentMethod': paymentMethod,
    'totalAmount': totalAmount,
    'codeStructure': codeStructure,
    'customerName': customerName,
    'status': status, // <--- Et envoyé ici au backend
  };
}