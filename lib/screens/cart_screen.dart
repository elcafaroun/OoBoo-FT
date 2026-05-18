import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../providers/cart_provider.dart';
import '../services/command_service.dart';
import '../services/customer_service.dart';
import '../services/receipt_service.dart';
import '../models/command_request.dart';
import '../models/command_item_request.dart';

class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  // --- GÉNÉRATION DU PDF (Uniquement pour PAYER) ---
  Future<void> _genererEtPartagerPDF(CartProvider cart, String customerName, String phone) async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a6,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(child: pw.Text("REÇU OoBou", style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold))),
              pw.Divider(),
              pw.Text("Client: $customerName", style: pw.TextStyle(fontSize: 10)),
              pw.Text("Tél: $phone", style: pw.TextStyle(fontSize: 10)),
              pw.SizedBox(height: 10),
              pw.Table.fromTextArray(
                headers: ['Art.', 'Qté', 'Total'],
                data: cart.items.values.map((item) => [
                  item.name,
                  item.quantity.toInt().toString(),
                  "${(item.price * item.quantity).toStringAsFixed(0)}"
                ]).toList(),
              ),
              pw.Divider(),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text("TOTAL: ${cart.totalAmount.toStringAsFixed(0)} FCFA",
                    style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );

    try {
      final output = await getTemporaryDirectory();
      final file = File("${output.path}/facture_$phone.pdf");
      await file.writeAsBytes(await pdf.save());
      await Share.shareXFiles([XFile(file.path)], text: 'Votre facture numérique');
    } catch (e) {
      debugPrint("Erreur PDF : $e");
    }
  }

  // --- TRAITEMENT DE LA COMMANDE ---
  Future<void> _processOrder(BuildContext context, CartProvider cart, String modePaiement, String customerPhone, String customerName, bool isPaye) async {
    final CommandService commandService = CommandService();
    final prefs = await SharedPreferences.getInstance();
    final String savedId = prefs.getString('selected_structure_id') ?? "1";
    final String commandId = "CMD-${DateTime.now().millisecondsSinceEpoch}-$savedId";

    final commandRequest = CommandRequest(
      id: commandId,
      customerName: customerName,
      totalAmount: cart.totalAmount,
      paymentMethod: modePaiement,
      codeStructure: savedId,
      status: isPaye ? 'COMPLETED' : 'PENDING', // Statut différencié
      items: cart.items.values.map((item) => CommandItemRequest(
        productId: item.id,
        productName: item.name,
        quantity: item.quantity.toInt(),
        unitPrice: item.price,
      )).toList(),
    );

    // Affichage du loader
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator(color: Colors.orange)),
    );

    try {
      bool success = await commandService.createCommand(commandRequest);

      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop(); // Fermer loader

        if (success) {
          // Si c'est un paiement, on gère les documents. Si c'est une commande simple, on vide juste.
          if (isPaye) {
            await _finaliserPaiement(context, cart, modePaiement, customerPhone, customerName);
          } else {
            _finaliserCommandeSimple(context, cart);
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Erreur d'enregistrement"), backgroundColor: Colors.red));
        }
      }
    } catch (e) {
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      debugPrint("Erreur: $e");
    }
  }

  // Flux pour le bouton COMMANDER
  void _finaliserCommandeSimple(BuildContext context, CartProvider cart) {
    cart.clearCart();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text("Votre commande est enregistrée avec succès !"),
      backgroundColor: Colors.green,
      duration: Duration(seconds: 3),
    ));
    Navigator.pop(context); // Retour à l'accueil
  }

  // Flux pour le bouton PAYER
  Future<void> _finaliserPaiement(BuildContext context, CartProvider cart, String mode, String phone, String name) async {
    var connectivityResult = await (Connectivity().checkConnectivity());
    bool hasInternet = !connectivityResult.contains(ConnectivityResult.none);

    try {
      await _genererEtPartagerPDF(cart, name, phone);
      if (hasInternet) await _envoyerCommandeWhatsApp(cart, mode, phone);
      await ReceiptService().generateAndPrintReceipt(cart: cart, customerPhone: phone, customerName: name, paymentMethod: mode);
    } catch (e) {
      debugPrint("Erreur documents : $e");
    }

    cart.clearCart();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Vente encaissée avec succès !"), backgroundColor: Colors.green));
      Navigator.pop(context);
    }
  }

  Future<void> _envoyerCommandeWhatsApp(CartProvider cart, String mode, String phone) async {
    String formattedPhone = phone.trim().replaceAll(' ', '');
    if (!formattedPhone.startsWith('226') && formattedPhone.length == 8) formattedPhone = '226$formattedPhone';
    String message = "✨ *REÇU OoBou* ✨\n💰 *Total : ${cart.totalAmount.toStringAsFixed(0)} FCFA*";
    final Uri uri = Uri.parse("https://wa.me/$formattedPhone?text=${Uri.encodeComponent(message)}");
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final cart = Provider.of<CartProvider>(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF9F7F2),
      appBar: AppBar(title: const Text("Mon Panier"), centerTitle: true, elevation: 0),
      body: cart.items.isEmpty
          ? const Center(child: Text("Le panier est vide"))
          : Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: cart.items.length,
              itemBuilder: (ctx, i) {
                final item = cart.items.values.toList()[i];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ListTile(
                    title: Text(item.name),
                    subtitle: Text("${(item.price * item.quantity).toStringAsFixed(0)} FCFA"),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: () => cart.removeSingleItem(item.id)),
                        Text("${item.quantity.toInt()}"),
                        IconButton(icon: const Icon(Icons.add_circle_outline, color: Colors.orange), onPressed: () => cart.addItem(item.id, item.name, item.price, item.imageUrl, 1)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          _buildSummary(context, cart),
        ],
      ),
    );
  }

  Widget _buildSummary(BuildContext context, CartProvider cart) {
    return Container(
      padding: const EdgeInsets.all(20),
      color: Colors.white,
      child: Column(
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text("Total à payer"),
            Text("${cart.totalAmount.toStringAsFixed(0)} FCFA", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.orange)),
          ]),
          const SizedBox(height: 20),
          Row(
            children: [
              // BOUTON COMMANDER : Action directe
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.orange),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () {
                    // Pas de dialogue client, pas de choix de paiement
                    _processOrder(context, cart, "COMMANDE SIMPLE", "00000000", "CLIENT PASSAGE", false);
                  },
                  child: const Text("COMMANDER", style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 12),
              // BOUTON PAYER : Flow avec choix paiement + client
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => _afficherChoixPaiement(context, cart),
                  child: const Text("PAYER", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  void _afficherChoixPaiement(BuildContext context, CartProvider cart) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 15),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Choisir le mode de paiement", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const Divider(),
            _tilePaiement(context, cart, "Orange Money", Icons.phonelink_ring, Colors.orange),
            _tilePaiement(context, cart, "Moov Money", Icons.phonelink_ring, Colors.blue),
            _tilePaiement(context, cart, "Telecel Money", Icons.phonelink_ring, Colors.red),
            _tilePaiement(context, cart, "Espèces", Icons.money, Colors.green),
            _tilePaiement(context, cart, "Achat à crédit", Icons.history, Colors.brown),
          ],
        ),
      ),
    );
  }

  Widget _tilePaiement(BuildContext context, CartProvider cart, String mode, IconData icon, Color color) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(mode),
      onTap: () {
        Navigator.pop(context);
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => CustomerDialog(
            onValidated: (phone, name) => _processOrder(context, cart, mode, phone, name, true),
          ),
        );
      },
    );
  }
}

// --- DIALOGUE CLIENT (Utilisé uniquement pour PAYER) ---
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
    return AlertDialog(
      title: const Text("Informations Client"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(controller: _phoneController, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: "Téléphone")),
          const SizedBox(height: 10),
          TextField(controller: _nameController, decoration: const InputDecoration(labelText: "Nom complet")),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Annuler")),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
          onPressed: () {
            Navigator.pop(context);
            widget.onValidated(_phoneController.text, _nameController.text);
          },
          child: const Text("Valider", style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}