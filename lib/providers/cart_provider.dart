import 'package:flutter/material.dart';

class CartItem {
  final String id;
  final String name;
  final String imageUrl;
  final double price;
  final int quantity;

  CartItem({
    required this.id,
    required this.name,
    required this.imageUrl,
    required this.price,
    required this.quantity,
  });
}

class CartProvider with ChangeNotifier {
  // Clé principale = structureId, Clé secondaire = productId
  final Map<String, Map<String, CartItem>> _structuresCarts = {};

  String _currentStructureId = "1";

  void setStructure(String structureId) {
    if (_currentStructureId != structureId) {
      _currentStructureId = structureId;
      notifyListeners();
    }
  }

  Map<String, CartItem> get items {
    return Map.from(_structuresCarts[_currentStructureId] ?? {});
  }

  // ✅ Correction : Compte la quantité totale de tous les articles dans le panier
  int get itemCount {
    return items.values.fold(0, (sum, item) => sum + item.quantity);
  }

  // ✅ Correction alternative si tu voulais le nombre de lignes distinctes, garde _items.length.
  // Mais pour un badge de panier, on additionne généralement les quantités.

  double get totalAmount {
    return items.values.fold(0.0, (sum, item) => sum + (item.price * item.quantity));
  }

  void addItem(String productId, String name, double price, String imageUrl, int quantity) {
    final cart = _structuresCarts.putIfAbsent(_currentStructureId, () => {});

    if (cart.containsKey(productId)) {
      cart.update(
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
      cart[productId] = CartItem(
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
    final cart = _structuresCarts[_currentStructureId];
    if (cart == null || !cart.containsKey(productId)) return;

    if (cart[productId]!.quantity > 1) {
      cart.update(
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
      cart.remove(productId);
    }
    notifyListeners();
  }

  void clearCart() {
    _structuresCarts[_currentStructureId]?.clear();
    notifyListeners();
  }
}