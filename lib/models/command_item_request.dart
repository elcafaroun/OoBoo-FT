class CommandItemRequest {
  final String productId;
  final String productName;
  final int quantity;
  final double unitPrice;

  CommandItemRequest({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPrice
  });

  Map<String, dynamic> toJson() => {
    'productId': productId,
    'productName': productName,
    'quantity': quantity,
    'unitPrice': unitPrice,
  };
}