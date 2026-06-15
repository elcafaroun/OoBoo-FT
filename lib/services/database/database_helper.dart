import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;

  // Version 3 : Ajout du support de la colonne codeUser pour l'alignement des agents
  static const int _dbVersion = 3;

  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDb();
    return _database!;
  }

  Future<Database> _initDb() async {
    String path = join(await getDatabasesPath(), 'c4us_master_online.db');
    return await openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: _onConfigure,
    );
  }

  Future _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Évolution vers version 2 (Gérée historiquement)
    if (oldVersion < 2) {
      try {
        await db.execute('ALTER TABLE structures ADD COLUMN endSub TEXT');
        debugPrint("✅ Migration : Colonne endSub ajoutée.");
      } catch (e) {
        debugPrint("⚠️ Migration endSub ignorée : $e");
      }
    }

    // Évolution vers version 3 (Ajout de codeUser sans casser l'historique)
    if (oldVersion < 3) {
      try {
        await db.execute('ALTER TABLE users ADD COLUMN codeUser TEXT');
        debugPrint("✅ Migration : Colonne codeUser ajoutée à la table users.");
      } catch (e) {
        debugPrint("⚠️ Migration codeUser ignorée : $e");
      }
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    // --- TABLE UTILISATEURS ---
    await db.execute('''
      CREATE TABLE users (
        id TEXT PRIMARY KEY,
        userName TEXT,
        userEmail TEXT,
        userPhone TEXT,
        userProfile TEXT,
        codeStructure TEXT,
        codeUser TEXT, -- ✅ Ajouté dans le script de création initiale de la V3
        isActive INTEGER,
        version INTEGER,
        updatedAt TEXT
      )
    ''');

    // --- TABLE STRUCTURES ---
    await db.execute('''
      CREATE TABLE structures (
        id TEXT PRIMARY KEY,
        nomStructure TEXT,
        codeStructure TEXT,
        emailStructure TEXT,
        phone1Structure TEXT,
        villeStructure TEXT,
        endSub TEXT,
        isActive INTEGER,
        lastUpdated TEXT,
        photoPath TEXT,
        version INTEGER,
        createdUserId TEXT
      )
    ''');
    await db.execute('CREATE INDEX idx_struct_user ON structures (createdUserId)');

    // --- TABLE CATÉGORIES ---
    await db.execute('''
      CREATE TABLE categories (
        id TEXT PRIMARY KEY,
        nameCat TEXT,
        codeStructure TEXT,
        isActive INTEGER,
        lastUpdated TEXT,
        photoPath TEXT,
        version INTEGER,
        deleted INTEGER DEFAULT 0
      )
    ''');

    // --- TABLE PRODUITS ---
    await db.execute('''
      CREATE TABLE products (
        id TEXT PRIMARY KEY,
        productName TEXT,
        productPrice REAL,
        prixAchat REAL,
        productQte REAL,
        stockAlert REAL,
        codeStructure TEXT,
        categoryId TEXT,
        isActive INTEGER,
        lastUpdated TEXT,
        photoPath TEXT,
        version INTEGER,
        deleted INTEGER DEFAULT 0
      )
    ''');

    // --- TABLE COMMANDES ---
    await db.execute('''
      CREATE TABLE commands (
        id TEXT PRIMARY KEY,
        customerName TEXT,
        status TEXT,
        totalAmount REAL,
        totalCredit REAL,
        codeStructure TEXT,
        paymentMethod TEXT,
        orderDate TEXT,
        lastUpdated TEXT,
        version INTEGER,
        deleted INTEGER DEFAULT 0,
        isSynced INTEGER DEFAULT 0
      )
    ''');

    // --- TABLE CUSTOMERS ---
    await db.execute('''
      CREATE TABLE customers (
        id TEXT PRIMARY KEY,
        numCust TEXT,
        codePin TEXT,
        customerName TEXT,
        createdDate TEXT,
        version INTEGER
      )
    ''');

    // --- TABLE LIGNES DE COMMANDE ---
    await db.execute('''
      CREATE TABLE command_lines (
        id TEXT PRIMARY KEY,
        commandId TEXT,
        productId TEXT,
        productName TEXT,
        quantity INTEGER,
        unitPrice REAL,
        codeStructure TEXT,
        FOREIGN KEY (commandId) REFERENCES commands (id) ON DELETE CASCADE
      )
    ''');

    // --- TABLE SYNC QUEUE ---
    await db.execute('''
      CREATE TABLE sync_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        action TEXT,          
        tableName TEXT,       
        entityId TEXT,        
        data TEXT,            
        timestamp TEXT,
        status TEXT DEFAULT 'PENDING'
      )
    ''');
  }

  // ======================================================
  // 1. MÉTHODES UTILISATEURS
  // ======================================================

  Future<void> saveOrUpdateUserLocal(Map<String, dynamic> userData) async {
    final db = await database;
    await db.insert('users', {
      'id': userData['id'],
      'userName': userData['userName'],
      'userEmail': userData['userEmail'],
      'userPhone': userData['userPhone'],
      'userProfile': userData['userProfile'],
      'codeStructure': userData['codeStructure'],
      'codeUser': userData['codeUser'], // ✅ Persistance de la nouvelle propriété récupérée de l'API
      'isActive': userData['isActive'] == true ? 1 : 0,
      'version': userData['version'] ?? 0,
      'updatedAt': userData['updatedAt'] ?? DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, dynamic>?> getUserByIdentifier(String identifier) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'users',
      where: 'userEmail = ? OR userName = ? OR userPhone = ?',
      whereArgs: [identifier, identifier, identifier],
    );
    return maps.isNotEmpty ? maps.first : null;
  }

  // ======================================================
  // 2. MÉTHODES DE SYNCHRONISATION (MAJ CACHE)
  // ======================================================

  Future<void> syncStructuresLocal(List<dynamic> structures) async {
    final db = await database;
    Batch batch = db.batch();
    for (var s in structures) {
      batch.insert('structures', {
        'id': s['idStructure']?.toString() ?? s['id']?.toString(),
        'nomStructure': s['nomStructure'],
        'codeStructure': s['codeStructure'],
        'emailStructure': s['emailStructure'],
        'phone1Structure': s['phone1Structure'],
        'villeStructure': s['villeStructure'],
        'endSub': s['endSub'],
        'isActive': (s['isActive'] == true || s['active'] == true) ? 1 : 0,
        'lastUpdated': DateTime.now().toIso8601String(),
        'version': s['version'] ?? 0,
        'createdUserId': s['createdUserId'],
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<void> syncCategoriesLocal(List<dynamic> categories) async {
    final db = await database;
    Batch batch = db.batch();
    for (var cat in categories) {
      batch.insert('categories', {
        'id': cat['id'],
        'nameCat': cat['nameCat'],
        'codeStructure': cat['codeStructure'],
        'isActive': cat['isActive'] == true ? 1 : 0,
        'lastUpdated': DateTime.now().toIso8601String(),
        'version': cat['version'] ?? 0,
        'deleted': cat['deleted'] == true ? 1 : 0,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<void> syncProductsLocal(List<dynamic> products) async {
    final db = await database;
    Batch batch = db.batch();
    for (var p in products) {
      batch.insert('products', {
        'id': p['id'],
        'productName': p['productName'],
        'productPrice': p['productPrice'],
        'prixAchat': p['prixAchat'],
        'productQte': p['productQte'],
        'stockAlert': p['stockAlert'],
        'codeStructure': p['codeStructure'],
        'categoryId': p['categoryId'],
        'isActive': p['isActive'] == true ? 1 : 0,
        'lastUpdated': DateTime.now().toIso8601String(),
        'version': p['version'] ?? 0,
        'deleted': p['deleted'] == true ? 1 : 0,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<void> syncCommandsLocal(List<dynamic> commands) async {
    final db = await database;
    Batch batch = db.batch();
    for (var cmd in commands) {
      batch.insert('commands', {
        'id': cmd['id'],
        'customerName': cmd['customerName'],
        'status': cmd['status'],
        'totalAmount': cmd['totalAmount'],
        'totalCredit': cmd['totalCredit'] ?? 0.0,
        'codeStructure': cmd['codeStructure'],
        'paymentMethod': cmd['paymentMethod'],
        'orderDate': cmd['orderDate'],
        'lastUpdated': cmd['lastUpdated'] ?? DateTime.now().toIso8601String(),
        'version': cmd['version'] ?? 0,
        'deleted': cmd['deleted'] == 1 ? 1 : 0,
        'isSynced': cmd['isSynced'] ?? 1
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      if (cmd['items'] != null) {
        batch.delete('command_lines', where: 'commandId = ?', whereArgs: [cmd['id']]);
        for (var item in cmd['items']) {
          batch.insert('command_lines', {
            'id': item['id'] ?? "ITEM_${DateTime.now().microsecondsSinceEpoch}",
            'commandId': cmd['id'],
            'productId': item['productId'],
            'productName': item['productName'],
            'quantity': item['quantity'],
            'unitPrice': item['unitPrice'],
            'codeStructure': item['codeStructure'] ?? cmd['codeStructure'],
          });
        }
      }
    }
    await batch.commit(noResult: true);
  }

  // ======================================================
  // 3. RÉCUPÉRATION ET LECTURE (OFFLINE)
  // ======================================================

  Future<List<Map<String, dynamic>>> getLocalStructuresByUser(String userId) async {
    final db = await database;
    final String cleanUserId = userId.trim().toLowerCase();

    debugPrint("🚀 [DEBUG OFFLINE] Recherche pour : '$cleanUserId'");

    // 1. On vérifie d'abord si la table contient QUOI QUE CE SOIT
    final allData = await db.query('structures');
    if (allData.isEmpty) {
      debugPrint("❌ [DEBUG] La table 'structures' est COMPLÈTEMENT VIDE en local.");
      return [];
    } else {
      debugPrint("📊 [DEBUG] Nombre total de lignes dans SQLite : ${allData.length}");
      debugPrint("📝 [DEBUG] Format 1ère ligne : ID=${allData.first['id']}, User=${allData.first['createdUserId']}, Active=${allData.first['isActive']}");
    }

    // 2. On tente la requête avec le filtre
    final List<Map<String, dynamic>> result = await db.query(
      'structures',
      where: 'LOWER(createdUserId) = ? AND isActive = 1',
      whereArgs: [cleanUserId],
    );

    if (result.isEmpty) {
      debugPrint("⚠️ [DEBUG] Aucun match trouvé pour User: '$cleanUserId' avec isActive=1");

      // Test de secours : est-ce que l'ID existe mais isActive est à 0 ?
      final idCheck = await db.query(
        'structures',
        where: 'LOWER(createdUserId) = ?',
        whereArgs: [cleanUserId],
      );

      if (idCheck.isNotEmpty) {
        debugPrint("💡 [DEBUG] L'ID existe (${idCheck.length} fois) mais isActive est à 0 dans SQLite !");
      } else {
        debugPrint("🕵️ [DEBUG] L'ID '$cleanUserId' n'existe dans aucune ligne de la base.");
      }
    } else {
      debugPrint("✅ [DEBUG] Succès : ${result.length} structures trouvées en local.");
    }

    return result;
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
    return await db.query(
        tableName,
        where: 'codeStructure = ? AND (deleted = 0 OR deleted IS NULL)',
        whereArgs: [codeStructure]
    );
  }

  Future<List<Map<String, dynamic>>> getLocalCommands(String codeStructure) async {
    final db = await database;
    final List<Map<String, dynamic>> commandMaps = await db.query(
        'commands',
        where: 'codeStructure = ? AND deleted = 0',
        whereArgs: [codeStructure],
        orderBy: 'orderDate DESC'
    );

    List<Map<String, dynamic>> fullCommands = [];
    for (var cmdMap in commandMaps) {
      var mutableCmd = Map<String, dynamic>.from(cmdMap);
      final List<Map<String, dynamic>> items = await db.query(
          'command_lines',
          where: 'commandId = ?',
          whereArgs: [cmdMap['id']]
      );
      mutableCmd['items'] = items;
      fullCommands.add(mutableCmd);
    }
    return fullCommands;
  }

  // ======================================================
  // 4. ACTIONS ET MISES À JOUR
  // ======================================================

  Future<void> updateProductStock(String productId, double quantitySold) async {
    final db = await database;
    await db.execute(
        'UPDATE products SET productQte = productQte - ? WHERE id = ?',
        [quantitySold, productId]
    );
  }

  Future<void> updateEntityPhotoPath(String tableName, String id, String path) async {
    final db = await database;
    await db.update(tableName, {'photoPath': path}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> addToSyncQueue(String action, String tableName, String entityId, Map<String, dynamic> data) async {
    final db = await database;
    await db.insert('sync_queue', {
      'action': action,
      'tableName': tableName,
      'entityId': entityId,
      'data': jsonEncode(data),
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  Future<void> removeFromSyncQueue(int id) async {
    final db = await database;
    await db.delete('sync_queue', where: 'id = ?', whereArgs: [id]);
  }

  // ======================================================
  // 5. CLIENTS (CUSTOMERS)
  // ======================================================

  Future<void> saveCustomerLocal(Map<String, dynamic> customer) async {
    final db = await database;
    await db.insert('customers', {
      'id': customer['id'],
      'numCust': customer['numCust'],
      'codePin': customer['codePin'],
      'customerName': customer['customerName'],
      'createdDate': customer['createdDate'] ?? DateTime.now().toIso8601String(),
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
    final List<Map<String, dynamic>> maps = await db.query(
      'products',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return maps.isNotEmpty ? maps.first : null;
  }
}