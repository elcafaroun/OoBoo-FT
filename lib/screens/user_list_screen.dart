import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../services/user_service.dart';
import 'register_screen.dart';

class UserListScreen extends StatefulWidget {
  const UserListScreen({super.key});

  @override
  State<UserListScreen> createState() => _UserListScreenState();
}

class _UserListScreenState extends State<UserListScreen> {
  final UserService _userService = UserService();
  List<dynamic> users = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchUsers();
  }

  int get activeCount => users.where((u) {
    final dynamic activeField = u['active'] ?? u['isActive'];
    return activeField == true || activeField == 1 || activeField.toString().toLowerCase() == 'true';
  }).length;

  Future<void> _fetchUsers() async {
    if (!mounted) return;
    setState(() => isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final String? structureId = prefs.getString('selected_structure_id') ?? prefs.getString('codeStructure');

      if (structureId != null && structureId.isNotEmpty) {
        final fetchedUsers = await _userService.getAllUsersByStructure(structureId);
        if (mounted) {
          setState(() {
            users = fetchedUsers ?? [];
            isLoading = false;
          });
        }
      } else {
        if (mounted) setState(() => isLoading = false);
      }
    } catch (e) {
      debugPrint("❌ Erreur : $e");
      if (mounted) setState(() => isLoading = false);
    }
  }

  // Méthode utilitaire pour formater la date venant de l'API
  String _formatSyncDate(dynamic syncDate) {
    if (syncDate == null) return "Jamais";
    try {
      DateTime dateTime = DateTime.parse(syncDate.toString());
      return DateFormat('dd/MM à HH:mm').format(dateTime);
    } catch (e) {
      return "Date invalide";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text("Gestion des Agents", style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0.5,
        centerTitle: true,
        actions: [IconButton(icon: const Icon(Icons.refresh, color: Colors.orange), onPressed: _fetchUsers)],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.orange))
          : Column(
        children: [
          _buildModernHeader(),
          Expanded(
            child: users.isEmpty
                ? _buildEmptyState()
                : RefreshIndicator(
              onRefresh: _fetchUsers,
              color: Colors.orange,
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemCount: users.length,
                itemBuilder: (context, index) => _buildAgentCard(users[index]),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterScreen(isFromLogin: false))).then((_) => _fetchUsers()),
        backgroundColor: const Color(0xFFFF9800),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text("Ajouter un agent", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
      ),
    );
  }

  Widget _buildModernHeader() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))]),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _statTile("Total", "${users.length}", Icons.people_outline, Colors.blueGrey),
          Container(width: 1, height: 40, color: Colors.grey.shade200),
          _statTile("Actifs", "$activeCount", Icons.check_circle_outline, Colors.green),
        ],
      ),
    );
  }

  Widget _statTile(String label, String value, IconData icon, Color color) {
    return Column(children: [Icon(icon, color: color, size: 24), const SizedBox(height: 8), Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey))]);
  }

  Widget _buildAgentCard(dynamic user) {
    final dynamic activeField = user['active'] ?? user['isActive'];
    final bool isActive = activeField == true || activeField == 1 || activeField.toString().toLowerCase() == 'true';
    final String displayName = user['userName'] ?? user['name'] ?? "Agent sans nom";
    final String displayProfile = user['userProfile'] ?? user['profile'] ?? "Vente";

    // Récupération de la date depuis l'objet user (backend)
    final String lastSync = _formatSyncDate(user['lastSyncDate']);

    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.withOpacity(0.1))),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(backgroundColor: isActive ? Colors.orange.shade50 : Colors.grey.shade100, child: Text(displayName[0].toUpperCase(), style: TextStyle(color: isActive ? Colors.orange : Colors.grey, fontWeight: FontWeight.bold))),
        title: Text(displayName, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(displayProfile, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
            Text("Synchro : $lastSync", style: const TextStyle(fontSize: 10, color: Colors.blueGrey, fontStyle: FontStyle.italic)),
          ],
        ),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: (value) async {
            if (value == 'edit') {
              // Action de modification (Rediriger par exemple vers l'écran Register en mode édition)
              // Navigator.push(context, MaterialPageRoute(builder: (_) => RegisterScreen(user: user, isFromLogin: false))).then((_) => _fetchUsers());
            } else if (value == 'toggle') {
              await _userService.toggleUserStatus(user['id'], !isActive);
              _fetchUsers();
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'edit',
              child: Row(
                children: [
                  Icon(Icons.edit, color: Colors.blue, size: 20),
                  SizedBox(width: 8),
                  Text("Modifier"),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'toggle',
              child: Row(
                children: [
                  Icon(
                      isActive ? Icons.block : Icons.check_circle_outline,
                      color: isActive ? Colors.red : Colors.green,
                      size: 20
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isActive ? "Désactiver l'agent" : "Activer l'agent",
                    style: TextStyle(color: isActive ? Colors.red : Colors.green),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.person_search, size: 80, color: Colors.grey.shade300), const Text("Aucun agent trouvé", style: TextStyle(color: Colors.grey))]));
}