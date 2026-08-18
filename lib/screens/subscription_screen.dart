import 'package:flutter/material.dart';
import '../services/subscription_service.dart';
import '../models/subscription_plan.dart';
import 'add_structure_screen.dart';

class SubscriptionScreen extends StatefulWidget {
  final String? structureId;
  final int? filterPriorite;

  const SubscriptionScreen({
    super.key,
    this.structureId,
    this.filterPriorite,
  });

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
        title: Text(
          widget.structureId != null ? "RENOUVELER L'ABONNEMENT" : "CHOISIR UN PLAN",
          style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2),
        ),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: FutureBuilder<List<SubscriptionPlan>>(
        future: _plansFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFFFF9800)));
          }
          if (snapshot.hasError) return Center(child: Text("Erreur : ${snapshot.error}"));
          if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Text("Aucun plan disponible."));

          List<SubscriptionPlan> plans = snapshot.data!;

          // 🔹 Filtrage : conserve uniquement les plans de priorité inférieure ou égale
          if (widget.filterPriorite != null) {
            plans = plans.where((plan) {
              int planPriority = plan.priorite ?? 0;
              return planPriority <= widget.filterPriorite!;
            }).toList();
          }
          plans.sort((a, b) => (a.priorite ?? 0).compareTo(b.priorite ?? 0));
          if (plans.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(20.0),
                child: Text(
                  "Aucun plan égal ou inférieur disponible pour le moment.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.grey, fontWeight: FontWeight.bold),
                ),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            itemCount: plans.length,
            itemBuilder: (context, index) {
              final plan = plans[index];
              final featureList = (plan.features ?? "")
                  .split(',')
                  .where((f) => f.trim().isNotEmpty)
                  .toList();

              return Container(
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    )
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () async {
                      if (widget.structureId != null || widget.filterPriorite != null) {
                        Navigator.pop(context, plan);
                      } else {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => AddStructureScreen(plan: plan.name),
                          ),
                        );
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
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
                                    Text(
                                      plan.name.toUpperCase(),
                                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                                    ),
                                    Text(
                                      plan.price,
                                      style: TextStyle(
                                        color: plan.color ?? Colors.orange,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 30),
                          if (featureList.isNotEmpty)
                            ...featureList.map(
                                  (f) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  children: [
                                    Icon(Icons.check, color: plan.color ?? Colors.orange, size: 18),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        f.trim(),
                                        style: TextStyle(color: Colors.grey.shade700),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          const SizedBox(height: 15),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: plan.color ?? Colors.orange,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Center(
                              child: Text(
                                "SÉLECTIONNER CE PLAN",
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
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