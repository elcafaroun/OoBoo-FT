import 'package:flutter/material.dart';

class CartItem {
  final String id;
  final String name;
  final String imageUrl;
  final double price;
  final int quantity; // ✅ 'quantity' passé en final pour l'immutabilité

  CartItem({
    required this.id,
    required this.name,
    required this.imageUrl,
    required this.price,
    required this.quantity,
  });
}

class CartProvider with ChangeNotifier {
  final Map<String, CartItem> _items = {};

  // ✅ Retourne une copie de la Map pour éviter les modifications externes imprévues
  Map<String, CartItem> get items => Map.from(_items);

  int get itemCount => _items.length;

  double get totalAmount {
    return _items.values.fold(0.0, (sum, item) => sum + (item.price * item.quantity));
  }

  void addItem(String productId, String name, double price, String imageUrl, int quantity) {
    if (_items.containsKey(productId)) {
      _items.update(
        productId,
            (existing) => CartItem(
          id: existing.id,
          name: existing.name,
          imageUrl: existing.imageUrl,
          price: existing.price,
          quantity: existing.quantity + quantity,
        ),
      );
    } else {
      _items[productId] = CartItem(
        id: productId,
        name: name,
        imageUrl: imageUrl,
        price: price,
        quantity: quantity,
      );
    }
    notifyListeners();
  }

  void removeSingleItem(String productId) {
    if (!_items.containsKey(productId)) return;

    if (_items[productId]!.quantity > 1) {
      _items.update(
        productId,
            (existing) => CartItem(
          id: existing.id,
          name: existing.name,
          imageUrl: existing.imageUrl,
          price: existing.price,
          quantity: existing.quantity - 1,
        ),
      );
    } else {
      _items.remove(productId);
    }
    notifyListeners();
  }

  void clearCart() {
    _items.clear();
    notifyListeners();
  }
}