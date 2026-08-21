import 'package:flutter/material.dart';
import '../services/dashboard_service.dart';

class MiniDashboardScreen extends StatefulWidget {
  final String structureId;

  const MiniDashboardScreen({super.key, required this.structureId});

  @override
  State<MiniDashboardScreen> createState() => _MiniDashboardScreenState();
}

class _MiniDashboardScreenState extends State<MiniDashboardScreen> {
  final DashboardService _dashboardService = DashboardService();
  DateTime selectedDate = DateTime.now();

  @override
  Widget build(BuildContext context) {
    String formattedDate = selectedDate.toIso8601String().split('T')[0];

    return Scaffold(
      backgroundColor: const Color(0xFFF9F7F2),
      appBar: AppBar(
        title: const Text(
          "Mini Dashboard",
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: Column(
        children: [
          // 🔹 Sélecteur de date
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
                if (picked != null) {
                  setState(() => selectedDate = picked);
                }
              },
            ),
          ),

          // 🔹 Chargement et affichage des chiffres
          Expanded(
            child: FutureBuilder<Map<String, dynamic>>(
              future: _dashboardService.getDailySummary(formattedDate, widget.structureId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: Color(0xFFFF9800)),
                  );
                }

                if (snapshot.hasError) {
                  return const Center(
                    child: Text("Erreur lors du chargement des données"),
                  );
                }

                final summary = snapshot.data ?? {};
                final totalVentes = summary['totalCommandes'] ?? 0;
                final totalDepenses = summary['totalDepenses'] ?? 0;
                final benefice = summary['benefice'] ?? (totalVentes - totalDepenses);

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      // Ventes
                      _buildSummaryCard(
                        title: "Ventes Total",
                        amount: "$totalVentes FCFA",
                        icon: Icons.trending_up_rounded,
                        color: Colors.green,
                      ),
                      const SizedBox(height: 12),

                      // Dépenses
                      _buildSummaryCard(
                        title: "Dépenses Total",
                        amount: "$totalDepenses FCFA",
                        icon: Icons.trending_down_rounded,
                        color: Colors.redAccent,
                      ),
                      const SizedBox(height: 12),

                      // Bénéfice / Résultat net
                      _buildSummaryCard(
                        title: "Bénéfice Net",
                        amount: "$benefice FCFA",
                        icon: Icons.account_balance_wallet_rounded,
                        color: Colors.blue,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // 🔹 Carte d'affichage simplifiée
  Widget _buildSummaryCard({
    required String title,
    required String amount,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withOpacity(0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    amount,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}