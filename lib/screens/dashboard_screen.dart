import 'package:flutter/material.dart';
import '../services/dashboard_service.dart';
import '../services/depense_service.dart';

class DashboardScreen extends StatefulWidget {
  final String structureId;
  const DashboardScreen({super.key, required this.structureId});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final DashboardService _dashboardService = DashboardService();
  final DepenseService _depenseService = DepenseService();

  // Date pour le résumé quotidien (Tab 1)
  DateTime selectedDailyDate = DateTime.now();

  // Date pour l'évolution mensuelle (Tab 3)
  DateTime selectedMonthlyDate = DateTime.now();

  @override
  Widget build(BuildContext context) {
    String formattedDailyDate = selectedDailyDate.toIso8601String().split('T')[0];
    String formattedMonthlyPeriod =
        "${selectedMonthlyDate.year}-${selectedMonthlyDate.month.toString().padLeft(2, '0')}";

    return DefaultTabController(
      length: 3, // 3 Onglets
      child: Scaffold(
        backgroundColor: const Color(0xFFF9F7F2), // Fond crème léger
        appBar: AppBar(
          title: const Text(
            "Tableau de bord",
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
          ),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
          bottom: const TabBar(
            labelColor: Colors.orange,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Colors.orange,
            indicatorWeight: 3,
            tabs: [
              Tab(icon: Icon(Icons.today), text: "Résumé"),
              Tab(icon: Icon(Icons.people), text: "Par Agent"),
              Tab(icon: Icon(Icons.bar_chart), text: "Évolution"),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // --- TAB 1 : RÉSUMÉ QUOTIDIEN ---
            _buildDailyTab(formattedDailyDate),

            // --- TAB 2 : REPARTITION PAR AGENT ---
            _buildAgentsTab(),

            // --- TAB 3 : GRAPHIQUE ÉVOLUTION ---
            _buildEvolutionTab(formattedMonthlyPeriod),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // TAB 1 : RÉSUMÉ QUOTIDIEN
  // ==========================================
  Widget _buildDailyTab(String formattedDate) {
    return Column(
      children: [
        // Sélecteur de date journalier
        Container(
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.grey.withOpacity(0.2)),
          ),
          child: ListTile(
            title: Text(
              "Date : ${selectedDailyDate.day}/${selectedDailyDate.month}/${selectedDailyDate.year}",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            trailing: const Icon(Icons.calendar_month, color: Color(0xFFFF9800)),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: selectedDailyDate,
                firstDate: DateTime(2024),
                lastDate: DateTime.now(),
              );
              if (picked != null) {
                setState(() => selectedDailyDate = picked);
              }
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
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 3, // Adapté pour 3 cartes côte-à-côte sans débordement
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.95,
                    children: [
                      _buildStatCard("Ventes", "${summary['totalCommandes'] ?? 0} FCFA", Icons.trending_up, Colors.green),
                      _buildStatCard("Dépenses", "${summary['totalDepenses'] ?? 0} FCFA", Icons.trending_down, Colors.red),
                      _buildStatCard("Bénéfice", "${summary['benefice'] ?? 0} FCFA", Icons.account_balance_wallet, Colors.blue),
                    ],
                  ),
                  const SizedBox(height: 25),
                  const Padding(
                    padding: EdgeInsets.only(left: 5),
                    child: Text("Répartition par Paiement", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 10),
                  paymentStats.isEmpty
                      ? const Center(child: Padding(padding: EdgeInsets.all(20), child: Text("Aucune donnée de paiement disponible")))
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
                          trailing: Text("${entry.value} FCFA", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
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
    );
  }

  // ==========================================
  // TAB 2 : RÉPARTITION DES VENTES PAR AGENT
  // ==========================================
  Widget _buildAgentsTab() {
    return FutureBuilder<List<dynamic>>(
      future: _dashboardService.getSalesByUser(widget.structureId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Colors.orange));
        }

        final usersData = snapshot.data ?? [];

        if (usersData.isEmpty) {
          return const Center(
            child: Text("Aucune vente enregistrée par un utilisateur pour le moment."),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: usersData.length,
          itemBuilder: (context, index) {
            final user = usersData[index];
            final String name = user['userName'] ?? 'Agent inconnu';
            final double amount = (user['totalSalesAmount'] as num?)?.toDouble() ?? 0.0;

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.grey.withOpacity(0.1)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.02),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  )
                ],
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.orange.withOpacity(0.1),
                  child: const Icon(Icons.person, color: Colors.orange),
                ),
                title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                subtitle: const Text("Total des commandes validées"),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    "${amount.toStringAsFixed(0)} FCFA",
                    style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ==========================================
  // TAB 3 : GRAPHIQUE ÉVOLUTION DU MOIS (VENTES & DÉPENSES)
  // ==========================================
  Widget _buildEvolutionTab(String currentYearMonth) {
    final List<String> monthNames = [
      "Janvier", "Février", "Mars", "Avril", "Mai", "Juin",
      "Juillet", "Août", "Septembre", "Octobre", "Novembre", "Décembre"
    ];

    return Column(
      children: [
        // --- SÉLECTEUR DE MOIS DYNAMIQUE ---
        Container(
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.grey.withOpacity(0.2)),
          ),
          child: ListTile(
            title: Text(
              "Période : ${monthNames[selectedMonthlyDate.month - 1]} ${selectedMonthlyDate.year}",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            trailing: const Icon(Icons.calendar_view_month, color: Colors.orange),
            onTap: () => _selectMonthAndYear(context),
          ),
        ),

        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: Future.wait([
              _dashboardService.getMonthlyDailySales(widget.structureId, currentYearMonth),
              _depenseService.getMonthlyDailyExpenses(widget.structureId, currentYearMonth),
            ]),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: Colors.orange));
              }

              final Map<String, dynamic> rawSalesData = snapshot.data?[0] ?? {};
              final Map<String, dynamic> rawExpensesData = snapshot.data?[1] ?? {};

              if (rawSalesData.isEmpty && rawExpensesData.isEmpty) {
                return const Center(
                  child: Text("Aucune donnée disponible pour ce mois."),
                );
              }

              // --- HARMONISATION DES CLÉS DE JOURS ---
              final Map<String, double> salesData = {};
              rawSalesData.forEach((key, value) {
                String cleanKey = key.contains('-') ? key.split('-').last : key;
                if (cleanKey.length == 1) cleanKey = "0$cleanKey";
                salesData[cleanKey] = (value as num).toDouble();
              });

              final Map<String, double> expensesData = {};
              rawExpensesData.forEach((key, value) {
                String cleanKey = key.contains('-') ? key.split('-').last : key;
                if (cleanKey.length == 1) cleanKey = "0$cleanKey";
                expensesData[cleanKey] = (value as num).toDouble();
              });

              // Calculs des indicateurs totaux du mois sélectionné
              double totalSales = salesData.values.fold(0.0, (sum, item) => sum + item);
              double totalExpenses = expensesData.values.fold(0.0, (sum, item) => sum + item);
              double netResult = totalSales - totalExpenses;

              // Trouver le plafond maximum pour étalonner la hauteur des barres
              double maxValSales = salesData.values.isNotEmpty ? salesData.values.reduce((a, b) => a > b ? a : b) : 0.0;
              double maxValExp = expensesData.values.isNotEmpty ? expensesData.values.reduce((a, b) => a > b ? a : b) : 0.0;
              final double maxAmount = maxValSales > maxValExp ? maxValSales : (maxValExp > 0 ? maxValExp : 1.0);

              // Fusionner et trier tous les jours disponibles (de "01" à "31")
              final Set<String> allDays = {}
                ..addAll(salesData.keys)
                ..addAll(expensesData.keys);
              final List<String> sortedDays = allDays.toList()..sort();

              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // --- CARTES DE SYNTHÈSE DU MOIS SÉLECTIONNÉ ---
                    Row(
                      children: [
                        Expanded(
                          child: _buildSummaryMiniCard(
                              "Ventes",
                              "${totalSales.toStringAsFixed(0)} FCFA",
                              Colors.orange
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildSummaryMiniCard(
                              "Dépenses",
                              "${totalExpenses.toStringAsFixed(0)} FCFA",
                              Colors.redAccent
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildSummaryMiniCard(
                              "Résultat",
                              "${netResult.toStringAsFixed(0)} FCFA",
                              netResult >= 0 ? Colors.green : Colors.deepOrange
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    const Text(
                        "Évolution Quotidienne",
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)
                    ),
                    const Text(
                        "Comparatif des flux de trésorerie par jour",
                        style: TextStyle(color: Colors.grey, fontSize: 13)
                    ),
                    const SizedBox(height: 15),

                    // --- GRAPHIQUE AMÉLIORÉ À DOUBLE COMPARTIMENTS ---
                    Container(
                      height: 280,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.grey.withOpacity(0.1)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.01),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          )
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: sortedDays.map((day) {
                              final double saleVal = salesData[day] ?? 0.0;
                              final double expVal = expensesData[day] ?? 0.0;

                              final double saleHeightFactor = maxAmount > 0 ? (saleVal / maxAmount) : 0.0;
                              final double expHeightFactor = maxAmount > 0 ? (expVal / maxAmount) : 0.0;

                              return Container(
                                width: 55,
                                margin: const EdgeInsets.symmetric(horizontal: 4),
                                decoration: BoxDecoration(
                                  color: Colors.grey.withOpacity(0.03),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    // Affichage condensé des valeurs au-dessus des barres
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                      children: [
                                        FittedBox(
                                          child: Text(
                                            saleVal > 0 ? "${(saleVal / 1000).toStringAsFixed(0)}k" : "-",
                                            style: const TextStyle(fontSize: 7, fontWeight: FontWeight.bold, color: Colors.orange),
                                          ),
                                        ),
                                        FittedBox(
                                          child: Text(
                                            expVal > 0 ? "${(expVal / 1000).toStringAsFixed(0)}k" : "-",
                                            style: const TextStyle(fontSize: 7, fontWeight: FontWeight.bold, color: Colors.redAccent),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    // Les deux barres physiques côte-à-côte
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        // Barre Vente (Orange)
                                        AnimatedContainer(
                                          duration: const Duration(milliseconds: 500),
                                          height: (saleHeightFactor * 160).clamp(5, 160).toDouble(),
                                          width: 14,
                                          decoration: BoxDecoration(
                                            gradient: const LinearGradient(
                                              colors: [Colors.orange, Colors.orangeAccent],
                                              begin: Alignment.topCenter,
                                              end: Alignment.bottomCenter,
                                            ),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                        ),
                                        // Barre Dépense (Rouge)
                                        AnimatedContainer(
                                          duration: const Duration(milliseconds: 500),
                                          height: (expHeightFactor * 160).clamp(5, 160).toDouble(),
                                          width: 14,
                                          decoration: BoxDecoration(
                                            gradient: const LinearGradient(
                                              colors: [Colors.redAccent, Colors.red],
                                              begin: Alignment.topCenter,
                                              end: Alignment.bottomCenter,
                                            ),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    // Numéro du Jour
                                    Text(
                                      day,
                                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 25),
                    // Légendes explicatives
                    _buildLegendRow("Montant maximal enregistré", "${maxAmount.toStringAsFixed(0)} FCFA", Colors.blueGrey),
                    _buildLegendRow("Vente Quotidienne", "Barre Orange", Colors.orange),
                    _buildLegendRow("Dépense Quotidienne", "Barre Rouge", Colors.redAccent),
                    const SizedBox(height: 30),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // --- WIDGET PETITE CARTE DE SYNTHÈSE MENSUELLE ---
  Widget _buildSummaryMiniCard(String title, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          FittedBox(
            child: Text(
              value,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: color),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  // --- DIALOGUE SÉLECTION DU MOIS / ANNÉE ---
  void _selectMonthAndYear(BuildContext context) async {
    int tempYear = selectedMonthlyDate.year;
    int tempMonth = selectedMonthlyDate.month;

    final List<String> monthNames = [
      "Janvier", "Février", "Mars", "Avril", "Mai", "Juin",
      "Juillet", "Août", "Septembre", "Octobre", "Novembre", "Décembre"
    ];

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text("Choisir un mois", style: TextStyle(fontWeight: FontWeight.bold)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios, size: 16),
                        onPressed: () => setDialogState(() => tempYear--),
                      ),
                      Text("$tempYear", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.orange)),
                      IconButton(
                        icon: const Icon(Icons.arrow_forward_ios, size: 16),
                        onPressed: tempYear < DateTime.now().year
                            ? () => setDialogState(() => tempYear++)
                            : null,
                      ),
                    ],
                  ),
                  const Divider(),
                  SizedBox(
                    width: double.maxFinite,
                    height: 200,
                    child: GridView.builder(
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        childAspectRatio: 1.5,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemCount: 12,
                      itemBuilder: (context, index) {
                        final isSelected = (index + 1) == tempMonth;
                        final String fullMonthName = monthNames[index];

                        final String abbrevName = fullMonthName.length > 4
                            ? fullMonthName.substring(0, 4)
                            : fullMonthName;

                        return InkWell(
                          onTap: () {
                            setDialogState(() => tempMonth = index + 1);
                          },
                          child: Container(
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: isSelected ? Colors.orange : Colors.grey.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              abbrevName,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isSelected ? Colors.white : Colors.black,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  child: const Text("ANNULER", style: TextStyle(color: Colors.grey)),
                  onPressed: () => Navigator.pop(context),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                  child: const Text("VALIDER", style: TextStyle(color: Colors.white)),
                  onPressed: () {
                    setState(() {
                      selectedMonthlyDate = DateTime(tempYear, tempMonth);
                    });
                    Navigator.pop(context);
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildLegendRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.grey)),
            ],
          ),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        ],
      ),
    );
  }

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
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 6),
          Text(title, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: FittedBox(
              child: Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: color)),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getIconForMethod(String method) {
    method = method.toLowerCase();
    if (method.contains("orange")) return Icons.phonelink_ring;
    if (method.contains("mobicash") || method.contains("moov")) return Icons.vibration;
    if (method.contains("cash") || method.contains("espèce")) return Icons.payments;
    return Icons.account_balance_wallet;
  }

  Color _getColorForMethod(String method) {
    method = method.toLowerCase();
    if (method.contains("orange")) return Colors.orange;
    if (method.contains("mobicash") || method.contains("moov")) return Colors.green;
    if (method.contains("cash")) return Colors.blueGrey;
    return Colors.blue;
  }
}