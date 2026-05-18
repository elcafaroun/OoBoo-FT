import 'package:flutter/material.dart';
import '../services/subscription_service.dart';
import '../models/subscription_plan.dart';
import 'add_structure_screen.dart';

class SubscriptionScreen extends StatefulWidget {
  final int? filterPriorite;

  const SubscriptionScreen({super.key, this.filterPriorite});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  final SubscriptionService _subService = SubscriptionService();
  late Future<List<SubscriptionPlan>> _plansFuture;

  @override
  void initState() {
    super.initState();
    _plansFuture = _subService.getAllPlans();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F4F4),
      appBar: AppBar(
        title: const Text("CHOISIR UN PLAN", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2)),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        centerTitle: true,
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
      ),
      body: FutureBuilder<List<SubscriptionPlan>>(
        future: _plansFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFFFF9800)));
          }
          if (snapshot.hasError) return Center(child: Text("Erreur : ${snapshot.error}"));
          if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Text("Aucun plan disponible."));

          // --- LOGIQUE DE FILTRAGE RENFORCÉE ---
          List<SubscriptionPlan> plans = snapshot.data!;
          if (widget.filterPriorite != null) {
            plans = plans.where((p) {
              // 1. Filtre Coût : doit être > 0
              final num prix = num.tryParse(p.price.toString().replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
              final bool isCostValid = prix > 0;

              // 2. Filtre Priorité : conversion forcée en int
              final int planPriorite = int.tryParse(p.priorite.toString()) ?? 0;
              final bool isPrioriteValid = planPriorite >= widget.filterPriorite!;

              return isCostValid && isPrioriteValid;
            }).toList();
          }

          if (plans.isEmpty) return const Center(child: Text("Aucun plan disponible selon vos critères."));

          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            itemCount: plans.length,
            itemBuilder: (context, index) {
              final plan = plans[index];
              final featureList = (plan.features ?? "").split(',').where((f) => f.trim().isNotEmpty).toList();

              return Container(
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      if (widget.filterPriorite != null) {
                        Navigator.pop(context, plan); // Retour au menu précédent avec le plan
                      } else {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(builder: (context) => AddStructureScreen(plan: plan.name)));
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header du Plan
                          Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: (plan.color ?? Colors.orange).withOpacity(0.1),
                                child: Icon(plan.icon ?? Icons.star, color: plan.color ?? Colors.orange),
                              ),
                              const SizedBox(width: 15),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(plan.name.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                                    Text(plan.price, style: TextStyle(color: plan.color ?? Colors.orange, fontWeight: FontWeight.bold, fontSize: 14)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 30),
                          // Liste des fonctionnalités
                          if (featureList.isNotEmpty)
                            ...featureList.map((f) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                children: [
                                  Icon(Icons.check, color: plan.color ?? Colors.orange, size: 18),
                                  const SizedBox(width: 10),
                                  Expanded(child: Text(f.trim(), style: TextStyle(color: Colors.grey.shade700))),
                                ],
                              ),
                            )),
                          const SizedBox(height: 15),
                          // Bouton d'action
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: plan.color ?? Colors.orange,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Center(
                              child: Text("SÉLECTIONNER CE PLAN", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            ),
                          )
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}