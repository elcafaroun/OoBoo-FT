import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/cart_provider.dart';
import '../services/command_service.dart';
import '../models/command_request.dart';
import '../models/command_item_request.dart';

class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  Future<void> _processOrder(BuildContext context, CartProvider cart, String modePaiement, String phone, String name, bool isPaye) async {
    final CommandService commandService = CommandService();
    final prefs = await SharedPreferences.getInstance();
    final String savedId = prefs.getString('selected_structure_id') ?? "1";
    final String commandId = "CMD-${DateTime.now().millisecondsSinceEpoch}-$savedId";

    final commandRequest = CommandRequest(
      id: commandId,
      customerName: name,
      totalAmount: cart.totalAmount,
      paymentMethod: modePaiement,
      codeStructure: savedId,
      status: isPaye ? 'COMPLETED' : 'PENDING',
      items: cart.items.values.map((item) => CommandItemRequest(
          productId: item.id,
          productName: item.name,
          quantity: item.quantity.toInt(),
          unitPrice: item.price
      )).toList(),
    );

    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator(color: Colors.orange)));

    try {
      bool success = await commandService.createCommand(commandRequest);
      if (context.mounted) {
        Navigator.pop(context);
        if (success) {
          cart.clearCart();
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isPaye ? "Paiement réussi !" : "Commande enregistrée"), backgroundColor: Colors.green));
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (context.mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = Provider.of<CartProvider>(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(title: const Text("Panier", style: TextStyle(fontWeight: FontWeight.w800)), backgroundColor: Colors.white, elevation: 0),
      body: cart.items.isEmpty
          ? const Center(child: Text("Votre panier est vide"))
          : Column(children: [
        Expanded(child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: cart.items.length,
          itemBuilder: (ctx, i) {
            final item = cart.items.values.toList()[i];
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
              child: ListTile(
                title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text("${item.price} FCFA"),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                      icon: const Icon(Icons.remove_circle_outline, color: Colors.orange),
                      onPressed: () => cart.removeSingleItem(item.id)
                  ),
                  Text("${item.quantity.toInt()}", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  IconButton(
                      icon: const Icon(Icons.add_circle_outline, color: Colors.orange),
                      // Correction : Passage des 5 paramètres requis par votre Provider
                      onPressed: () => cart.addItem(item.id, item.name, item.price, item.imageUrl, 1)
                  ),
                ]),
              ),
            );
          },
        )),
        _buildSummary(context, cart),
      ]),
    );
  }

  Widget _buildSummary(BuildContext context, CartProvider cart) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Total à payer", style: TextStyle(fontSize: 16)), Text("${cart.totalAmount} FCFA", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900))]),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(child: OutlinedButton(onPressed: () => showDialog(context: context, builder: (_) => CustomerDialog(onValidated: (p, n) => _processOrder(context, cart, "PENDING", p, n, false))), child: const Text("COMMANDER"))),
          const SizedBox(width: 12),
          Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.orange), onPressed: () => _afficherChoixPaiement(context, cart), child: const Text("PAYER", style: TextStyle(color: Colors.white)))),
        ]),
      ]),
    );
  }

  void _afficherChoixPaiement(BuildContext context, CartProvider cart) {
    final modes = [
      {"name": "Orange Money", "icon": Icons.phone_android, "color": Colors.orange},
      {"name": "Wave", "icon": Icons.payment, "color": Colors.blue},
      {"name": "Moov Money", "icon": Icons.sim_card, "color": Colors.green},
      {"name": "SANK", "icon": Icons.account_balance_wallet, "color": Colors.purple},
      {"name": "Espèces", "icon": Icons.money, "color": Colors.teal},
    ];

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text("Mode de paiement", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          ...modes.map((m) => ListTile(
            leading: Icon(m["icon"] as IconData, color: m["color"] as Color),
            title: Text(m["name"] as String),
            onTap: () {
              Navigator.pop(ctx);
              showDialog(context: context, builder: (_) => CustomerDialog(onValidated: (p, n) => _processOrder(context, cart, m["name"] as String, p, n, true)));
            },
          )),
        ]),
      ),
    );
  }
}

class CustomerDialog extends StatefulWidget {
  final Function(String phone, String name) onValidated;
  const CustomerDialog({super.key, required this.onValidated});
  @override
  State<CustomerDialog> createState() => _CustomerDialogState();
}

class _CustomerDialogState extends State<CustomerDialog> {
  final _phoneController = TextEditingController();
  final _nameController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircleAvatar(radius: 30, backgroundColor: Color(0xFFFFF3E0), child: Icon(Icons.person, size: 40, color: Colors.orange)),
          const SizedBox(height: 15),
          const Text("Informations", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          TextField(controller: _phoneController, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: "Téléphone", border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), prefixIcon: const Icon(Icons.phone))),
          const SizedBox(height: 15),
          TextField(controller: _nameController, decoration: InputDecoration(labelText: "Nom complet", border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), prefixIcon: const Icon(Icons.person))),
          const SizedBox(height: 25),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: () {
                if(_phoneController.text.isNotEmpty && _nameController.text.isNotEmpty) {
                  Navigator.pop(context);
                  widget.onValidated(_phoneController.text, _nameController.text);
                }
              },
              child: const Text("VALIDER", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          )
        ]),
      ),
    );
  }
}