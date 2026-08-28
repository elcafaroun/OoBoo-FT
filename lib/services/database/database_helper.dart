import 'package:bcrypt/bcrypt.dart';
import 'package:pokiboo/providers/file_storage_helper.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();

  static Database? _database;

  // Version globale de la base de données (Passage en v5 pour intégrer les règles de fidélité et segments)
  static const int _dbVersion = 5;

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

    debugPrint(" [DB INIT] Chemin physique : $path");

    return await openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, version) async {
        debugPrint(" [DB INIT] Nouvelle installation (v$version). Création complète du schéma...");
        await _onCreate(db, version);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        debugPrint(" [DB INIT] Migration déclenchée : passage de la v$oldVersion à la v$newVersion.");
        await _runMigrations(db, oldVersion, newVersion);
      },
      onDowngrade: onDatabaseDowngradeDelete,
      onConfigure: _onConfigure,
    );
  }

  Future _onConfigure(Database db) async {
    // OPTIMISATION PERFORMANCES : Mode WAL & synchronous NORMAL
    // rawQuery est utilisé ici car PRAGMA journal_mode retourne un résultat ("wal")
    await db.rawQuery('PRAGMA journal_mode = WAL');
    await db.execute('PRAGMA synchronous = NORMAL');
    await db.execute('PRAGMA foreign_keys = ON');
    debugPrint(" [DB INIT] PRAGMA WAL, Synchronous NORMAL & Clés étrangères activés.");
  }

  // --- GESTION CENTRALISÉE ET SÉQUENTIELLE DES MIGRATIONS ---
  Future<void> _runMigrations(Database db, int oldVersion, int newVersion) async {
    // Migration de v1 vers v2
    if (oldVersion < 2) {
      debugPrint(" [DB MIGRATION] Exécution des scripts pour v2...");
      try {
        await db.execute('ALTER TABLE structures ADD COLUMN endSub TEXT');
      } catch (e) {
        debugPrint(" [DB MIGRATION WARNING] endSub existe déjà : $e");
      }
    }

    // Migration de v2 vers v3
    if (oldVersion < 3) {
      debugPrint(" [DB MIGRATION] Exécution des scripts pour v3...");
      try {
        await db.execute('ALTER TABLE users ADD COLUMN codeUser TEXT');
      } catch (e) {
        debugPrint(" [DB MIGRATION WARNING] codeUser existe déjà : $e");
      }
    }

    // Migration de v3 vers v4
    if (oldVersion < 4) {
      debugPrint(" [DB MIGRATION] Exécution des scripts pour v4...");
      await db.execute('CREATE INDEX IF NOT EXISTS idx_cmd_date ON commands (orderDate)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_sync_queue_status ON sync_queue (status)');
    }

    // Migration de v4 vers v5 (Support Fidélité & Segments)
    if (oldVersion < 5) {
      debugPrint(" [DB MIGRATION] Exécution des scripts pour v5 (Ajout segment et nombreDePoints)...");
      try {
        await db.execute("ALTER TABLE customers ADD COLUMN segment TEXT DEFAULT 'STANDARD'");
      } catch (e) {
        debugPrint(" [DB MIGRATION WARNING] segment existe déjà : $e");
      }
      try {
        await db.execute("ALTER TABLE customers ADD COLUMN nombreDePoints INTEGER DEFAULT 0");
      } catch (e) {
        debugPrint(" [DB MIGRATION WARNING] nombreDePoints existe déjà : $e");
      }

      await db.execute('''
        CREATE TABLE IF NOT EXISTS segment_rules (
          id TEXT PRIMARY KEY,
          segmentName TEXT UNIQUE NOT NULL,
          conversionRate REAL DEFAULT 1000.0,
          pointsEarned INTEGER DEFAULT 1,
          minAmountOrder REAL DEFAULT 0.0,
          codeStructure TEXT
        )
      ''');
    }
  }

  // Méthode utilitaire pour les migrations complexes (changement de types / suppression de colonnes)
  Future<void> _migrateTableComplex(
      Database db, {
        required String tableName,
        required String createTableSql,
        required String copyColumnsSql,
      }) async {
    final tempTableName = '${tableName}_old';
    await db.execute('ALTER TABLE $tableName RENAME TO $tempTableName');
    await db.execute(createTableSql);
    await db.execute('INSERT INTO $tableName SELECT $copyColumnsSql FROM $tempTableName');
    await db.execute('DROP TABLE $tempTableName');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    await _runMigrations(db, oldVersion, newVersion);
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute(
        '''CREATE TABLE users (id TEXT PRIMARY KEY, userName TEXT, userEmail TEXT, userPhone TEXT, userProfile TEXT, codeStructure TEXT, codeUser TEXT, userPassword TEXT, isActive INTEGER, version INTEGER, updatedAt TEXT)''');

    await db.execute('''
      CREATE TABLE structures (
        id TEXT PRIMARY KEY, 
        idStructure TEXT, 
        nomStructure TEXT, 
        codeStructure TEXT, 
        emailStructure TEXT, 
        phone1Structure TEXT, 
        phone2Structure TEXT,
        paysStructure TEXT,
        villeStructure TEXT, 
        rueStructure TEXT,
        codePoste TEXT,
        endSub TEXT, 
        isActive INTEGER, 
        active INTEGER,
        lastUpdated TEXT, 
        photoPath TEXT, 
        structPhotoUrl TEXT,
        version INTEGER, 
        createdUserId TEXT,
        disponibiliteStructure TEXT,
        geoLocStructure TEXT,
        descriptionStructure TEXT,
        planStructure TEXT,
        startSub TEXT,
        cout REAL,
        priorite INTEGER,
        createdDate TEXT,
        deleted INTEGER DEFAULT 0,
        users TEXT,
        photoStructure TEXT,
        typeStructure TEXT,
        smsAlerte INTEGER,
        stockAlerte INTEGER,
        emailAlerte INTEGER,
        iaActive INTEGER,
        dashboard INTEGER,
        miniDashboard INTEGER,
        dashboardWeb INTEGER,
        userManagement INTEGER,
        nombreUsers INTEGER,
        loyaltyAccess INTEGER,
        gracePeriode INTEGER,
        nombreJourSouscription INTEGER,
        nombreCategorieParBusiness INTEGER,
        nombreProdParBusiness INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE app_settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');

    await db.execute(
        '''CREATE TABLE categories (id TEXT PRIMARY KEY, nameCat TEXT, codeStructure TEXT, isActive INTEGER, lastUpdated TEXT, photoPath TEXT, version INTEGER, deleted INTEGER DEFAULT 0)''');

    await db.execute(
        '''CREATE TABLE products (id TEXT PRIMARY KEY, productName TEXT, productPrice REAL, prixAchat REAL, productDescription TEXT, productQte REAL, stockAlert REAL, productQrCode TEXT, codeStructure TEXT, categoryId TEXT, isActive INTEGER, lastUpdated TEXT, photoPath TEXT, version INTEGER, deleted INTEGER DEFAULT 0)''');

    await db.execute(
        '''CREATE TABLE commands (id TEXT PRIMARY KEY, customerName TEXT, status TEXT, totalAmount REAL, totalCredit REAL, codeStructure TEXT, paymentMethod TEXT, orderDate TEXT, lastUpdated TEXT, version INTEGER, deleted INTEGER DEFAULT 0, isSynced INTEGER DEFAULT 0)''');

    await db.execute('''
      CREATE TABLE customers (
        id TEXT PRIMARY KEY, 
        numCust TEXT, 
        codePin TEXT, 
        customerName TEXT, 
        codeStructure TEXT,
        segment TEXT DEFAULT 'STANDARD',
        nombreDePoints INTEGER DEFAULT 0,
        createdDate TEXT, 
        version INTEGER,
        isSynced INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE segment_rules (
        id TEXT PRIMARY KEY,
        segmentName TEXT UNIQUE NOT NULL,
        conversionRate REAL DEFAULT 1000.0,
        pointsEarned INTEGER DEFAULT 1,
        minAmountOrder REAL DEFAULT 0.0,
        codeStructure TEXT
      )
    ''');

    await db.execute(
        '''CREATE TABLE command_lines (id TEXT PRIMARY KEY, commandId TEXT, productId TEXT, productName TEXT, quantity INTEGER, unitPrice REAL, codeStructure TEXT, FOREIGN KEY (commandId) REFERENCES commands (id) ON DELETE CASCADE)''');

    await db.execute(
        '''CREATE TABLE user_structures (id TEXT PRIMARY KEY, user_id TEXT, structure_id TEXT, role_in_structure TEXT, deleted INTEGER DEFAULT 0, updated_at TEXT, FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE, FOREIGN KEY (structure_id) REFERENCES structures (id) ON DELETE CASCADE)''');

    await db.execute(
        '''CREATE TABLE sync_queue (id INTEGER PRIMARY KEY AUTOINCREMENT, action TEXT, tableName TEXT, entityId TEXT, data TEXT, timestamp TEXT, status TEXT DEFAULT 'PENDING')''');

    // --- OPTIMISATION : INDEX DE RECHERCHE ---
    await db.execute('CREATE INDEX IF NOT EXISTS idx_struct_user ON structures (createdUserId)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_products_struct ON products (codeStructure)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_products_cat ON products (categoryId)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_products_qr ON products (productQrCode)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_categories_struct ON categories (codeStructure)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_commands_struct ON commands (codeStructure)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_cmd_lines_cmd ON command_lines (commandId)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_customers_struct ON customers (codeStructure)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_customers_num ON customers (numCust)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_user_struct_user ON user_structures (user_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_cmd_date ON commands (orderDate)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sync_queue_status ON sync_queue (status)');
  }

  // --- 1. UTILISATEURS ---
  Future<void> saveOrUpdateUserLocal(Map<String, dynamic> userData) async {
    final db = await database;

    await db.insert(
        'users',
        {
          'id': userData['id'],
          'userName': userData['userName'],
          'userEmail': userData['userEmail'],
          'userPhone': userData['userPhone'],
          'userProfile': userData['userProfile'],
          'codeStructure': userData['codeStructure'],
          'codeUser': userData['codeUser'],
          'userPassword': userData['userPassword'],
          'isActive': userData['isActive'] == true ? 1 : 0,
          'version': userData['version'] ?? 0,
          'updatedAt': userData['updatedAt'] ?? DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace);

    debugPrint(" [DB] Utilisateur ${userData['id']} sauvegardé.");
  }

  Future<Map<String, dynamic>?> getUserByIdentifier(String identifier) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('users',
        where: 'userEmail = ? OR userName = ? OR userPhone = ?',
        whereArgs: [identifier, identifier, identifier],
        limit: 1);
    return maps.isNotEmpty ? maps.first : null;
  }

  // --- 2. SYNCHRONISATION ---
  Future<void> syncStructuresLocal(List<dynamic> structures) async {
    if (structures.isEmpty) return;

    final db = await database;

    final List<Map<String, dynamic>> existingList = await db.query('structures', columns: ['id', 'photoPath']);
    final Map<String, String?> existingPhotos = {
      for (var row in existingList) row['id'].toString(): row['photoPath'] as String?
    };

    final Batch batch = db.batch();

    for (final s in structures) {
      final String? structId = (s['id'] ?? s['idStructure'])?.toString();
      if (structId == null || structId.isEmpty) continue;

      final String? existingPhotoPath = existingPhotos[structId];
      final int serverStatus = _parseBool(s['isActive'] ?? s['active']);

      batch.insert(
        'structures',
        {
          'id': structId,
          'nomStructure': s['nomStructure'] ?? 'Structure sans nom',
          'codeStructure': s['codeStructure'] ?? '',
          'emailStructure': s['emailStructure'],
          'phone1Structure': s['phone1Structure'],
          'villeStructure': s['villeStructure'],
          'endSub': s['endSub'],
          'isActive': serverStatus,
          'lastUpdated': DateTime.now().toIso8601String(),
          'version': s['version'] ?? 0,
          'createdUserId': s['createdUserId']?.toString(),
          'photoPath': existingPhotoPath,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
    debugPrint(" [DB] ${structures.length} structures synchronisées (photos protégées).");

    _processStructurePhotos(structures);
  }

  void _processStructurePhotos(List<dynamic> structures) {
    for (var s in structures) {
      final String? imageUrl = s['structPhotoUrl'] ?? s['photo'];
      final String? structId = (s['id'] ?? s['idStructure'])?.toString();

      if (imageUrl != null && imageUrl.isNotEmpty && imageUrl.startsWith("http") && structId != null) {
        FileStorageHelper.saveImageLocally(imageUrl, "struct_$structId")
            .then((path) {
          if (path != null) {
            updateEntityPhotoPath('structures', structId, path);
          }
        }).catchError((e) => debugPrint(" Échec photo structure $structId : $e"));
      }
    }
  }

  Future<void> syncUserStructuresLocal(List<Map<String, dynamic>> userStructures) async {
    final db = await database;

    if (userStructures.isEmpty) {
      debugPrint(" Données vides reçues, aucune mise à jour effectuée pour protéger la base.");
      return;
    }

    final Batch batch = db.batch();

    for (var us in userStructures) {
      final String relationId = us['id']?.toString() ?? '';

      final Map<String, dynamic> row = {
        'id': relationId,
        'user_id': us['user_id']?.toString(),
        'structure_id': us['structure_id']?.toString(),
        'role_in_structure': us['role_in_structure'],
        'updated_at': us['updated_at'] ?? DateTime.now().toIso8601String(),
      };

      batch.insert(
        'user_structures',
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
    debugPrint(" Synchronisation des liens utilisateur terminée sans suppression massive.");
  }

  Future<void> syncCategoriesLocal(List<dynamic> categories) async {
    if (categories.isEmpty) return;

    final db = await database;

    final List<Map<String, dynamic>> existingList = await db.query('categories', columns: ['id', 'photoPath']);
    final Map<String, String?> existingPhotos = {
      for (var row in existingList) row['id'].toString(): row['photoPath'] as String?
    };

    final Batch batch = db.batch();

    for (var cat in categories) {
      final String catId = cat['id'].toString();
      final String? existingPath = existingPhotos[catId];

      batch.insert(
        'categories',
        {
          'id': catId,
          'nameCat': cat['nameCat'],
          'codeStructure': cat['codeStructure'],
          'photoPath': existingPath,
          'isActive': _parseBool(cat['active']),
          'lastUpdated': DateTime.now().toIso8601String(),
          'version': cat['version'] ?? 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
    debugPrint(" Catégories synchronisées (données textuelles protégées).");

    for (var cat in categories) {
      final String? imageUrl = cat['photoCat'] ?? cat['categoryPhotoUrl'];
      final String catId = cat['id'].toString();

      if (imageUrl != null && imageUrl.isNotEmpty && imageUrl.startsWith("http")) {
        FileStorageHelper.saveImageLocally(imageUrl, "cat_$catId").then((path) {
          if (path != null) {
            updateEntityPhotoPath('categories', catId, path);
          }
        }).catchError((e) {
          debugPrint(" Échec téléchargement image pour $catId : $e");
        });
      }
    }
  }

  Future<void> syncProductsLocal(List<dynamic> products) async {
    if (products.isEmpty) return;
    final db = await database;

    final List<Map<String, dynamic>> existingList = await db.query('products', columns: ['id', 'photoPath']);
    final Map<String, String?> existingPhotos = {
      for (var row in existingList) row['id'].toString(): row['photoPath'] as String?
    };

    final Batch batch = db.batch();

    for (var p in products) {
      final String productId = p['id'].toString();
      final String? existingPath = existingPhotos[productId];

      final Map<String, dynamic> productData = {
        'id': p['id'],
        'productName': p['productName'],
        'productPrice': (p['productPrice'] as num?)?.toDouble() ?? 0.0,
        'prixAchat': (p['prixAchat'] as num?)?.toDouble() ?? 0.0,
        'productDescription': p['productDescription'] ?? '',
        'productQte': (p['productQte'] as num?)?.toDouble() ?? 0.0,
        'stockAlert': (p['stockAlert'] as num?)?.toDouble() ?? 0.0,
        'productQrCode': p['productQrCode']?.toString(),
        'codeStructure': p['codeStructure'],
        'categoryId': p['categoryId'],
        'isActive': _parseBool(p['active']),
        'lastUpdated': DateTime.now().toIso8601String(),
        'version': p['version'] ?? 0,
        'deleted': p['deleted'] == true ? 1 : 0,
        'photoPath': existingPath,
      };

      batch.insert(
        'products',
        productData,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
    debugPrint(" Synchronisation des produits terminée.");

    for (var p in products) {
      final String? imageUrl = p['photo'] ?? p['productPhotoUrl'];
      final String productId = p['id'].toString();

      if (imageUrl != null && imageUrl.isNotEmpty && imageUrl.startsWith("http")) {
        FileStorageHelper.saveImageLocally(imageUrl, productId)
            .then((localPath) {
          if (localPath != null) {
            updateEntityPhotoPath('products', productId, localPath);
          }
        }).catchError((e) => debugPrint(" Échec téléchargement image produit $productId : $e"));
      }
    }
  }

  Future<Map<String, dynamic>?> getProductByQrCodeLocal(String qrCode) async {
    final db = await database;
    final List<Map<String, dynamic>> results = await db.query(
      'products',
      where: 'productQrCode = ? AND deleted = 0',
      whereArgs: [qrCode.trim()],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  Future<void> syncCommandsLocal(List<dynamic> commands) async {
    if (commands.isEmpty) return;
    final db = await database;
    Batch batch = db.batch();
    for (var cmd in commands) {
      batch.insert(
          'commands',
          {
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
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
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

  // --- 3. LECTURE (OFFLINE) ---
  Future<List<Map<String, dynamic>>> getLocalStructuresByUser(String userId) async {
    final db = await database;

    final totalStructs = await db.rawQuery('SELECT COUNT(*) FROM structures');
    final userLinks = await db.rawQuery('SELECT * FROM user_structures WHERE user_id = ?', [userId]);

    debugPrint(" [DEBUG SYNC] Total structures en base : ${totalStructs.first.values.first}");
    debugPrint(" [DEBUG SYNC] Liens trouvés pour user $userId : ${userLinks.length}");

    final results = await db.rawQuery('''
      SELECT s.* FROM structures s
      INNER JOIN user_structures us ON s.id = us.structure_id
      WHERE us.user_id = ? AND s.isActive = 1
    ''', [userId]);

    debugPrint(" [DEBUG SYNC] Résultat final après JOIN : ${results.length} structures trouvées.");
    return results;
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
    return await db.query(tableName,
        where: 'codeStructure = ? AND (deleted = 0 OR deleted IS NULL)',
        whereArgs: [codeStructure]);
  }

  Future<List<Map<String, dynamic>>> getLocalCommands(String codeStructure) async {
    final db = await database;

    final List<Map<String, dynamic>> rows = await db.rawQuery('''
      SELECT 
        c.id AS cmd_id, c.customerName, c.status, c.totalAmount, c.totalCredit, 
        c.codeStructure, c.paymentMethod, c.orderDate, c.lastUpdated, c.version, 
        c.deleted, c.isSynced,
        cl.id AS line_id, cl.productId, cl.productName, cl.quantity, cl.unitPrice
      FROM commands c
      LEFT JOIN command_lines cl ON c.id = cl.commandId
      WHERE c.codeStructure = ? AND c.deleted = 0
      ORDER BY c.orderDate DESC
    ''', [codeStructure]);

    final Map<String, Map<String, dynamic>> commandsMap = {};

    for (var row in rows) {
      final String cmdId = row['cmd_id'] as String;

      if (!commandsMap.containsKey(cmdId)) {
        commandsMap[cmdId] = {
          'id': row['cmd_id'],
          'customerName': row['customerName'],
          'status': row['status'],
          'totalAmount': row['totalAmount'],
          'totalCredit': row['totalCredit'],
          'codeStructure': row['codeStructure'],
          'paymentMethod': row['paymentMethod'],
          'orderDate': row['orderDate'],
          'lastUpdated': row['lastUpdated'],
          'version': row['version'],
          'deleted': row['deleted'],
          'isSynced': row['isSynced'],
          'items': <Map<String, dynamic>>[],
        };
      }

      if (row['line_id'] != null) {
        (commandsMap[cmdId]!['items'] as List<Map<String, dynamic>>).add({
          'id': row['line_id'],
          'commandId': cmdId,
          'productId': row['productId'],
          'productName': row['productName'],
          'quantity': row['quantity'],
          'unitPrice': row['unitPrice'],
          'codeStructure': row['codeStructure'],
        });
      }
    }

    return commandsMap.values.toList();
  }

  // --- 4. ACTIONS & SYNC QUEUE ---
  Future<void> updateProductStock(String productId, double quantitySold) async {
    final db = await database;
    await db.execute(
        'UPDATE products SET productQte = productQte - ? WHERE id = ?',
        [quantitySold, productId]);
  }

  Future<void> updateEntityPhotoPath(String tableName, String id, String path) async {
    final db = await database;
    debugPrint(" [DB UPDATE] Mise à jour ID $id dans table $tableName avec path: $path");
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

  // --- 5. CUSTOMERS & FIDÉLITÉ ---
  Future<void> saveCustomerLocal(Map<String, dynamic> customer) async {
    final db = await database;
    await db.insert(
        'customers',
        {
          'id': customer['id'],
          'numCust': customer['numCust'],
          'codePin': customer['codePin'],
          'customerName': customer['customerName'],
          'codeStructure': customer['codeStructure'],
          'segment': customer['segment'] ?? 'STANDARD',
          'nombreDePoints': customer['nombreDePoints'] ?? 0,
          'createdDate': customer['createdDate'] ?? DateTime.now().toIso8601String(),
          'version': customer['version'] ?? 0,
          'isSynced': customer['isSynced'] ?? 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, dynamic>?> getCustomerById(String id) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('customers', where: 'id = ?', whereArgs: [id], limit: 1);
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

    await db.update('users',
        {'codeUser': newCode, 'updatedAt': DateTime.now().toIso8601String()},
        where: 'id = ?', whereArgs: [userId]);

    await db.insert('sync_queue', {
      'action': 'UPDATE_PASSWORD',
      'tableName': 'users',
      'entityId': userId,
      'data': jsonEncode({'newPassword': newCode}),
      'timestamp': DateTime.now().millisecondsSinceEpoch.toString(),
      'status': 'PENDING'
    });

    debugPrint(" [DB Helper] Changement PIN enregistré dans la queue avec 'newPassword'.");
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

  Future<Map<String, dynamic>?> checkLoginOffline(String identifier, String codePin) async {
    final cleanIdentifier = identifier.trim();
    final cleanPin = codePin.trim();

    if (cleanIdentifier.isEmpty || cleanPin.isEmpty) return null;

    final db = await database;

    final List<Map<String, dynamic>> results = await db.query(
      'users',
      where: 'userEmail = ? OR userName = ? OR userPhone = ? OR codeUser = ?',
      whereArgs: [
        cleanIdentifier,
        cleanIdentifier,
        cleanIdentifier,
        cleanIdentifier
      ],
      limit: 1,
    );

    if (results.isEmpty) {
      debugPrint(" [AUTH] Aucun utilisateur trouvé avec cet identifiant.");
      return null;
    }

    final user = results.first;
    final String? storedHash = user['userPassword'] as String?;

    if (storedHash != null && BCrypt.checkpw(cleanPin, storedHash)) {
      debugPrint(" [AUTH OFFLINE] Succès : Mot de passe validé via BCrypt.");
      return user;
    }

    debugPrint(" [AUTH OFFLINE] Mot de passe incorrect.");
    return null;
  }

  Future<List<Map<String, dynamic>>> getProductsInAlert(String structureIdentifier) async {
    final db = await database;

    final results = await db.rawQuery('''
      SELECT p.* FROM products p
      LEFT JOIN structures s ON p.codeStructure = s.codeStructure OR p.codeStructure = s.id
      WHERE (p.codeStructure = ? OR s.id = ? OR s.idStructure = ?)
      AND CAST(p.productQte AS REAL) <= CAST(p.stockAlert AS REAL)
      AND p.isActive = 1 
      AND p.deleted = 0
    ''', [structureIdentifier, structureIdentifier, structureIdentifier]);

    debugPrint(" [DEBUG ALERTE] Identifiant: $structureIdentifier | Alertes trouvées : ${results.length}");
    return results;
  }

  Future<Map<String, dynamic>?> getActiveUserLocal(String userId) async {
    final db = await database;
    final List<Map<String, dynamic>> results = await db.query(
      'users',
      where: 'id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  Future<void> updateStructureLocal(String id, Map<String, dynamic> data) async {
    final db = await database;

    final Map<String, dynamic> updateFields = {
      if (data['idStructure'] != null) 'idStructure': data['idStructure'].toString(),
      if (data['nomStructure'] != null) 'nomStructure': data['nomStructure'].toString(),
      if (data['codeStructure'] != null) 'codeStructure': data['codeStructure'].toString(),
      if (data['emailStructure'] != null) 'emailStructure': data['emailStructure'].toString(),
      if (data['phone1Structure'] != null) 'phone1Structure': data['phone1Structure'].toString(),
      if (data['phone2Structure'] != null) 'phone2Structure': data['phone2Structure'].toString(),
      if (data['paysStructure'] != null) 'paysStructure': data['paysStructure'].toString(),
      if (data['villeStructure'] != null) 'villeStructure': data['villeStructure'].toString(),
      if (data['rueStructure'] != null) 'rueStructure': data['rueStructure'].toString(),
      if (data['codePoste'] != null) 'codePoste': data['codePoste'].toString(),
      if (data['endSub'] != null) 'endSub': data['endSub'].toString(),
      if (data['startSub'] != null) 'startSub': data['startSub'].toString(),
      if (data['descriptionStructure'] != null) 'descriptionStructure': data['descriptionStructure'].toString(),
      if (data['geoLocStructure'] != null) 'geoLocStructure': data['geoLocStructure'].toString(),
      if (data['planStructure'] != null) 'planStructure': data['planStructure'].toString(),
      if (data['typeStructure'] != null) 'typeStructure': data['typeStructure'].toString(),
      if (data['disponibiliteStructure'] != null) 'disponibiliteStructure': data['disponibiliteStructure'].toString(),
      if (data['structPhotoUrl'] != null) 'structPhotoUrl': data['structPhotoUrl'].toString(),
      if (data['photoPath'] != null) 'photoPath': data['photoPath'].toString(),
      if (data['photoStructure'] != null) 'photoStructure': data['photoStructure'].toString(),

      if (data['nombreUsers'] != null) 'nombreUsers': int.tryParse(data['nombreUsers'].toString()) ?? 0,
      if (data['gracePeriode'] != null) 'gracePeriode': int.tryParse(data['gracePeriode'].toString()) ?? 0,
      if (data['nombreJourSouscription'] != null) 'nombreJourSouscription': int.tryParse(data['nombreJourSouscription'].toString()) ?? 0,
      if (data['nombreCategorieParBusiness'] != null) 'nombreCategorieParBusiness': int.tryParse(data['nombreCategorieParBusiness'].toString()) ?? 0,
      if (data['nombreProdParBusiness'] != null) 'nombreProdParBusiness': int.tryParse(data['nombreProdParBusiness'].toString()) ?? 0,

      if (data['smsAlerte'] != null) 'smsAlerte': _parseBool(data['smsAlerte']),
      if (data['stockAlerte'] != null) 'stockAlerte': _parseBool(data['stockAlerte']),
      if (data['emailAlerte'] != null) 'emailAlerte': _parseBool(data['emailAlerte']),
      if (data['iaActive'] != null) 'iaActive': _parseBool(data['iaActive']),
      if (data['dashboard'] != null) 'dashboard': _parseBool(data['dashboard']),
      if (data['miniDashboard'] != null) 'miniDashboard': _parseBool(data['miniDashboard']),
      if (data['dashboardWeb'] != null) 'dashboardWeb': _parseBool(data['dashboardWeb']),
      if (data['userManagement'] != null) 'userManagement': _parseBool(data['userManagement']),
      if (data['loyaltyAccess'] != null) 'loyaltyAccess': _parseBool(data['loyaltyAccess']),
      if (data['users'] != null) 'users': data['users'] is String ? data['users'] : jsonEncode(data['users']),

      'lastUpdated': DateTime.now().toIso8601String(),
    };

    int rowsAffected = await db.update(
      'structures',
      updateFields,
      where: 'id = ?',
      whereArgs: [id],
    );

    debugPrint(" [DB] Structure $id mise à jour localement. Lignes modifiées : $rowsAffected");
  }

  Future<Map<String, dynamic>?> getCustomerByNumCustLocal(String numCust) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'customers',
      where: 'numCust = ?',
      whereArgs: [numCust],
      limit: 1,
    );
    return maps.isNotEmpty ? maps.first : null;
  }

  Future<List<Map<String, dynamic>>> getLocalCustomersByStructure(String codeStructure) async {
    final db = await database;

    final List<Map<String, dynamic>> results = await db.query(
      'customers',
      where: 'codeStructure = ?',
      whereArgs: [codeStructure],
      orderBy: 'customerName ASC',
    );

    debugPrint(" [DB] ${results.length} clients trouvés en local pour la structure : $codeStructure");
    return results;
  }

  Future<void> syncCustomersLocal(List<dynamic> customers) async {
    debugPrint(" [DB] Données brutes reçues pour les clients : $customers");
    if (customers.isEmpty) return;

    final db = await database;
    Batch batch = db.batch();

    for (var cust in customers) {
      batch.insert(
        'customers',
        {
          'id': cust['id'],
          'numCust': cust['numCust'],
          'codePin': cust['codePin'],
          'customerName': cust['customerName'],
          'codeStructure': cust['codeStructure'],
          'segment': cust['segment'] ?? 'STANDARD',
          'nombreDePoints': cust['nombreDePoints'] ?? 0,
          'createdDate': cust['createdDate'] ?? DateTime.now().toIso8601String(),
          'version': cust['version'] ?? 0,
          'isSynced': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
    debugPrint(" [DB] ${customers.length} clients synchronisés.");
  }

  // --- GESTION DES RÈGLES DE SEGMENTATION ---

  Future<void> syncSegmentRulesLocal(List<dynamic> rules) async {
    if (rules.isEmpty) return;
    final db = await database;
    Batch batch = db.batch();

    for (var rule in rules) {
      batch.insert(
        'segment_rules',
        {
          'id': rule['id'],
          'segmentName': rule['segmentName'],
          'conversionRate': (rule['conversionRate'] as num?)?.toDouble() ?? 1000.0,
          'pointsEarned': rule['pointsEarned'] ?? 1,
          'minAmountOrder': (rule['minAmountOrder'] as num?)?.toDouble() ?? 0.0,
          'codeStructure': rule['codeStructure'],
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
    debugPrint(" [DB] ${rules.length} règles de segmentation synchronisées.");
  }

  // --- CALCUL DES POINTS FIDÉLITÉ (HORS-LIGNE) ---

  Future<void> addLoyaltyPointsOffline(String phone, double amountPaid) async {
    if (amountPaid <= 0 || phone.isEmpty) return;
    final db = await database;

    final customer = await getCustomerByNumCustLocal(phone);
    if (customer == null) return;

    final String segment = customer['segment'] ?? 'STANDARD';
    final int currentPoints = (customer['nombreDePoints'] as int?) ?? 0;

    final List<Map<String, dynamic>> rules = await db.query(
      'segment_rules',
      where: 'segmentName = ?',
      whereArgs: [segment],
      limit: 1,
    );

    double conversionRate = 1000.0;
    int pointsEarned = 1;
    double minAmount = 0.0;

    if (rules.isNotEmpty) {
      conversionRate = (rules.first['conversionRate'] as num?)?.toDouble() ?? 1000.0;
      pointsEarned = (rules.first['pointsEarned'] as int?) ?? 1;
      minAmount = (rules.first['minAmountOrder'] as num?)?.toDouble() ?? 0.0;
    }

    if (amountPaid >= minAmount && conversionRate > 0) {
      int earned = (amountPaid / conversionRate).floor() * pointsEarned;
      if (earned > 0) {
        int newTotalPoints = currentPoints + earned;
        await db.update(
          'customers',
          {
            'nombreDePoints': newTotalPoints,
            'isSynced': 0,
          },
          where: 'id = ?',
          whereArgs: [customer['id']],
        );
        debugPrint(" [FIDÉLITÉ] $earned points ajoutés au client $phone (Nouveau total: $newTotalPoints)");
      }
    }
  }

  // --- APP SETTINGS ---
  Future<bool> getSettingBool(String key, {bool defaultValue = false}) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (maps.isNotEmpty) {
      return maps.first['value'] == 'true' || maps.first['value'] == '1';
    }
    return defaultValue;
  }

  Future<void> setSettingBool(String key, bool value) async {
    final db = await database;
    await db.insert(
      'app_settings',
      {
        'key': key,
        'value': value ? '1' : '0',
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}