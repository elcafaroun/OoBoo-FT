import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/structure_service.dart';
import '../services/network_checker.dart'; // ✅ Importation de ton service amélioré
import '../models/subscription_plan.dart';
import 'structure_categories_screen.dart';
import 'subscription_screen.dart';

class MonEspaceScreen extends StatefulWidget {
  const MonEspaceScreen({super.key});

  @override
  State<MonEspaceScreen> createState() => _MonEspaceScreenState();
}

class _MonEspaceScreenState extends State<MonEspaceScreen> {
  final StructureService _structureService = StructureService();

  bool isLoading = true;
  bool isCheckingNetwork = false;
  bool isBackendAccessible = true;
  List<dynamic> userStructures = [];

  @override
  void initState() {
    super.initState();
    _checkNetworkAndLoad();
  }

  /// 🔹 Point d'entrée unique qui orchestre la vérification réseau et le chargement
  Future<void> _checkNetworkAndLoad() async {
    if (!mounted) return;
    setState(() {
      if (userStructures.isEmpty) {
        isLoading = true;
      } else {
        isCheckingNetwork = true;
      }
    });

    // ✅ Appel direct de la méthode statique optimisée de ton service
    bool online = await NetworkChecker.isBackendAccessible();

    if (!online) {
      if (mounted) {
        setState(() {
          isBackendAccessible = false;
          isLoading = false;
          isCheckingNetwork = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() => isBackendAccessible = true);
    }
    await _loadStructures();
  }

  Future<void> _loadStructures() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? userId = prefs.getString('userId');

      if (userId != null) {
        List<dynamic> result = await _structureService.getStructuresByUser(userId);

        if (mounted) {
          setState(() {
            userStructures = result;
            isLoading = false;
            isCheckingNetwork = false;
          });
        }
      } else {
        if (mounted) setState(() => isLoading = false);
      }
    } catch (e) {
      debugPrint("❌ Erreur chargement structures : $e");
      if (mounted) {
        setState(() {
          isLoading = false;
          isCheckingNetwork = false;
        });
      }
    }
  }

