import 'package:pokiboo/services/database/database_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import '../services/network_checker.dart';
import 'structures_screen.dart';
import 'login_screen.dart';
import '../services/sync_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  String? _userName;
  String? _userProfile;
  String? _codeStructure;
  String? _idStructure;
  String? _userId;

  String _lastSyncDateLabel = "Jamais";

  int _pendingSyncCount = 0;
  bool _isInitialSyncing = true;

  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _handleStartup();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshPendingCount();
    }
  }

  /// Affichage de la modale bloquante de synchronisation
  void _showSyncProgressDialog({required String title, required String message}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false, // Bloque le retour arrière physique sur Android
        child: Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: Color(0xFFFF9800)),
                const SizedBox(height: 20),
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleStartup() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? savedUserId = prefs.getString('userId');

      if (savedUserId != null && savedUserId.isNotEmpty) {
        // 1. Charger d'abord les données locales
        await _loadUserProfile();

        if (mounted) setState(() => _isInitialSyncing = false);

        // 2. Vérification première connexion & réseau
        if (await NetworkChecker.isBackendAccessible()) {
          final bool isFirstLoginDone = await _dbHelper.getSettingBool(
              'first_login_completed', defaultValue: false);

          if (!isFirstLoginDone) {
            debugPrint("🚀 Première connexion détectée, ouverture du popup de synchro...");

            // Attendre la fin du premier frame pour afficher le dialog en toute sécurité
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              if (!mounted) return;

              _showSyncProgressDialog(
                title: "Initialisation en cours...",
                message: "Téléchargement initial des données de votre compte. Veuillez patienter.",
              );

              try {
                await _syncService.fullSynchronization(savedUserId);
                await _dbHelper.setSettingBool('first_login_completed', true);
                await _loadUserProfile();
                await _loadLastSyncDate();
                await _refreshPendingCount();

                if (mounted) {
                  Navigator.pop(context); // Fermeture du dialog
                  _showSnackBar("Initialisation réussie ✅", Colors.green);
                }
              } catch (e) {
                if (mounted) {
                  Navigator.pop(context); // Fermeture du dialog en cas d'erreur
                  _showSnackBar("Erreur lors de l'initialisation : $e", Colors.redAccent);
                }
              }
            });
          } else {
            debugPrint(" Initialisation déjà effectuée précédemment.");
            await _loadLastSyncDate();
            await _refreshPendingCount();
          }
        }
      } else {
        if (mounted) setState(() => _isInitialSyncing = false);
      }
    } catch (e) {
      debugPrint("❌ Erreur démarrage : $e");
      if (mounted) setState(() => _isInitialSyncing = false);
    }
  }

  Future<void> _loadLastSyncDate() async {
    final prefs = await SharedPreferences.getInstance();
    final String? lastSync = prefs.getString('last_sync_date');
    if (lastSync != null) {
      DateTime dt = DateTime.parse(lastSync);
      setState(() {
        _lastSyncDateLabel =
        "${dt.day}/${dt.month} à ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}";
      });
    }
  }

  Future<void> _loadUserProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final String? userId = prefs.getString('userId');

    if (userId != null) {
      final userMap = await _dbHelper.getActiveUserLocal(userId);

      if (userMap != null) {
        setState(() {
          _userId = userId;
          _userName = userMap['userName'];
          _userProfile = userMap['userProfile'];
          _codeStructure = userMap['codeStructure'];
          _idStructure = userMap['idStructure']?.toString() ??
              userMap['structureId']?.toString();

          final String? lastSync = userMap['updatedAt'];
          if (lastSync != null) {
            DateTime dt = DateTime.parse(lastSync);
            _lastSyncDateLabel =
            "${dt.day}/${dt.month} à ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}";
          }
        });
      }
    }
  }

  Future<void> _refreshPendingCount() async {
    try {
      final db = await _dbHelper.database;
      final res = await db.rawQuery(
          "SELECT COUNT(*) as count FROM sync_queue WHERE status = 'PENDING'");
      if (mounted) setState(() => _pendingSyncCount = res.first['count'] as int);
    } catch (e) {
      debugPrint("Erreur sync_queue : $e");
    }
  }

  /// Synchronisation manuelle via le bouton Dashboard
  Future<void> _handleManualSync() async {
    bool online = await NetworkChecker.isBackendAccessible();
    if (!online) {
      _showSnackBar("Aucune connexion au serveur ❌", Colors.redAccent);
      return;
    }

    _showSyncProgressDialog(
      title: "Synchronisation en cours...",
      message: "Mise à jour des données locales avec le serveur.",
    );

    try {
      await _syncService.fullSynchronization(_userId ?? "");

      await _refreshPendingCount();
      await _loadUserProfile();
      await _loadLastSyncDate();

      if (mounted) {
        Navigator.pop(context);
        _showSnackBar("Synchronisation réussie ✅", Colors.green);
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        _showSnackBar("Échec de la synchronisation : $e", Colors.redAccent);
      }
    }
  }

  void _showChangePasswordDialog() {
    final formKey = GlobalKey<FormState>();
    final newPassController = TextEditingController();
    final confirmPassController = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text("Sécurité PIN"),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                  controller: newPassController,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  decoration: const InputDecoration(labelText: "Nouveau code")),
              TextFormField(
                  controller: confirmPassController,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  decoration: const InputDecoration(labelText: "Confirmer")),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Annuler")),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                await _dbHelper.updateCustomerCodePinOffline(
                    _userId!, newPassController.text);
                if (mounted) {
                  Navigator.pop(context);
                  _logout();
                }
              }
            },
            child: const Text("ENREGISTRER"),
          )
        ],
      ),
    );
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
  }

  Future<void> _logout() async {
    if (mounted) {
      Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
              (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitialSyncing) {
      return const Scaffold(
          body: Center(
              child: CircularProgressIndicator(color: Color(0xFFFF9800))));
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text("TABLEAU DE BORD",
            style: TextStyle(fontWeight: FontWeight.w900)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout)
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
              children: [_buildHeader(), const SizedBox(height: 30), _buildMenuGrid()]),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: const Color(0xFFFF9800),
          borderRadius: BorderRadius.circular(20)),
      child: Row(children: [
        const CircleAvatar(
            radius: 30,
            backgroundColor: Colors.white24,
            child: Icon(Icons.person, size: 40, color: Colors.white)),
        const SizedBox(width: 15),
        Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Bonjour, ${_userName ?? 'Utilisateur'}",
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                  Text("Profil : ${_userProfile ?? 'Non défini'}",
                      style: const TextStyle(color: Colors.white70))
                ])),
      ]),
    );
  }

  Widget _buildMenuGrid() {
    return Column(children: [
      Row(children: [
        Expanded(
            child: _buildMenuCard(
                "Commencer",
                "Mes structures",
                Icons.storefront_rounded,
                Colors.orange,
                    () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const StructuresScreen()))
                    .then((_) => _refreshPendingCount()))),
        const SizedBox(width: 15),
        Expanded(
            child: _buildMenuCard("Sécurité", "Code PIN", Icons.lock_outline,
                Colors.purple, _showChangePasswordDialog)),
      ]),
      const SizedBox(height: 15),
      Row(children: [
        Expanded(
            child: _buildMenuCard(
                "Sync",
                _pendingSyncCount > 0
                    ? "$_pendingSyncCount en attente"
                    : "Dernière : $_lastSyncDateLabel",
                Icons.sync,
                Colors.blue,
                _handleManualSync)),
        const SizedBox(width: 15),
        const Expanded(child: SizedBox.shrink()),
      ]),
    ]);
  }

  Widget _buildMenuCard(
      String title, String subtitle, IconData icon, Color color, VoidCallback onTap) {
    return Container(
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: color.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, 4))
          ]),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                          color: color.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12)),
                      child: Icon(icon, color: color, size: 24)),
                  const SizedBox(height: 15),
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 16)),
                  Text(subtitle,
                      style: TextStyle(
                          color: Colors.grey.shade600, fontSize: 12)),
                ]),
          ),
        ),
      ),
    );
  }
}