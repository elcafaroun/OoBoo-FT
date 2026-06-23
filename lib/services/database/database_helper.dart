import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';

class DatabaseHelper {

  static final DatabaseHelper _instance = DatabaseHelper._internal();

  static Database? _database;

  static const int _dbVersion = 3;

  factory DatabaseHelper() => _instance;

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDb();
    return _database!;

  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'c4us_master_online.db');

    debugPrint("📂 [DB INIT] Chemin physique : $path");

    return await openDatabase(
      path,
      version: 3,
      onCreate: (db, version) async {
        debugPrint("🆕 [DB INIT] Création de la base de données...");
        await _onCreate(db, version);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        debugPrint("🆙 [DB INIT] Mise à jour de la base de $oldVersion vers $newVersion...");
        await _onUpgrade(db, oldVersion, newVersion);
      },
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
        debugPrint("⚙️ [DB INIT] Clés étrangères activées.");
      },
    );
  }


  Future _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      try { await db.execute('ALTER TABLE structures ADD COLUMN endSub TEXT'); } catch (_) {}
    }
    if (oldVersion < 3) {
      try { await db.execute('ALTER TABLE users ADD COLUMN codeUser TEXT'); } catch (_) {}
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''CREATE TABLE users (id TEXT PRIMARY KEY, userName TEXT, userEmail TEXT, userPhone TEXT, userProfile TEXT, codeStructure TEXT, codeUser TEXT, isActive INTEGER, version INTEGER, updatedAt TEXT)''');
    await db.execute('''CREATE TABLE structures (id TEXT PRIMARY KEY, nomStructure TEXT, codeStructure TEXT, emailStructure TEXT, phone1Structure TEXT, villeStructure TEXT, endSub TEXT, isActive INTEGER, lastUpdated TEXT, photoPath TEXT, version INTEGER, createdUserId TEXT)''');
    await db.execute('CREATE INDEX idx_struct_user ON structures (createdUserId)');
    await db.execute('''CREATE TABLE categories (id TEXT PRIMARY KEY, nameCat TEXT, codeStructure TEXT, isActive INTEGER, lastUpdated TEXT, photoPath TEXT, version INTEGER, deleted INTEGER DEFAULT 0)''');
    await db.execute('''CREATE TABLE products (id TEXT PRIMARY KEY, productName TEXT, productPrice REAL, prixAchat REAL, productQte REAL, stockAlert REAL, codeStructure TEXT, categoryId TEXT, isActive INTEGER, lastUpdated TEXT, photoPath TEXT, version INTEGER, deleted INTEGER DEFAULT 0)''');
    await db.execute('''CREATE TABLE commands (id TEXT PRIMARY KEY, customerName TEXT, status TEXT, totalAmount REAL, totalCredit REAL, codeStructure TEXT, paymentMethod TEXT, orderDate TEXT, lastUpdated TEXT, version INTEGER, deleted INTEGER DEFAULT 0, isSynced INTEGER DEFAULT 0)''');
    await db.execute('''CREATE TABLE customers (id TEXT PRIMARY KEY, numCust TEXT, codePin TEXT, customerName TEXT, createdDate TEXT, version INTEGER)''');
    await db.execute('''CREATE TABLE command_lines (id TEXT PRIMARY KEY, commandId TEXT, productId TEXT, productName TEXT, quantity INTEGER, unitPrice REAL, codeStructure TEXT, FOREIGN KEY (commandId) REFERENCES commands (id) ON DELETE CASCADE)''');
    await db.execute('''CREATE TABLE user_structures (id TEXT PRIMARY KEY, user_id TEXT, structure_id TEXT, role_in_structure TEXT, deleted INTEGER DEFAULT 0, updated_at TEXT, FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE, FOREIGN KEY (structure_id) REFERENCES structures (id) ON DELETE CASCADE)''');
    await db.execute('''CREATE TABLE sync_queue (id INTEGER PRIMARY KEY AUTOINCREMENT, action TEXT, tableName TEXT, entityId TEXT, data TEXT, timestamp TEXT, status TEXT DEFAULT 'PENDING')''');
  }

  // --- 1. UTILISATEURS ---
  Future<void> saveOrUpdateUserLocal(Map<String, dynamic> userData) async {
    final db = await database;
    await db.insert('users', {
      'id': userData['id'], 'userName': userData['userName'], 'userEmail': userData['userEmail'],
      'userPhone': userData['userPhone'], 'userProfile': userData['userProfile'],
      'codeStructure': userData['codeStructure'], 'codeUser': userData['codeUser'],
      'isActive': userData['isActive'] == true ? 1 : 0, 'version': userData['version'] ?? 0,
      'updatedAt': userData['updatedAt'] ?? DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, dynamic>?> getUserByIdentifier(String identifier) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('users', where: 'userEmail = ? OR userName = ? OR userPhone = ?', whereArgs: [identifier, identifier, identifier]);
    return maps.isNotEmpty ? maps.first : null;
  }

  // --- 2. SYNCHRONISATION ---
  Future<void> syncStructuresLocal(List<dynamic> structures) async {
    final db = await database;
    Batch batch = db.batch();
    for (var s in structures) {
      batch.insert('structures', {
        'id': (s['idStructure'] ?? s['id'] ?? '').toString(),
        'nomStructure': s['nomStructure'] ?? 'Structure sans nom',
        'codeStructure': s['codeStructure'] ?? '',
        'emailStructure': s['emailStructure'],
        'phone1Structure': s['phone1Structure'],
        'villeStructure': s['villeStructure'],
        'endSub': s['endSub'],
        'isActive': _parseBool(s['isActive'] ?? s['active']),
        'lastUpdated': DateTime.now().toIso8601String(),
        'version': s['version'] ?? 0,
        'createdUserId': s['createdUserId']?.toString(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }
  Future<void> syncUserStructuresLocal(List<Map<String, dynamic>> userStructures) async {
    final db = await database;

    if (userStructures.isEmpty) {
      debugPrint("⚠️ Aucune donnée reçue pour syncUserStructuresLocal.");
      return;
    }

    // 1. Désactivation temporaire des contraintes de clés étrangères
    // Cela permet d'insérer le lien même si la structure n'est pas encore "vue" par SQLite
    await db.execute('PRAGMA foreign_keys = OFF');

    int insertedCount = 0;

    for (var us in userStructures) {
      try {
        final Map<String, dynamic> row = {
          'id': us['id']?.toString(),
          // Remplacez 'userId' par 'user_id' et 'structureId' par 'structure_id'
          'user_id': us['user_id']?.toString(),
          'structure_id': us['structure_id']?.toString(),
          'role_in_structure': us['role_in_structure'], // Vérifiez aussi le nom ici
          'updated_at': us['updated_at'] ?? DateTime.now().toIso8601String(),
        };

        await db.insert(
          'user_structures',
          row,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      } catch (e) {
        debugPrint("❌ ERREUR SQL : $e");
      }
    }

    // 4. Réactivation des contraintes
    await db.execute('PRAGMA foreign_keys = ON');

    // 5. Vérification finale du résultat
    final count = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM user_structures'));
    debugPrint("🚨 [DEBUG FINAL] Nombre de lignes réelles dans SQLite après sync : $count (Insérées : $insertedCount)");
  }

  Future<void> syncCategoriesLocal(List<dynamic> categories) async {
    final db = await database;
    Batch batch = db.batch();
    for (var cat in categories) {
      batch.insert('categories', {
        'id': cat['id'], 'nameCat': cat['nameCat'], 'codeStructure': cat['codeStructure'],
        'isActive': cat['isActive'] == true ? 1 : 0, 'lastUpdated': DateTime.now().toIso8601String(),
        'version': cat['version'] ?? 0, 'deleted': cat['deleted'] == true ? 1 : 0,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<void> syncProductsLocal(List<dynamic> products) async {
    final db = await database;
    Batch batch = db.batch();
    for (var p in products) {
      batch.insert('products', {
        'id': p['id'], 'productName': p['productName'], 'productPrice': p['productPrice'],
        'prixAchat': p['prixAchat'], 'productQte': p['productQte'], 'stockAlert': p['stockAlert'],
        'codeStructure': p['codeStructure'], 'categoryId': p['categoryId'], 'isActive': p['isActive'] == true ? 1 : 0,
        'lastUpdated': DateTime.now().toIso8601String(), 'version': p['version'] ?? 0, 'deleted': p['deleted'] == true ? 1 : 0,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<void> syncCommandsLocal(List<dynamic> commands) async {
    final db = await database;
    Batch batch = db.batch();
    for (var cmd in commands) {
      batch.insert('commands', {
        'id': cmd['id'], 'customerName': cmd['customerName'], 'status': cmd['status'],
        'totalAmount': cmd['totalAmount'], 'totalCredit': cmd['totalCredit'] ?? 0.0,
        'codeStructure': cmd['codeStructure'], 'paymentMethod': cmd['paymentMethod'],
        'orderDate': cmd['orderDate'], 'lastUpdated': cmd['lastUpdated'] ?? DateTime.now().toIso8601String(),
        'version': cmd['version'] ?? 0, 'deleted': cmd['deleted'] == 1 ? 1 : 0, 'isSynced': cmd['isSynced'] ?? 1
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      if (cmd['items'] != null) {
        batch.delete('command_lines', where: 'commandId = ?', whereArgs: [cmd['id']]);
        for (var item in cmd['items']) {
          batch.insert('command_lines', {
            'id': item['id'] ?? "ITEM_${DateTime.now().microsecondsSinceEpoch}",
            'commandId': cmd['id'], 'productId': item['productId'], 'productName': item['productName'],
            'quantity': item['quantity'], 'unitPrice': item['unitPrice'], 'codeStructure': item['codeStructure'] ?? cmd['codeStructure'],
          });
        }
      }
    }
    await batch.commit(noResult: true);
  }

  // --- 3. LECTURE (OFFLINE) ---
  Future<List<Map<String, dynamic>>> getLocalStructuresByUser(String userId) async {
    final db = await database;

    // 1. Voir ce qu'il y a VRAIMENT dans les tables
    final allStructs = await db.rawQuery('SELECT id FROM structures');
    final allLinks = await db.rawQuery('SELECT structure_id, user_id FROM user_structures');
    debugPrint("🔍 [DEBUG] Structures présentes : $allStructs");
    debugPrint("🔍 [DEBUG] Liens présents : $allLinks");

    // 2. Requête corrigée avec les bons noms de colonnes
    return await db.rawQuery('''
    SELECT s.* FROM structures s
    INNER JOIN user_structures us ON s.id = us.structure_id
    WHERE us.user_id = ?
  ''', [userId]);
  }

  Future<List<Map<String, dynamic>>> getLocalCategories() async {
    final db = await database;
    return await db.query('categories', orderBy: 'nameCat ASC');
  }

  Future<List<Map<String, dynamic>>> getLocalProducts() async {
    final db = await database;
    return await db.query('products', orderBy: 'productName ASC');
  }

  Future<List<Map<String, dynamic>>> getLocalEntities(String tableName, String codeStructure) async {
    final db = await database;
    return await db.query(tableName, where: 'codeStructure = ? AND (deleted = 0 OR deleted IS NULL)', whereArgs: [codeStructure]);
  }

  Future<List<Map<String, dynamic>>> getLocalCommands(String codeStructure) async {
    final db = await database;
    final List<Map<String, dynamic>> commandMaps = await db.query('commands', where: 'codeStructure = ? AND deleted = 0', whereArgs: [codeStructure], orderBy: 'orderDate DESC');
    List<Map<String, dynamic>> fullCommands = [];
    for (var cmdMap in commandMaps) {
      var mutableCmd = Map<String, dynamic>.from(cmdMap);
      final List<Map<String, dynamic>> items = await db.query('command_lines', where: 'commandId = ?', whereArgs: [cmdMap['id']]);
      mutableCmd['items'] = items;
      fullCommands.add(mutableCmd);
    }
    return fullCommands;
  }

  // --- 4. ACTIONS & SYNC QUEUE ---
  Future<void> updateProductStock(String productId, double quantitySold) async {
    final db = await database;
    await db.execute('UPDATE products SET productQte = productQte - ? WHERE id = ?', [quantitySold, productId]);
  }

  Future<void> updateEntityPhotoPath(String tableName, String id, String path) async {
    final db = await database;
    await db.update(tableName, {'photoPath': path}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> addToSyncQueue(String action, String tableName, String entityId, Map<String, dynamic> data) async {
    final db = await database;
    await db.insert('sync_queue', {
      'action': action, 'tableName': tableName, 'entityId': entityId,
      'data': jsonEncode(data), 'timestamp': DateTime.now().toIso8601String(),
    });
  }

  Future<void> removeFromSyncQueue(int id) async {
    final db = await database;
    await db.delete('sync_queue', where: 'id = ?', whereArgs: [id]);
  }

  // --- 5. CUSTOMERS ---
  Future<void> saveCustomerLocal(Map<String, dynamic> customer) async {
    final db = await database;
    await db.insert('customers', {
      'id': customer['id'], 'numCust': customer['numCust'], 'codePin': customer['codePin'],
      'customerName': customer['customerName'], 'createdDate': customer['createdDate'] ?? DateTime.now().toIso8601String(),
      'version': customer['version'] ?? 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, dynamic>?> getCustomerById(String id) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('customers', where: 'id = ?', whereArgs: [id]);
    return maps.isNotEmpty ? maps.first : null;
  }

  Future<void> deleteCustomerLocal(String id) async {
    final db = await database;
    await db.delete('customers', where: 'id = ?', whereArgs: [id]);
  }

  Future<Map<String, dynamic>?> getProductById(String id) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('products', where: 'id = ?', whereArgs: [id], limit: 1);
    return maps.isNotEmpty ? maps.first : null;
  }

  Future<void> updateCustomerCodePinOffline(String userId, String newCode) async {
    final db = await database;
    await db.update('customers', {'codePin': newCode}, where: 'id = ?', whereArgs: [userId]);
    await addToSyncQueue('UPDATE_PASSWORD', 'customers', userId, {'newPassword': newCode});
  }

  int _parseBool(dynamic value) {
    if (value == null) return 0;
    if (value is bool) return value ? 1 : 0;
    if (value is String) return (value.toLowerCase() == 'true' || value == '1') ? 1 : 0;
    if (value is int) return value == 1 ? 1 : 0;
    return 0;
  }

  Future<List<Map<String, dynamic>>> getCategoriesByStructureLocal(String structureId) async {
    final db = await database;
    return await db.query('categories', where: 'codeStructure = ?', whereArgs: [structureId]);
  }

  Future<List<Map<String, dynamic>>> getProductsByStructureLocal(String structureId) async {
    final db = await database;
    return await db.query('products', where: 'codeStructure = ?', whereArgs: [structureId]);
  }
}