import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import '../services/command_service.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});
  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  final CommandService _commandService = CommandService();
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
    setState(() => isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    final structureId = prefs.getString('selected_structure_id') ?? "";
    if (structureId.isNotEmpty) {
      final data = await _commandService.getCommandsByStructure(structureId);
      if (mounted) {
        setState(() {
          allOrders = data;
          _applyFilters();
          isLoading = false;
        });
      }
    } else {
      setState(() => isLoading = false);
    }
  }

  void _applyFilters() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      filteredOrders = allOrders.where((order) {
        final name = (order['customerName'] ?? '').toString().toLowerCase();
        final matchesSearch = name.contains(query);
        bool matchesDate = selectedDate == null ||
            DateFormat('yyyy-MM-dd').format(DateTime.parse(order['orderDate'])) ==
                DateFormat('yyyy-MM-dd').format(selectedDate!);
        final status = (order['status'] ?? 'PENDING').toString().toUpperCase();
        bool matchesStatus = activeFilter == "TOUS" || status == activeFilter;
        return matchesSearch && matchesDate && matchesStatus;
      }).toList();
    });
  }

  Future<pw.Document> _generatePdf(dynamic order) async {
    final pdf = pw.Document();
    pdf.addPage(pw.Page(pageFormat: PdfPageFormat.a6, build: (pw.Context context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text("FACTURE: ${order['customerName']}", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.Divider(),
          pw.Text("Total : ${order['totalAmount']} FCFA"),
        ]
    )));
    return pdf;
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
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredOrders.isEmpty
                ? const Center(child: Text("Aucune commande trouvée"))
                : ListView.separated(
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
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(children: [
            Expanded(child: TextField(
              controller: _searchController,
              decoration: InputDecoration(hintText: "Rechercher...", prefixIcon: const Icon(Icons.search), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none), filled: true, fillColor: Colors.grey.shade100),
            )),
            const SizedBox(width: 8),
            IconButton.filled(onPressed: () async {
              DateTime? picked = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2022), lastDate: DateTime(2030));
              if (picked != null) { setState(() => selectedDate = picked); _applyFilters(); }
            }, icon: const Icon(Icons.calendar_month), style: IconButton.styleFrom(backgroundColor: Colors.orange))
          ]),
          const SizedBox(height: 12),
          Row(children: ["TOUS", "COMPLETED", "PENDING"].map((f) => Expanded(
            child: GestureDetector(
              onTap: () { setState(() => activeFilter = f); _applyFilters(); },
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(color: activeFilter == f ? Colors.orange : Colors.grey.shade200, borderRadius: BorderRadius.circular(8)),
                child: Center(child: Text(f, style: TextStyle(color: activeFilter == f ? Colors.white : Colors.grey.shade700, fontWeight: FontWeight.bold))),
              ),
            ),
          )).toList())
        ],
      ),
    );
  }

  Widget _buildOrderTile(dynamic order) {
    bool isPending = order['status'] == 'PENDING';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade100)),
      child: Column(
        children: [
          Row(children: [
            Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: isPending ? Colors.orange.shade50 : Colors.green.shade50, borderRadius: BorderRadius.circular(12)), child: Icon(Icons.receipt_long, color: isPending ? Colors.orange : Colors.green)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(order['customerName'] ?? "Inconnu", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Text(order['orderDate'] != null ? DateFormat('dd MMM yyyy').format(DateTime.parse(order['orderDate'])) : "", style: TextStyle(color: Colors.grey.shade600))
            ])),
            Text("${order['totalAmount']} FCFA", style: const TextStyle(fontWeight: FontWeight.w900))
          ]),
          const Divider(height: 24),
          Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                    onPressed: () async {
                      final doc = await _generatePdf(order);
                      await Printing.layoutPdf(onLayout: (f) => doc.save());
                    },
                    icon: const Icon(Icons.print, size: 16),
                    label: const Text("Imprimer")
                ),
                if(isPending) ...[
                  FilledButton(onPressed: () {}, style: FilledButton.styleFrom(backgroundColor: Colors.green), child: const Text("Payer")),
                  FilledButton(onPressed: () {}, style: FilledButton.styleFrom(backgroundColor: Colors.red), child: const Text("Annuler")),
                ]
              ]
          )
        ],
      ),
    );
  }
}