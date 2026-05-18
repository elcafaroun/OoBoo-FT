import 'package:flutter/material.dart';
import 'package:provider/provider.dart'; // ✅ Nécessaire pour le panier
import '../providers/cart_provider.dart'; // ✅ Votre modèle de gestion du panier

class ProductDetailScreen extends StatefulWidget {
  final Map<String, dynamic> product;

  const ProductDetailScreen({super.key, required this.product});

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  int _quantity = 1; // Quantité sélectionnée localement

  @override
  Widget build(BuildContext context) {
    // 🛒 Accès au panier (listen: false car on veut juste déclencher une action)
    final cart = Provider.of<CartProvider>(context, listen: false);

    final p = widget.product;

    // Gestion de l'URL pour l'émulateur
    final imageUrl = (p['productPhotoUrl'] ?? '').toString().replaceAll('http://localhost:8080', 'http://10.0.2.2:8080');
    final nom = (p['productName'] ?? 'Produit inconnu').toString();
    final desc = (p['descriptionProduit'] ?? 'Aucune description disponible.').toString();
    final prix = (p['productPrice'] ?? 0);

    return Scaffold(
      backgroundColor: Colors.white,
      body: CustomScrollView(
        slivers: [
          // 🖼️ Image avec effet de réduction (SliverAppBar)
          SliverAppBar(
            expandedHeight: 350,
            pinned: true,
            backgroundColor: const Color(0xFFFF9800),
            iconTheme: const IconThemeData(color: Colors.white),
            flexibleSpace: FlexibleSpaceBar(
              background: Hero(
                tag: 'prod_${p['id']}',
                child: imageUrl.isNotEmpty
                    ? Image.network(imageUrl, fit: BoxFit.cover)
                    : Container(
                    color: Colors.orange[100],
                    child: const Icon(Icons.image, size: 100, color: Colors.orange)
                ),
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- Titre et Prix ---
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                            nom,
                            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)
                        ),
                      ),
                      Text(
                          "$prix FCFA",
                          style: const TextStyle(
                              fontSize: 22,
                              color: Color(0xFFFF9800),
                              fontWeight: FontWeight.w900
                          )
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // --- Description ---
                  const Text(
                      "Description",
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)
                  ),
                  const SizedBox(height: 10),
                  Text(
                      desc,
                      style: TextStyle(fontSize: 16, color: Colors.grey[800], height: 1.5)
                  ),

                  const SizedBox(height: 30),

                  // --- Sélecteur de Quantité ---
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Row(
                      children: [
                        const Text(
                            "Quantité",
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)
                        ),
                        const Spacer(),
                        _quantityButton(Icons.remove, () {
                          if (_quantity > 1) setState(() => _quantity--);
                        }),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Text(
                              "$_quantity",
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)
                          ),
                        ),
                        _quantityButton(Icons.add, () => setState(() => _quantity++)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 120), // Espace pour ne pas cacher le contenu sous le bouton
                ],
              ),
            ),
          ),
        ],
      ),

      // 🛒 Barre fixe en bas pour l'ajout au panier
      bottomSheet: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(color: Colors.black12, blurRadius: 10, offset: const Offset(0, -2))
          ],
        ),
        child: SafeArea(
          child: SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton.icon(
              onPressed: () {
                // ✅ ACTION RÉELLE DU PANIER
                cart.addItem(
                  p['id'].toString(),
                  nom,
                  double.parse(prix.toString()),
                  imageUrl,
                  _quantity,
                );

                // Message de confirmation
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text("✅ $_quantity $nom ajouté(s) au panier"),
                    backgroundColor: Colors.green,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              icon: const Icon(Icons.add_shopping_cart, color: Colors.white),
              label: const Text(
                  "AJOUTER AU PANIER",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF9800),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Petit widget pour les boutons +/-
  Widget _quantityButton(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Icon(icon, color: const Color(0xFFFF9800)),
      ),
    );
  }
}