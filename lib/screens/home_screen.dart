import 'package:fada/services/database/database_helper.dart';
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

class _HomeScreenState extends State<HomeScreen> {
  String? _userName;
  String? _userProfile;
  String? _codeStructure;
  String? _userId;

  int _pendingSyncCount = 0;
  bool _isInitialSyncing = true;

  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();

  @override
  void initState() {
    super.initState(); // ✅ FIX : Syntaxe nettoyée ici
    _handleStartup();
  }

  Future<void> _handleStartup() async {
    setState(() => _isInitialSyncing = true);
    try {
      await _loadUserProfile();
      await _refreshPendingCount();

      if (_userId != null && _userId!.isNotEmpty) {
        if (await NetworkChecker.isBackendAccessible()) {
          await _syncService.fullSynchronization(_codeStructure ?? "", _userId!);
          await _refreshPendingCount();
        } else {
          // 🛰️ CAS HORS-LIGNE : Le serveur n'est pas joignable au démarrage
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showSnackBar(
                "Mode hors-ligne actif 🛰️. Les données locales seront utilisées.",
                Colors.blueGrey
            );
          });
        }

        final db = await _dbHelper.database;
        final catCount = Sqflite.firstIntValue(await db.rawQuery("SELECT COUNT(*) FROM categories"));
        final prodCount = Sqflite.firstIntValue(await db.rawQuery("SELECT COUNT(*) FROM products"));

        debugPrint("🔍 [DB CHECK] Catégories trouvées : $catCount, Produits trouvés : $prodCount");
      }
    } catch (e) {
      debugPrint("❌ Erreur démarrage : $e");
    } finally {
      if (mounted) setState(() => _isInitialSyncing = false);
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
      final res = await db.rawQuery("SELECT COUNT(*) as count FROM sync_queue WHERE status = 'PENDING'");
      if (mounted) setState(() => _pendingSyncCount = res.first['count'] as int);
    } catch (e) {
      debugPrint("Erreur sync_queue : $e");
    }
  }

  Future<void> _handleManualSync() async {
    // 1️⃣ Vérification immédiate de la connexion
    bool online = await NetworkChecker.isBackendAccessible();

    if (!online) {
      _showSnackBar(
          "Impossible de synchroniser : aucune connexion au serveur ❌",
          Colors.redAccent
      );
      return; // On arrête l'exécution ici
    }

    // 2️⃣ Si la connexion est bonne, on procède à la synchro
    _showSnackBar("Synchronisation en cours...", Colors.orange);
    try {
      await _syncService.fullSynchronization(_codeStructure ?? "", _userId!);
      await _refreshPendingCount();
      if (mounted) _showSnackBar("Synchronisation réussie ✅", Colors.green);
    } catch (e) {
      _showSnackBar("Échec de la synchronisation : $e", Colors.redAccent);
    }
  }

  void _showChangePasswordDialog() {
    final _formKey = GlobalKey<FormState>();
    final TextEditingController _newPassController = TextEditingController();
    final TextEditingController _confirmPassController = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.purple.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.lock_reset_rounded, color: Colors.purple),
            ),
            const SizedBox(width: 12),
            const Text("Sécurité PIN", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          ],
        ),
        content: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                  "Le code sera enregistré localement et synchronisé automatiquement dès le retour du réseau.",
                  style: TextStyle(fontSize: 12, color: Colors.grey, height: 1.4)
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _newPassController,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 4,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
                decoration: InputDecoration(
                  labelText: "Nouveau code (4 chiffres)",
                  prefixIcon: const Icon(Icons.lock_outline, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  counterText: "",
                ),
                validator: (v) => (v == null || v.length < 4) ? "4 chiffres requis" : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _confirmPassController,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 4,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
                decoration: InputDecoration(
                  labelText: "Confirmer le code",
                  prefixIcon: const Icon(Icons.gpp_good_outlined, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  counterText: "",
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return "Confirmation requise";
                  if (v != _newPassController.text) return "Les codes ne correspondent pas";
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Annuler", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF9800),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
            ),
            onPressed: () async {
              if (_formKey.currentState!.validate()) {
                try {
                  await _dbHelper.updateCustomerCodePinOffline(_userId!, _newPassController.text);
                  await _refreshPendingCount();

                  if (mounted) {
                    Navigator.pop(context);
                    _showSnackBar("Code enregistré ! Reconnexion requise. ✅", Colors.green);
                    await _logout();
                  }
                } catch (e) {
                  if (mounted) _showSnackBar("Erreur lors de l'enregistrement : $e", Colors.red);
                }
              }
            },
            child: const Text("ENREGISTRER", style: TextStyle(fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: color));
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
            (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitialSyncing) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: Color(0xFFFF9800))));
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text("TABLEAU DE BORD", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [IconButton(icon: const Icon(Icons.logout), onPressed: () => _logout())],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 30),
              _buildMenuGrid(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: const Color(0xFFFF9800), borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: [
          const CircleAvatar(radius: 30, backgroundColor: Colors.white24, child: Icon(Icons.person, size: 40, color: Colors.white)),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Bonjour, ${_userName ?? 'Utilisateur'}", style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                Text("Profil : ${_userProfile ?? 'Non défini'}", style: const TextStyle(color: Colors.white70), overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuGrid() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _buildMenuCard("Commencer", "Mes structures", Icons.storefront_rounded, Colors.orange, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StructuresScreen())))),
            const SizedBox(width: 15),
            Expanded(child: _buildMenuCard("Sécurité", "Code PIN", Icons.lock_outline, Colors.purple, _showChangePasswordDialog)),
          ],
        ),
        const SizedBox(height: 15),
        Row(
          children: [
            Expanded(child: _buildMenuCard("Sync", _pendingSyncCount > 0 ? "$_pendingSyncCount en attente" : "À jour", Icons.sync, Colors.blue, _handleManualSync)),
            const SizedBox(width: 15),
            // ✅ FIX : Remplacement du Spacer() par un conteneur vide flexible pour équilibrer la grille de rendu
            const Expanded(child: SizedBox.shrink()),
          ],
        ),
      ],
    );
  }

  Widget _buildMenuCard(String title, String subtitle, IconData icon, Color color, VoidCallback onTap) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: color.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4))]),
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
                Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: color, size: 24)),
                const SizedBox(height: 15),
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(subtitle, style: TextStyle(color: Colors.grey.shade600, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ),
      ),
    );
  }
}