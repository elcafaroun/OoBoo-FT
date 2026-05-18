import 'package:flutter/material.dart';
import '../services/dashboard_service.dart';

class DashboardScreen extends StatefulWidget {
  final String structureId;
  const DashboardScreen({super.key, required this.structureId});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final DashboardService _dashboardService = DashboardService();
  DateTime selectedDate = DateTime.now();

  @override
  Widget build(BuildContext context) {
    String formattedDate = selectedDate.toIso8601String().split('T')[0];

    return Scaffold(
      backgroundColor: const Color(0xFFF9F7F2), // Fond crème léger
      appBar: AppBar(
        title: const Text(
          "Tableau de bord",
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(color: Colors.grey.withOpacity(0.2), height: 1.0),
        ),
      ),
      body: Column(
        children: [
          // --- SÉLECTEUR DE DATE (Look "Pro") ---
          Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Colors.grey.withOpacity(0.2)),
            ),
            child: ListTile(
              title: Text(
                "Date : ${selectedDate.day}/${selectedDate.month}/${selectedDate.year}",
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              trailing: const Icon(Icons.calendar_month, color: Color(0xFFFF9800)),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: selectedDate,
                  firstDate: DateTime(2024),
                  lastDate: DateTime.now(),
                );
                if (picked != null) setState(() => selectedDate = picked);
              },
            ),
          ),

          Expanded(
            child: FutureBuilder(
              future: Future.wait([
                _dashboardService.getDailySummary(formattedDate, widget.structureId),
                _dashboardService.getPaymentMethodsStats(formattedDate, widget.structureId),
              ]),
              builder: (context, AsyncSnapshot<List<dynamic>> snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Color(0xFFFF9800)));
                }

                final summary = snapshot.data?[0] ?? {};
                final paymentStats = snapshot.data?[1] as Map<String, dynamic>? ?? {};

                return ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    // --- GRILLE DES RÉSUMÉS ---
                    GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 1.3,
                      children: [
                        _buildStatCard("Ventes", "${summary['totalCommandes'] ?? 0}", Icons.trending_up, Colors.green),
                        _buildStatCard("Dépenses", "${summary['totalDepenses'] ?? 0}", Icons.trending_down, Colors.red),
                        _buildStatCard("Bénéfice", "${summary['benefice'] ?? 0}", Icons.account_balance_wallet, Colors.blue),
                      ],
                    ),

                    const SizedBox(height: 25),
                    const Padding(
                      padding: EdgeInsets.only(left: 5),
                      child: Text("Répartition par Paiement",
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 10),

                    // --- LISTE DES MODES DE PAIEMENT ---
                    paymentStats.isEmpty
                        ? const Center(child: Text("Aucune donnée disponible"))
                        : Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: Colors.grey.withOpacity(0.1)),
                      ),
                      child: Column(
                        children: paymentStats.entries.map((entry) {
                          return ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: _getColorForMethod(entry.key).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(_getIconForMethod(entry.key), color: _getColorForMethod(entry.key)),
                            ),
                            title: Text(entry.key, style: const TextStyle(fontWeight: FontWeight.w600)),
                            trailing: Text("${entry.value} FCFA",
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // --- WIDGET CARTE STATISTIQUE PRO ---
  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey.withOpacity(0.1)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(title, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 4),
          FittedBox(
            child: Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color)),
          ),
        ],
      ),
    );
  }

  // --- HELPERS VISUELS (Logique inchangée) ---
  IconData _getIconForMethod(String method) {
    method = method.toLowerCase();
    if (method.contains("orange")) return Icons.phonelink_ring;
    if (method.contains("mobicash")) return Icons.vibration;
    if (method.contains("cash") || method.contains("espèce")) return Icons.payments;
    return Icons.account_balance_wallet;
  }

  Color _getColorForMethod(String method) {
    method = method.toLowerCase();
    if (method.contains("orange")) return Colors.orange;
    if (method.contains("mobicash")) return Colors.green;
    if (method.contains("cash")) return Colors.blueGrey;
    return Colors.blue;
  }
}