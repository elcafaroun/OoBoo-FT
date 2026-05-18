import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  int get activeCount => users.where((u) => (u['active'] ?? u['isActive'] ?? false)).length;

  Future<void> _fetchUsers() async {
    setState(() => isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? structureId = prefs.getString('selected_structure_id');
      if (structureId != null) {
        final fetchedUsers = await _userService.getAllUsersByStructure(structureId);
        setState(() { users = fetchedUsers; isLoading = false; });
      } else {
        setState(() => isLoading = false);
      }
    } catch (e) {
      setState(() => isLoading = false);
    }
  }

  // --- UI BUILDER ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC), // Bleu-gris très clair, très moderne
      appBar: AppBar(
        title: const Text("Gestion des Agents", style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0.5,
        centerTitle: true,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.orange))
          : Column(
        children: [
          _buildModernHeader(),
          Expanded(
            child: users.isEmpty
                ? _buildEmptyState()
                : ListView.separated(
              padding: const EdgeInsets.all(16),
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemCount: users.length,
              itemBuilder: (context, index) => _buildAgentCard(users[index]),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterScreen(isFromLogin: false))).then((_) => _fetchUsers()),
        backgroundColor: const Color(0xFFFF9800),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text("Ajouter un agent", style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  // --- WIDGETS DÉDIÉS ---

  Widget _buildModernHeader() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
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
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 8),
        Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  Widget _buildAgentCard(dynamic user) {
    final bool isActive = user['active'] ?? user['isActive'] ?? false;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withOpacity(0.1)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: isActive ? Colors.orange.shade50 : Colors.grey.shade100,
          child: Text(user['userName']?[0] ?? "?", style: TextStyle(color: isActive ? Colors.orange : Colors.grey, fontWeight: FontWeight.bold)),
        ),
        title: Text(user['userName'] ?? "Inconnu", style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text("${user['userProfile']}", style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: (value) { /* Appelez ici vos fonctions de gestion (edit, reset, etc.) */ },
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'edit', child: Text("Modifier")),
            const PopupMenuItem(value: 'toggle', child: Text("Activer/Désactiver")),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.person_search, size: 80, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          const Text("Aucun agent enregistré", style: TextStyle(fontSize: 16, color: Colors.grey)),
        ],
      ),
    );
  }
}