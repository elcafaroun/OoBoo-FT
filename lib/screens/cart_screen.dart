import 'dart:convert';


import 'dart:io';

import 'package:fada/services/customer_service.dart';
import 'package:fada/services/database/database_helper.dart';
import 'package:fada/services/network_checker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import '../providers/cart_provider.dart';
import '../services/command_service.dart';
import '../models/command_request.dart';
import '../models/command_item_request.dart';

class CartScreen extends StatefulWidget {
  final String? userId;
  final String? userName;
  final String? structureId;

  const CartScreen({
    super.key,
    this.userId,
    this.userName,
    this.structureId,
  });

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  String _currentStructureId = "1";
  String _currentUserId = "agent_inconnu";
  String _currentUserName = "Agent";
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadContextData();
  }

  Future<void> _loadContextData() async {
    final prefs = await SharedPreferences.getInstance();

    final structureId = widget.structureId ?? prefs.getString('selected_structure_id') ?? "1";
    final userId = widget.userId ?? prefs.getString('userId') ?? "agent_inconnu";
    final userName = widget.userName ?? prefs.getString('userName') ?? "Agent";

    if (mounted) {
      Provider.of<CartProvider>(context, listen: false).setStructure(structureId);
    }

    setState(() {
      _currentStructureId = structureId;
      _currentUserId = userId;
      _currentUserName = userName;
      _isLoading = false;
    });
  }

  Future<void> _processOrder(BuildContext context, CartProvider cart, String modePaiement, String phone, String name, bool isPaye) async {
    final CommandService commandService = CommandService();
    final String commandId = "CMD-${DateTime.now().millisecondsSinceEpoch}-$_currentStructureId";

    final commandRequest = CommandRequest(
      id: commandId,
      customerName: name,
      totalAmount: cart.totalAmount,
      paymentMethod: modePaiement,
      codeStructure: _currentStructureId,
      status: isPaye ? 'COMPLETED' : 'PENDING',
      userId: _currentUserId,
      userName: _currentUserName,
      items: cart.items.values.map((item) => CommandItemRequest(
          productId: item.id,
          productName: item.name,
          quantity: item.quantity.toInt(),
          unitPrice: item.price
      )).toList(),
    );

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: Colors.orange)),
    );

    try {
      bool success = await commandService.createCommand(commandRequest);
      if (context.mounted) {
        Navigator.pop(context); // Fermer le loader
        if (success) {
          cart.clearCart();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(isPaye ? "Paiement réussi !" : "Commande enregistrée"),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context); // Quitter le panier
        }
      }
    } catch (e) {
      if (context.mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF8F9FA),
        body: Center(child: CircularProgressIndicator(color: Colors.orange)),
      );
    }

    final cart = Provider.of<CartProvider>(context);
    cart.setStructure(_currentStructureId);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text("Panier", style: TextStyle(fontWeight: FontWeight.w800)),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: cart.items.isEmpty
          ? const Center(child: Text("Votre panier est vide", style: TextStyle(fontSize: 16, color: Colors.grey)))
          : Column(
        children: [
          Expanded(
            child: ListView.builder(
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
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline, color: Colors.orange),
                          onPressed: () => cart.removeSingleItem(item.id),
                        ),
                        Text("${item.quantity.toInt()}", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline, color: Colors.orange),
                          onPressed: () => cart.addItem(item.id, item.name, item.price, item.imageUrl, 1),
                        ),
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
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Total à payer", style: TextStyle(fontSize: 16)),
              Text("${cart.totalAmount} FCFA", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) => CustomerDialog(
                      onValidated: (p, n) => _processOrder(context, cart, "PENDING", p, n, false),
                    ),
                  ),
                  child: const Text("COMMANDER"),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                  onPressed: () => _afficherChoixPaiement(context, cart),
                  child: const Text("PAYER", style: TextStyle(color: Colors.white)),
                ),
              ),
            ],
          ),
        ],
      ),
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Mode de paiement", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            ...modes.map((m) => ListTile(
              leading: Icon(m["icon"] as IconData, color: m["color"] as Color),
              title: Text(m["name"] as String),
              onTap: () {
                Navigator.pop(ctx);
                showDialog(
                  context: context,
                  builder: (_) => CustomerDialog(
                    onValidated: (p, n) => _processOrder(context, cart, m["name"] as String, p, n, true),
                  ),
                );
              },
            )),
          ],
        ),
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
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final FocusNode _phoneFocusNode = FocusNode();

  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _phoneFocusNode.addListener(_onPhoneFocusChange);
  }

  @override
  void dispose() {
    _phoneFocusNode.removeListener(_onPhoneFocusChange);
    _phoneFocusNode.dispose();
    _phoneController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _onPhoneFocusChange() {
    if (!_phoneFocusNode.hasFocus) {
      _searchCustomerOffline(_phoneController.text);
    }
  }

  Future<void> _searchCustomerOffline(String phone) async {
    final cleanPhone = phone.trim();
    if (cleanPhone.length < 8) return;

    setState(() => _isSearching = true);

    try {
      final db = await _dbHelper.database;
      final List<Map<String, dynamic>> results = await db.query(
        'customers',
        where: 'numCust = ?',
        whereArgs: [cleanPhone],
        limit: 1,
      );

      if (results.isNotEmpty) {
        final customerName = results.first['customerName'] ?? '';
        setState(() {
          _nameController.text = customerName;
        });
        debugPrint("👤 [OFFLINE] Client trouvé : $customerName");
      }
    } catch (e) {
      debugPrint("⚠️ Erreur recherche locale du client : $e");
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _saveOrUpdateCustomer(String phone, String name) async {
    final CustomerService customerService = CustomerService();
    final db = await _dbHelper.database;

    final prefs = await SharedPreferences.getInstance();
    final String codeStructure = prefs.getString('selected_structure_id') ??
        prefs.getString('codeStructure') ?? '';

    final existing = await db.query(
      'customers',
      where: 'numCust = ?',
      whereArgs: [phone],
      limit: 1,
    );

    String customerId;
    int currentVersion = 1;

    if (existing.isNotEmpty) {
      customerId = existing.first['id'] as String;
      currentVersion = ((existing.first['version'] as int?) ?? 0) + 1;
    } else {
      customerId = "CUST-${DateTime.now().millisecondsSinceEpoch}";
    }

    final customerPayload = {
      'id': customerId,
      'numCust': phone,
      'codePin': null,
      'customerName': name,
      'codeStructure': codeStructure,
      'createdDate': existing.isNotEmpty
          ? (existing.first['createdDate'] ?? DateTime.now().toIso8601String())
          : DateTime.now().toIso8601String(),
      'version': currentVersion,
    };

    try {
      if (existing.isNotEmpty) {
        await customerService.updateCustomer(customerPayload);
        debugPrint("🔄 Tentative de mise à jour du client effectuée via CustomerService.");
      } else {
        await customerService.createCustomer(customerPayload);
        debugPrint("✨ Tentative de création du client effectuée via CustomerService.");
      }
    } catch (e) {
      debugPrint("⚠️ Erreur lors de l'appel au CustomerService (Mode Hors-ligne) : $e");

      await _dbHelper.saveCustomerLocal(customerPayload);
      await _addToSyncQueue(db, customerId, customerPayload, existing.isNotEmpty);
    }
  }

  Future<void> _addToSyncQueue(Database db, String customerId, Map<String, dynamic> payload, bool isUpdate) async {
    final String actionType = isUpdate ? 'UPDATE' : 'INSERT';

    final existingQueue = await db.query(
      'sync_queue',
      where: 'entityId = ? AND status = ?',
      whereArgs: [customerId, 'PENDING'],
    );

    if (existingQueue.isNotEmpty) {
      await db.update(
        'sync_queue',
        {
          'action': actionType,
          'data': jsonEncode(payload),
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [existingQueue.first['id']],
      );
    } else {
      await db.insert('sync_queue', {
        'tableName': 'customers',
        'action': actionType,
        'entityId': customerId,
        'data': jsonEncode(payload),
        'status': 'PENDING',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    }

    debugPrint("📥 [SYNC QUEUE] Client $customerId ajouté/mis à jour en file d'attente ($actionType).");
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircleAvatar(
              radius: 30,
              backgroundColor: Color(0xFFFFF3E0),
              child: Icon(Icons.person, size: 40, color: Colors.orange),
            ),
            const SizedBox(height: 15),
            const Text("Informations Client", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),

            TextField(
              controller: _phoneController,
              focusNode: _phoneFocusNode,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: "Téléphone",
                hintText: "Ex: 70000000",
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                prefixIcon: const Icon(Icons.phone),
                suffixIcon: _isSearching
                    ? const Padding(
                  padding: EdgeInsets.all(12.0),
                  child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange)),
                )
                    : null,
              ),
            ),
            const SizedBox(height: 15),

            TextField(
              controller: _nameController,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: "Nom complet",
                hintText: "Nom du client",
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                prefixIcon: const Icon(Icons.person),
              ),
            ),
            const SizedBox(height: 25),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () async {
                  FocusScope.of(context).unfocus();

                  final phone = _phoneController.text.trim();
                  final name = _nameController.text.trim();

                  if (phone.isNotEmpty && name.isNotEmpty) {
                    await _saveOrUpdateCustomer(phone, name);

                    if (mounted) {
                      Navigator.pop(context);
                      widget.onValidated(phone, name);
                    }
                  }
                },
                child: const Text("VALIDER", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            )
          ],
        ),
      ),
    );
  }
}