import 'package:fada/services/database/database_helper.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/network_checker.dart';
import 'structures_screen.dart';
import 'stock_alert_screen.dart';
import 'login_screen.dart';
import '../services/sync_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Données utilisateur
  String? _userProfile;
  String? _userName;
  String? _codeStructure;
  String? _userId;

  // États de l'interface
  int _pendingSyncCount = 0;
  bool _isInitialSyncing = true;
  String _loadingMessage = "Initialisation de l'application...";

  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();

  @override
  void initState() {
    super.initState();
    _handleStartup();
  }

  /// Gère le chargement complet au démarrage (Sans blocage internet)
  Future<void> _handleStartup() async {
    setState(() {
      _isInitialSyncing = true;
      _loadingMessage = "Vérification de la connexion...";
    });

    final minimumWait = Future.delayed(const Duration(seconds: 2));

    try {
      // 1. Charger les préférences utilisateur
      await _loadUserProfile();

      // 2. Vérification de l'accès au serveur central 📡
      bool isServerOnline = await NetworkChecker.isBackendAccessible();

      if (isServerOnline) {
        if (_codeStructure != null && _userId != null) {
          setState(() => _loadingMessage = "Serveur en ligne !\nRafraîchissement des données...");
          await _syncService.refreshLocalData(_codeStructure!, _userId!);
        }
      } else {
        debugPrint("📡 Le serveur est injoignable. Mode hors-ligne activé automatiquement.");
      }

      // 3. Mettre à jour le compteur de la file d'attente locale
      await _refreshPendingCount();

    } catch (e, stacktrace) {
      debugPrint("🚨 Erreur lors du démarrage : $e");
      debugPrint(stacktrace.toString());
    } finally {
      await minimumWait;

      // ✅ STRATÉGIE OFF-LINE FIRST ACCÉLÉRÉE :
      // Qu'il y ait des données locales ou non, on libère l'accès à l'interface.
      if (mounted) {
        setState(() {
          _isInitialSyncing = false;
        });
      }
    }
  }

  Future<void> _loadUserProfile() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userProfile = prefs.getString('userProfile');
      _userName = prefs.getString('userName');
      _codeStructure = prefs.getString('codeStructure');
      _userId = prefs.getString('userId');
    });
  }

  Future<void> _refreshPendingCount() async {
    try {
      final db = await _dbHelper.database;
      final List<Map<String, dynamic>> res = await db.rawQuery(
          "SELECT COUNT(*) as count FROM sync_queue WHERE status = 'PENDING'"
      );
      if (mounted) {
        setState(() {
          _pendingSyncCount = res.first['count'] as int;
        });
      }
    } catch (e) {
      debugPrint("Erreur compteur sync_queue : $e");
    }
  }

  Future<void> _handleManualSync() async {
    _showSnackBar("Vérification de la liaison avec le serveur... 🌐", Colors.blueGrey);
    bool isServerOnline = await NetworkChecker.isBackendAccessible();

    if (!isServerOnline) {
      _showSnackBar("Impossible de joindre le serveur central. Réessayez plus tard. ❌", Colors.redAccent);
      return;
    }

    if (_codeStructure == null || _userId == null) {
      _showSnackBar("Informations de session manquantes.", Colors.redAccent);
      return;
    }

    _showSnackBar("Synchronisation complète en cours... 🔄", Colors.orange);

    try {
      await _syncService.fullSynchronization(_codeStructure!, _userId!);
      await _refreshPendingCount();
      if (mounted) {
        _showSnackBar("Synchronisation réussie ✅", Colors.green);
      }
    } catch (e) {
      _showSnackBar("Échec de la synchronisation : $e", Colors.redAccent);
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: color, duration: const Duration(seconds: 3))
    );
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
              (route) => false
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitialSyncing) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(30.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(color: Color(0xFFFF9800)),
                const SizedBox(height: 30),
                Text(_loadingMessage,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Colors.black87)),
                const SizedBox(height: 10),
                const Text("Préparation de votre espace de travail...",
                    style: TextStyle(fontSize: 12, color: Colors.grey))
              ],
            ),
          ),
        ),
      );
    }

    final bool isVente = _userProfile == "Vente";

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text("Tableau de bord", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        actions: [
          IconButton(
              onPressed: () => _showLogoutDialog(context),
              icon: const Icon(Icons.logout, color: Color(0xFFFF9800))
          ),
        ],
      ),
      body: RefreshIndicator(
        color: const Color(0xFFFF9800),
        onRefresh: () async {
          try {
            bool isServerOnline = await NetworkChecker.isBackendAccessible();
            if (isServerOnline && _codeStructure != null && _userId != null) {
              await _syncService.fullSynchronization(_codeStructure!, _userId!);
            } else if (!isServerOnline) {
              _showSnackBar("Mode hors-ligne : Impossible de rafraîchir depuis le serveur.", Colors.orange);
            }
          } catch (e) {
            debugPrint("Erreur lors du rafraîchissement : $e");
          }
          await _refreshPendingCount();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 30),
              const Text("MENU PRINCIPAL",
                  style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
              const SizedBox(height: 15),
              _buildMenuGrid(isVente),
              const SizedBox(height: 30),

            ],
          ),
        ),
      ),
    );
  }

  // --- COMPOSANTS UI DU TABLEAU DE BORD ---

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: const Color(0xFFFF9800),
          borderRadius: BorderRadius.circular(20)
      ),
      child: Row(
        children: [
          const CircleAvatar(
              radius: 30,
              backgroundColor: Colors.white24,
              child: Icon(Icons.person, size: 40, color: Colors.white)
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Bonjour, ${_userName ?? 'Utilisateur'}",
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                Text("Profil : ${_userProfile ?? 'Non défini'}",
                    style: const TextStyle(color: Colors.white70, fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuGrid(bool isVente) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
                child: _buildMenuCard(
                    title: "Commencer",
                    subtitle: "Mes structures",
                    icon: Icons.storefront_rounded,
                    color: Colors.orange,
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StructuresScreen())).then((_) => _refreshPendingCount())
                )
            ),
            const SizedBox(width: 15),
            Expanded(
                child: _buildMenuCard(
                    title: isVente ? "Restreint" : "Stocks",
                    subtitle: isVente ? "Admin requis" : "Gérer stocks",
                    icon: isVente ? Icons.lock_outline : Icons.notification_important_rounded,
                    color: isVente ? Colors.grey : Colors.redAccent,
                    onTap: isVente ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StockAlertScreen()))
                )
            ),
          ],
        ),
        const SizedBox(height: 15),
        Row(
          children: [
            Expanded(
                child: _buildMenuCard(
                    title: "Synchroniser",
                    subtitle: _pendingSyncCount > 0 ? "$_pendingSyncCount en attente" : "Données à jour",
                    icon: Icons.sync,
                    color: _pendingSyncCount > 0 ? Colors.deepOrange : Colors.blue,
                    onTap: _handleManualSync
                )
            ),
            const Spacer(),
          ],
        ),
      ],
    );
  }

  Widget _buildMenuCard({required String title, required String subtitle, required IconData icon, required Color color, VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 15),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      ),
    );
  }



  Widget _buildContactItem(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, color: Colors.orange, size: 20),
          const SizedBox(width: 15),
          Text("$label : ", style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(value, style: const TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
        context: context,
        builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            title: const Text("Déconnexion"),
            content: const Text("Voulez-vous vraiment quitter l'application ?"),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text("Annuler")),
              ElevatedButton(
                  onPressed: _logout,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                  child: const Text("Confirmer")
              )
            ]
        )
    );
  }
}