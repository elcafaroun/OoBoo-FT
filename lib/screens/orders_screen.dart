import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
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
  DateTime? selectedDate;
  String activeFilter = "TOUS";

  @override
  void initState() {
    super.initState();
    _fetchOrders();
    _searchController.addListener(_applyFilters);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchOrders() async {
    if (!mounted) return;
    setState(() => isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    final structureId = prefs.getString('selected_structure_id') ?? "";

    if (structureId.isNotEmpty) {
      try {
        final data = await _commandService.getCommandsByStructure(structureId);
        if (mounted) {
          setState(() {
            allOrders = data;
            isLoading = false;
            _applyFilters();
          });
        }
      } catch (e) {
        if (mounted) setState(() => isLoading = false);
      }
    }
  }

  void _applyFilters() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      filteredOrders = allOrders.where((order) {
        final name = (order['customerName'] ?? '').toString().toLowerCase();
        final matchesSearch = name.contains(query);

        bool matchesDate = true;
        if (selectedDate != null) {
          DateTime d = DateTime.parse(order['orderDate']);
          matchesDate = (d.year == selectedDate!.year && d.month == selectedDate!.month && d.day == selectedDate!.day);
        }

        bool matchesStatus = true;
        final status = (order['status'] ?? 'PENDING').toString().toUpperCase();
        final double credit = (order['totalCredit'] ?? 0.0).toDouble();

        if (activeFilter == "PENDING") matchesStatus = (status == "PENDING" && credit == 0);
        if (activeFilter == "CANCELLED") matchesStatus = (status == "CANCELLED");
        if (activeFilter == "DETTE") matchesStatus = (credit > 0 && status != "CANCELLED");

        return matchesSearch && matchesDate && matchesStatus;
      }).toList();
    });
  }

  // --- LOGIQUE DE RÈGLEMENT ---
  Future<void> _handleUpdateCredit(dynamic order) async {
    final TextEditingController amountController = TextEditingController();
    final double currentCredit = (order['totalCredit'] ?? 0.0).toDouble();
    amountController.text = currentCredit.toStringAsFixed(0);

    String selectedMethod = "Espèces";
    final List<String> methods = ["Espèces", "Orange Money", "Moov Money", "Telecel Money"];

    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(builder: (context, setDialogState) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text("Règlement de crédit"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                  child: Text("Dette restante : ${currentCredit.toStringAsFixed(0)} FCFA", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red))),
              const SizedBox(height: 20),
              TextField(controller: amountController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Montant versé", border: OutlineInputBorder())),
              const SizedBox(height: 15),
              DropdownButtonFormField<String>(
                value: selectedMethod, decoration: const InputDecoration(labelText: "Mode de paiement", border: OutlineInputBorder()),
                items: methods.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                onChanged: (val) => setDialogState(() => selectedMethod = val!),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Annuler")),
            ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.green), onPressed: () => Navigator.pop(context, true), child: const Text("Valider", style: TextStyle(color: Colors.white))),
          ],
        );
      }),
    );

    if (confirm == true) {
      double amount = double.tryParse(amountController.text) ?? 0;
      if (amount <= 0) return;
      setState(() => isLoading = true);
      bool success = await _commandService.settleCredit(order['id'], amount, selectedMethod);
      if (success) { _fetchOrders(); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Paiement enregistré !"), backgroundColor: Colors.green)); } else { setState(() => isLoading = false); }
    }
  }

  Future<void> _handleCancelOrder(dynamic order) async {
    bool confirm = await showDialog(context: context, builder: (context) => AlertDialog(
      title: const Text("Annulation"), content: const Text("Confirmer l'annulation et restaurer le stock ?"),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Non")), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(context, true), child: const Text("Oui"))],
    )) ?? false;
    if (confirm) { setState(() => isLoading = true); await _commandService.cancelOrder(order['id']); _fetchOrders(); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F7F2), // Fond crème
      appBar: AppBar(
        title: const Text("Commandes", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          IconButton(icon: Icon(selectedDate == null ? Icons.calendar_today_outlined : Icons.filter_alt_off), onPressed: () => selectedDate == null ? _selectDate(context) : setState(() { selectedDate = null; _applyFilters(); })),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: "Rechercher un client...",
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                filled: true, fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(children: ["TOUS", "PENDING", "DETTE", "CANCELLED"].map((f) => _buildFilterChip(f)).toList()),
          ),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator(color: Colors.orange))
                : filteredOrders.isEmpty
                ? const Center(child: Text("Aucune commande", style: TextStyle(color: Colors.grey)))
                : RefreshIndicator(onRefresh: _fetchOrders, child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: filteredOrders.length,
              itemBuilder: (context, index) => _buildOrderCard(filteredOrders[index]),
            )),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label) {
    bool isSelected = activeFilter == label;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: FilterChip(
        label: Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.black87, fontWeight: FontWeight.w600)),
        selected: isSelected,
        selectedColor: Colors.orange,
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: isSelected ? Colors.orange : Colors.grey.shade300)),
        onSelected: (_) { setState(() { activeFilter = label; _applyFilters(); }); },
      ),
    );
  }

  Widget _buildOrderCard(dynamic order) {
    final status = (order['status'] ?? 'PENDING').toString().toUpperCase();
    final double credit = (order['totalCredit'] ?? 0.0).toDouble();
    final bool isCredit = credit > 0 && status != "CANCELLED";

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))]),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: CircleAvatar(backgroundColor: isCredit ? Colors.red.withOpacity(0.1) : Colors.orange.withOpacity(0.1), child: Icon(isCredit ? Icons.warning_rounded : Icons.shopping_bag, color: isCredit ? Colors.red : Colors.orange)),
        title: Text(order['customerName'] ?? "Client", style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text("#${order['id']} • ${isCredit ? credit.toStringAsFixed(0) : order['totalAmount']} FCFA", style: const TextStyle(fontSize: 12, color: Colors.grey)),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _infoRow("Date", DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(order['orderDate']))),
                _infoRow("Mode", order['paymentMethod']),
                const Divider(),
                const Text("Articles :", style: TextStyle(fontWeight: FontWeight.bold)),
                ...(order['items'] as List).map((it) => Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text("• ${it['productName']} x${it['quantity']}"), Text("${(it['unitPrice'] * it['quantity'])} F")]))).toList(),
                const SizedBox(height: 15),
                if (isCredit)
                  SizedBox(width: double.infinity, child: ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: Colors.green), onPressed: () => _handleUpdateCredit(order), icon: const Icon(Icons.payments, color: Colors.white), label: const Text("RÉGLER LA DETTE", style: TextStyle(color: Colors.white)))),
                if (status == 'PENDING')
                  SizedBox(width: double.infinity, child: TextButton(style: TextButton.styleFrom(foregroundColor: Colors.red), onPressed: () => _handleCancelOrder(order), child: const Text("ANNULER LA COMMANDE"))),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) => Padding(padding: const EdgeInsets.only(bottom: 4), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: const TextStyle(color: Colors.grey)), Text(value, style: const TextStyle(fontWeight: FontWeight.w600))]));

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(context: context, initialDate: selectedDate ?? DateTime.now(), firstDate: DateTime(2022), lastDate: DateTime(2030));
    if (picked != null) { setState(() { selectedDate = picked; _applyFilters(); }); }
  }
}