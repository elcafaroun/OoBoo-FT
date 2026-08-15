class CommandItemRequest {
  final String productId;
  final String productName;
  final int quantity;
  final double unitPrice;

  CommandItemRequest({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
  });

  Map<String, dynamic> toJson() {
    return {
      'productId': productId,
      'productName': productName,
      'quantity': quantity,
      'unitPrice': unitPrice,
    };
  }

  factory CommandItemRequest.fromJson(Map<String, dynamic> json) {
    return CommandItemRequest(
      productId: json['productId'] as String? ?? '',
      productName: json['productName'] as String? ?? '',
      quantity: json['quantity'] as int? ?? 0,
      unitPrice: (json['unitPrice'] as num?)?.toDouble() ?? 0.0,
    );
  }
}