  Future<void> _handleSubscriptionAction(dynamic s, bool isExpired) async {
    final String structureId = (s['id'] ?? s['structureId'] ?? s['idStructure']).toString();
    final int currentPriorite = int.tryParse(s['priorite']?.toString() ?? '0') ?? 0;

    final SubscriptionPlan? selectedPlan = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SubscriptionScreen(filterPriorite: currentPriorite)),
    );

    if (selectedPlan != null) {
      if (mounted) setState(() => isLoading = true);
      try {
        await _structureService.updateStructurePlan(structureId, selectedPlan.name);
        await _checkNetworkAndLoad();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("✅ Mise à jour effectuée !"), backgroundColor: Colors.green));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erreur : $e"), backgroundColor: Colors.red));
        }
      } finally {
        if (mounted) setState(() => isLoading = false);
      }
    }
  }

  bool _isExpired(dynamic s) {
    if (s['cout'] != null && (s['cout'] == 0.0 || s['cout'] == 0)) return false;
    if (s['endSub'] == null) return true;
    try {
      DateTime endDate = DateTime.parse(s['endSub'].toString());
      return DateTime.now().isAfter(endDate);
    } catch (e) {
      return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: isBackendAccessible ? const Color(0xFFF8FAFC) : Colors.white,
      appBar: AppBar(
        title: Text(
            isBackendAccessible ? "ADMINISTRATION" : "",
            style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.5)
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1E293B),
        elevation: 0,
        leading: Navigator.canPop(context) ? const BackButton(color: Colors.black87) : null,
        actions: isBackendAccessible
            ? [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _checkNetworkAndLoad,
          )
        ]
            : null,
      ),
      floatingActionButton: (isBackendAccessible && !isLoading)
          ? FloatingActionButton(
        backgroundColor: const Color(0xFFFF9800),
        elevation: 4,
        onPressed: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => const SubscriptionScreen()));
          _checkNetworkAndLoad();
        },
        child: const Icon(Icons.add, color: Colors.white, size: 28),
      )
          : null,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: _buildCurrentState(),
      ),
    );
  }

  Widget _buildCurrentState() {
    if (isLoading) {
      return const Center(
        key: ValueKey('loading_state'),
        child: CircularProgressIndicator(color: Color(0xFFFF9800)),
      );
    }

    if (!isBackendAccessible) {
      return _buildOfflineView();
    }

    return _buildOnlineAdminView();
  }

  /// 🛰️ Vue Hors-ligne unifiée et centrée
  Widget _buildOfflineView() {
    return SafeArea(
      key: const ValueKey('offline_state'),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.wifi_off_rounded,
                  size: 72,
                  color: Colors.red.shade400,
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                "Service déconnecté",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1E293B), letterSpacing: -0.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              const Text(
                "Le module d'administration requiert une synchronisation en direct avec le serveur. Vérifiez votre réseau ou réessayez.",
                style: TextStyle(fontSize: 14, color: Color(0xFF64748B), height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),

              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: isCheckingNetwork ? null : _checkNetworkAndLoad,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF9800),
                    disabledBackgroundColor: Colors.orange.shade300,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  child: isCheckingNetwork
                      ? const SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                  )
                      : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.refresh_rounded, color: Colors.white),
                      SizedBox(width: 8),
                      Text("VÉRIFIER À NOUVEAU", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 0.5)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 🏢 Vue Online de l'Espace Administration
  Widget _buildOnlineAdminView() {
    return RefreshIndicator(
      key: const ValueKey('online_state'),
      onRefresh: _checkNetworkAndLoad,
      color: const Color(0xFFFF9800),
      child: Column(
        children: [
          _buildHeaderStats(),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              itemCount: userStructures.length,
              itemBuilder: (context, index) => _buildProCard(userStructures[index]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderStats() {
    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF9800), Color(0xFFF57C00)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: const Color(0xFFFF9800).withOpacity(0.25), blurRadius: 15, offset: const Offset(0, 8))],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text("TOTAL STRUCTURES", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 0.5)),
          Text("${userStructures.length}", style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  Widget _buildProCard(dynamic s) {
    final id = (s['id'] ?? s['structureId'] ?? s['idStructure']).toString();
    final name = s['nomStructure'] ?? 'Structure';
    final bool expired = _isExpired(s);
    final bool isFree = s['cout'] != null && (s['cout'] == 0.0 || s['cout'] == 0);

    Color stateColor = isFree ? Colors.green : (expired ? Colors.red : Colors.blue);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: stateColor.withOpacity(0.15), width: 1),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              onTap: () async {
                final SharedPreferences prefs = await SharedPreferences.getInstance();

                final String currentId = (s['id'] ?? s['structureId'] ?? s['idStructure']).toString();
                final String currentName = s['nomStructure'] ?? 'Structure';
                final String currentCode = s['codeStructure'] ?? '';

                await prefs.setString('selected_structure_id', currentId);
                await prefs.setString('selected_structure_name', currentName);
                await prefs.setString('codeStructure', currentCode);

                debugPrint("⚙️ [Administration] ID=$currentId | Code=$currentCode");

                if (!context.mounted) return;

                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => StructureCategoriesScreen(structureId: currentId, structureName: currentName),
                  ),
                );
              },
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                leading: CircleAvatar(
                  radius: 24,
                  backgroundColor: stateColor.withOpacity(0.08),
                  child: Icon(isFree ? Icons.star_rounded : Icons.business_rounded, color: stateColor, size: 26),
                ),
                title: Text(name.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E293B), fontSize: 15, letterSpacing: 0.3)),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Text(
                    expired ? "EXPIRÉ" : "ACTIF",
                    style: TextStyle(color: expired ? Colors.red.shade600 : Colors.green.shade600, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
                trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
              ),
            ),
          ),
          const Divider(height: 1, thickness: 0.8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: () => _handleSubscriptionAction(s, expired),
                  icon: const Icon(Icons.autorenew_rounded, size: 18),
                  label: const Text("GÉRER", style: TextStyle(fontWeight: FontWeight.bold)),
                  style: TextButton.styleFrom(foregroundColor: const Color(0xFFFF9800)),
                ),
                TextButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text("EDIT", style: TextStyle(fontWeight: FontWeight.bold)),
                  style: TextButton.styleFrom(foregroundColor: Colors.blueGrey),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () {
                    _structureService.deleteStructure(id).then((_) => _checkNetworkAndLoad());
                  },
                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 22),
                  style: IconButton.styleFrom(foregroundColor: Colors.red.shade50),
                )
              ],
            ),
          )
        ],
      ),
    );
  }
}