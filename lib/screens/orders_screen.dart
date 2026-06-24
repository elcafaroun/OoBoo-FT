import 'dart:io';
import 'package:fada/services/network_checker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../services/command_service.dart';
import '../services/database/database_helper.dart'; // Import nécessaire

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});
  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  final CommandService _commandService = CommandService();
  final DatabaseHelper _dbHelper = DatabaseHelper(); // Instance ajoutée
  final TextEditingController _searchController = TextEditingController();

  List<dynamic> allOrders = [];
  List<dynamic> filteredOrders = [];
  bool isLoading = true;
  String activeFilter = "TOUS";
  DateTime? selectedDate;

  @override
  void initState() {
    super.initState();
    _fetchOrders();
    _searchController.addListener(_applyFilters);
  }

  Future<void> _fetchOrders() async {
    final prefs = await SharedPreferences.getInstance();
    final structureId = prefs.getString('selected_structure_id') ?? "";

    if (structureId.isEmpty) {
      if (mounted) setState(() => isLoading = false);
      return;
    }

    // 1. CHARGEMENT LOCAL IMMEDIAT (Source de vérité)
    final localData = await _dbHelper.getLocalCommands(structureId);
    if (mounted) {
      setState(() {
        allOrders = localData;
        _applyFilters(); // Applique le filtre immédiatement
        isLoading = false;
      });
    }

    // 2. SYNCHRONISATION EN ARRIÈRE-PLAN
    if (await NetworkChecker.isBackendAccessible()) {
      try {
        final remoteData = await _commandService.getCommandsByStructure(structureId);
        await _dbHelper.syncCommandsLocal(remoteData);

        // Rafraîchir avec les données fraîches si nécessaire
        final updatedLocalData = await _dbHelper.getLocalCommands(structureId);
        if (mounted) {
          setState(() {
            allOrders = updatedLocalData;
            _applyFilters();
          });
        }
      } catch (e) {
        debugPrint("⚠️ Synchro API échouée, maintien du cache : $e");
      }
    }
  }

  // --- FONCTIONNALITÉS ---
  Future<void> _printReceipt(dynamic order, double amount, String method) async {
    final pdf = pw.Document();
    final orderId = order['id']?.toString() ?? "N/A";
    final List<dynamic> items = order['items'] ?? [];

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a6,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(child: pw.Text("REÇU DE PAIEMENT", style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold))),
              pw.Divider(),
              pw.Text("Client : ${order['customerName'] ?? 'Inconnu'}"),
              pw.Text("Date : ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}"),
              pw.Text("Mode : $method"),
              pw.Divider(),
              ...items.map((item) => pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text("${item['productName'] ?? 'Produit'} (x${item['quantity'] ?? 1})"),
                  pw.Text("${(item['unitPrice'] ?? 0 * (item['quantity'] ?? 1)).toStringAsFixed(0)} FCFA"),
                ],
              )),
              pw.Divider(),
              pw.Text("Total réglé : ${amount.toStringAsFixed(0)} FCFA", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 10),
              pw.Center(child: pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: orderId, width: 60, height: 60)),
              pw.Text("Merci pour votre confiance", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            ],
          );
        },
      ),
    );
    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save());
  }

  Future<void> _cancelOrder(dynamic order) async {
    final prefs = await SharedPreferences.getInstance();
    final String? profile = prefs.getString('userProfile');

    if (profile != 'Super admin' && profile != 'Administrateur') {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Accès refusé."), backgroundColor: Colors.red));
      return;
    }

    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Confirmation"),
        content: Text("Annuler la commande de ${order['customerName'] ?? 'ce client'} ?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Non")),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Oui")),
        ],
      ),
    );

    if (confirm == true) {
      await _commandService.cancelOrder(order['id']);
      await _fetchOrders();
    }
  }

  Future<void> _showSettleDialog(dynamic order) async {
    final rawAmount = order['totalCredit'] ?? 0;
    final double maxAmount = (rawAmount is num) ? rawAmount.toDouble() : 0.0;
    final TextEditingController amountController = TextEditingController(text: maxAmount.toString());
    String selectedPaymentMethod = "Espèces";
    final List<String> methods = ["Espèces", "Mobile Money", "Chèque", "Virement"];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("Régler le crédit"),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text("Total dû : $maxAmount FCFA"),
            const SizedBox(height: 15),
            TextField(controller: amountController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Montant", border: OutlineInputBorder())),
            const SizedBox(height: 15),
            DropdownButtonFormField<String>(
              value: selectedPaymentMethod,
              items: methods.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
              onChanged: (v) => setDialogState(() => selectedPaymentMethod = v!),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Annuler")),
            ElevatedButton(onPressed: () async {
              double? amount = double.tryParse(amountController.text);
              if (amount != null && amount > 0) {
                Navigator.pop(context);
                bool success = await _commandService.settleCredit(order['id'], amount, selectedPaymentMethod);
                if (success) {
                  await _printReceipt(order, amount, selectedPaymentMethod);
                  await _fetchOrders();
                }
              }
            }, child: const Text("Valider")),
          ],
        ),
      ),
    );
  }

  void _applyFilters() {
    setState(() {
      filteredOrders = allOrders.where((order) {
        final query = _searchController.text.toLowerCase();
        final name = (order['customerName'] ?? '').toString().toLowerCase();
        bool matchesSearch = name.contains(query);
        bool matchesDate = selectedDate == null ||
            (order['orderDate'] != null && DateFormat('yyyy-MM-dd').format(DateTime.parse(order['orderDate'])) == DateFormat('yyyy-MM-dd').format(selectedDate!));
        String status = (order['status'] ?? 'PENDING').toString().toUpperCase();
        bool matchesStatus = activeFilter == "TOUS" || status == activeFilter;
        return matchesSearch && matchesDate && matchesStatus;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(title: const Text("Mes Commandes", style: TextStyle(color: Colors.black)), backgroundColor: Colors.white, elevation: 0),
      body: Column(
        children: [
          _buildTopBar(),
          Expanded(
            child: isLoading ? const Center(child: CircularProgressIndicator()) :
            filteredOrders.isEmpty ? const Center(child: Text("Aucune commande trouvée")) :
            ListView.separated(
              padding: const EdgeInsets.all(16),
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemCount: filteredOrders.length,
              itemBuilder: (context, index) => _buildOrderTile(filteredOrders[index]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(color: Colors.white, padding: const EdgeInsets.all(16), child: Column(children: [
      Row(children: [
        Expanded(child: TextField(controller: _searchController, decoration: InputDecoration(hintText: "Rechercher...", prefixIcon: const Icon(Icons.search), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none), filled: true, fillColor: Colors.grey.shade100))),
        const SizedBox(width: 8),
        IconButton.filled(onPressed: () async {
          DateTime? picked = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2022), lastDate: DateTime(2030));
          if (picked != null) { setState(() => selectedDate = picked); _applyFilters(); }
        }, icon: const Icon(Icons.calendar_month), style: IconButton.styleFrom(backgroundColor: Colors.orange))
      ]),
      const SizedBox(height: 12),
      SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: ["TOUS", "COMPLETED", "PENDING", "CANCELLED"].map((f) => GestureDetector(
        onTap: () { setState(() => activeFilter = f); _applyFilters(); },
        child: Container(margin: const EdgeInsets.symmetric(horizontal: 4), padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12), decoration: BoxDecoration(color: activeFilter == f ? Colors.orange : Colors.grey.shade200, borderRadius: BorderRadius.circular(8)), child: Text(f, style: TextStyle(color: activeFilter == f ? Colors.white : Colors.grey.shade700, fontWeight: FontWeight.bold))),
      )).toList()))
    ]));
  }

  Widget _buildOrderTile(dynamic order) {
    String status = (order['status'] ?? 'PENDING').toString().toUpperCase();
    return Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade100)), child: Column(children: [
      Row(children: [
        Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.receipt_long, color: Colors.orange)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(order['customerName'] ?? "Inconnu", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          Text(order['orderDate'] != null ? DateFormat('dd MMM yyyy').format(DateTime.parse(order['orderDate'])) : "", style: TextStyle(color: Colors.grey.shade600))
        ])),
        Text("${order['totalAmount']} FCFA", style: const TextStyle(fontWeight: FontWeight.w900))
      ]),
      const Divider(height: 24),
      Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: [
        OutlinedButton.icon(onPressed: () => _printReceipt(order, (order['totalAmount'] ?? 0).toDouble(), order['paymentMethod'] ?? "Espèces"), icon: const Icon(Icons.print, size: 16), label: const Text("Imp")),
        if (status == 'PENDING') FilledButton.icon(onPressed: () => _showSettleDialog(order), style: FilledButton.styleFrom(backgroundColor: Colors.blue), icon: const Icon(Icons.attach_money, size: 16), label: const Text("Régler")),
        if (status != 'CANCELLED') FilledButton(onPressed: () => _cancelOrder(order), style: FilledButton.styleFrom(backgroundColor: Colors.red), child: const Text("Annuler")),
      ])
    ]));
  }
}