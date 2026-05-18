import 'package:flutter/material.dart';

class CartItem {
  final String id;
  final String name;
  final String imageUrl;
  final double price;
  int quantity;

  CartItem({
    required this.id,
    required this.name,
    required this.imageUrl,
    required this.price,
    this.quantity = 1,
  });
}

class CartProvider with ChangeNotifier {
  final Map<String, CartItem> _items = {};

  Map<String, CartItem> get items => {..._items};

  int get itemCount => _items.length;

  double get totalAmount {
    double total = 0.0;
    _items.forEach((key, item) {
      total += item.price * item.quantity;
    });
    return total;
  }

  void addItem(String productId, String name, double price, String imageUrl, int quantity) {
    if (_items.containsKey(productId)) {
      _items.update(
        productId,
            (existingItem) => CartItem(
          id: existingItem.id,
          name: existingItem.name,
          imageUrl: existingItem.imageUrl,
          price: existingItem.price,
          quantity: existingItem.quantity + quantity,
        ),
      );
    } else {
      _items.putIfAbsent(
        productId,
            () => CartItem(
          id: productId,
          name: name,
          imageUrl: imageUrl,
          price: price,
          quantity: quantity,
        ),
      );
    }
    notifyListeners();
  }

  // ✅ AJOUTEZ CETTE MÉTHODE ICI
  void removeSingleItem(String productId) {
    if (!_items.containsKey(productId)) {
      return;
    }
    if (_items[productId]!.quantity > 1) {
      // Si plus d'un article, on diminue la quantité
      _items.update(
        productId,
            (existingItem) => CartItem(
          id: existingItem.id,
          name: existingItem.name,
          imageUrl: existingItem.imageUrl,
          price: existingItem.price,
          quantity: existingItem.quantity - 1,
        ),
      );
    } else {
      // S'il n'en reste qu'un, on supprime carrément l'entrée
      _items.remove(productId);
    }
    notifyListeners();
  }

  void clearCart() {
    _items.clear();
    notifyListeners();
  }
}