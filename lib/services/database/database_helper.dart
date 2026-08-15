import 'package:bcrypt/bcrypt.dart';
import 'package:fada/providers/file_storage_helper.dart';
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
        debugPrint(
            "🆙 [DB INIT] Mise à jour de la base de $oldVersion vers $newVersion...");
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
      try {
        await db.execute('ALTER TABLE structures ADD COLUMN endSub TEXT');
      } catch (_) {}
    }
    if (oldVersion < 3) {
      try {
        await db.execute('ALTER TABLE users ADD COLUMN codeUser TEXT');
      } catch (_) {}
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute(
        '''CREATE TABLE users (id TEXT PRIMARY KEY, userName TEXT, userEmail TEXT, userPhone TEXT, userProfile TEXT, codeStructure TEXT, codeUser TEXT,userPassword TEXT, isActive INTEGER, version INTEGER, updatedAt TEXT)''');
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
    typeStructure TEXT
  )
''');
    await db
        .execute('CREATE INDEX idx_struct_user ON structures (createdUserId)');
    await db.execute(
        '''CREATE TABLE categories (id TEXT PRIMARY KEY, nameCat TEXT, codeStructure TEXT, isActive INTEGER, lastUpdated TEXT, photoPath TEXT, version INTEGER, deleted INTEGER DEFAULT 0)''');
    await db.execute(
        '''CREATE TABLE products (id TEXT PRIMARY KEY, productName TEXT, productPrice REAL, prixAchat REAL, productQte REAL, stockAlert REAL,productQrCode TEXT, codeStructure TEXT, categoryId TEXT, isActive INTEGER, lastUpdated TEXT, photoPath TEXT, version INTEGER, deleted INTEGER DEFAULT 0)''');
    await db.execute(
        '''CREATE TABLE commands (id TEXT PRIMARY KEY, customerName TEXT, status TEXT, totalAmount REAL, totalCredit REAL, codeStructure TEXT, paymentMethod TEXT, orderDate TEXT, lastUpdated TEXT, version INTEGER, deleted INTEGER DEFAULT 0, isSynced INTEGER DEFAULT 0)''');
    await db.execute('''
  CREATE TABLE customers (
    id TEXT PRIMARY KEY, 
    numCust TEXT, 
    codePin TEXT, 
    customerName TEXT, 
    codeStructure TEXT,
    createdDate TEXT, 
    version INTEGER,
    isSynced INTEGER DEFAULT 0
  )
''');
    await db.execute(
        '''CREATE TABLE command_lines (id TEXT PRIMARY KEY, commandId TEXT, productId TEXT, productName TEXT, quantity INTEGER, unitPrice REAL, codeStructure TEXT, FOREIGN KEY (commandId) REFERENCES commands (id) ON DELETE CASCADE)''');
    await db.execute(
        '''CREATE TABLE user_structures (id TEXT PRIMARY KEY, user_id TEXT, structure_id TEXT, role_in_structure TEXT, deleted INTEGER DEFAULT 0, updated_at TEXT, FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE, FOREIGN KEY (structure_id) REFERENCES structures (id) ON DELETE CASCADE)''');
    await db.execute(
        '''CREATE TABLE sync_queue (id INTEGER PRIMARY KEY AUTOINCREMENT, action TEXT, tableName TEXT, entityId TEXT, data TEXT, timestamp TEXT, status TEXT DEFAULT 'PENDING')''');
  }

  // --- 1. UTILISATEURS ---
  Future<void> saveOrUpdateUserLocal(Map<String, dynamic> userData) async {
    final db = await database;

    // Optionnel : Si vous ne voulez VRAIMENT qu'un seul utilisateur en base
    // await db.delete('users');

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
          'updatedAt':
              userData['updatedAt'] ?? DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace);

    debugPrint("👤 [DB] Utilisateur ${userData['id']} sauvegardé.");
  }

  Future<Map<String, dynamic>?> getUserByIdentifier(String identifier) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('users',
        where: 'userEmail = ? OR userName = ? OR userPhone = ?',
        whereArgs: [identifier, identifier, identifier]);
    return maps.isNotEmpty ? maps.first : null;
  }

  // --- 2. SYNCHRONISATION ---
  /// Synchronise la liste des structures du serveur vers la base locale.
  /// Harmonise les identifiants pour garantir le fonctionnement des jointures avec user_structures.

  /// Synchronise la liste des structures du serveur vers la base locale.
  /// Préserve le statut 'isActive' local si la structure a déjà été modifiée localement.

  Future<void> syncStructuresLocal(List<dynamic> structures) async {
    if (structures.isEmpty) return;

    final db = await database;

    await db.transaction((txn) async {
      for (final s in structures) {
        final String? structId = (s['id'] ?? s['idStructure'])?.toString();
        if (structId == null || structId.isEmpty) continue;

        // 1. Récupération de l'ancien chemin de la photo en local
        final List<Map<String, dynamic>> existing = await txn.query(
          'structures',
          columns: ['photoPath', 'isActive'],
          where: 'id = ?',
          whereArgs: [structId],
        );

        final String? existingPhotoPath =
            existing.isNotEmpty ? existing.first['photoPath'] as String? : null;
        final int serverStatus = _parseBool(s['isActive'] ?? s['active']);

        // 2. Insertion en conservant impérativement le photoPath existant
        await txn.insert(
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
            'photoPath':
                existingPhotoPath, // ✅ SÉCURITÉ : Conserve l'image locale
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });

    debugPrint(
        "✅ [DB] ${structures.length} structures synchronisées (photos protégées).");

    // 3. Téléchargement asynchrone de la nouvelle photo si disponible
    for (var s in structures) {
      final String? imageUrl = s['structPhotoUrl'] ?? s['photo'];
      final String? structId = (s['id'] ?? s['idStructure'])?.toString();

      if (imageUrl != null &&
          imageUrl.isNotEmpty &&
          imageUrl.startsWith("http") &&
          structId != null) {
        FileStorageHelper.saveImageLocally(imageUrl, "struct_$structId")
            .then((path) {
          if (path != null) {
            updateEntityPhotoPath('structures', structId, path);
          }
        }).catchError(
                (e) => debugPrint("⚠️ Échec photo structure $structId : $e"));
      }
    }
  }

  void _processStructurePhotos(List<dynamic> structures) {
    for (var s in structures) {
      final String? imageUrl = s['structPhotoUrl'] ?? s['photo'];
      final String? structId = (s['id'] ?? s['idStructure'])?.toString();

      if (imageUrl != null && imageUrl.startsWith("http") && structId != null) {
        FileStorageHelper.saveImageLocally(imageUrl, "struct_$structId")
            .then((path) {
          if (path != null) updateEntityPhotoPath('structures', structId, path);
        }).catchError((e) => debugPrint("⚠️ Échec photo $structId : $e"));
      }
    }
  }

  Future<void> syncUserStructuresLocal(
      List<Map<String, dynamic>> userStructures) async {
    final db = await database;

    if (userStructures.isEmpty) {
      debugPrint(
          "⚠️ Données vides reçues, aucune mise à jour effectuée pour protéger la base.");
      return;
    }

    await db.transaction((txn) async {
      // 1. Au lieu de DELETE, on met à jour les existants ou on insère
      for (var us in userStructures) {
        final String relationId = us['id']?.toString() ?? '';

        final Map<String, dynamic> row = {
          'id': relationId,
          'user_id': us['user_id']?.toString(),
          'structure_id': us['structure_id']?.toString(),
          'role_in_structure': us['role_in_structure'],
          'updated_at': us['updated_at'] ?? DateTime.now().toIso8601String(),
        };

        // 2. On insère ou on écrase seulement la ligne concernée (ConflictAlgorithm.replace)
        await txn.insert(
          'user_structures',
          row,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });

    debugPrint(
        "✅ Synchronisation des liens utilisateur terminée sans suppression massive.");
  }

  Future<void> syncCategoriesLocal(List<dynamic> categories) async {
    final db = await database;

    // On utilise une transaction globale pour garantir l'intégrité
    await db.transaction((txn) async {
      for (var cat in categories) {
        final String catId = cat['id'].toString();

        // 1. On récupère le chemin actuel en base AVANT d'insérer
        final List<Map<String, dynamic>> existing = await txn.query(
            'categories',
            columns: ['photoPath'],
            where: 'id = ?',
            whereArgs: [catId]);

        final String? existingPath =
            existing.isNotEmpty ? existing.first['photoPath'] as String? : null;

        // 2. On insère en forçant le maintien du path existant (ou null si rien n'était là)

        await txn.insert(
            'categories',
            {
              'id': catId,
              'nameCat': cat['nameCat'],
              'codeStructure': cat['codeStructure'],
              'photoPath':
                  existingPath, // <-- GARANTIT QU'ON NE PERD JAMAIS L'IMAGE
              'isActive': _parseBool(cat['active']),
              'lastUpdated': DateTime.now().toIso8601String(),
              'version': cat['version'] ?? 0,
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });

    debugPrint("✅ Catégories synchronisées (données textuelles protégées).");

    // 3. Téléchargement asynchrone des images (sans bloquer la synchro)
    for (var cat in categories) {
      final String? imageUrl = cat['photoCat'] ?? cat['categoryPhotoUrl'];
      final String catId = cat['id'].toString();

      if (imageUrl != null &&
          imageUrl.isNotEmpty &&
          imageUrl.startsWith("http")) {
        FileStorageHelper.saveImageLocally(imageUrl, "cat_$catId").then((path) {
          if (path != null) {
            // Mise à jour uniquement si le téléchargement a réussi
            updateEntityPhotoPath('categories', catId, path);
          }
        }).catchError((e) {
          debugPrint("⚠️ Échec téléchargement image pour $catId : $e");
        });
      }
    }
  }

  Future<void> syncProductsLocal(List<dynamic> products) async {
    final db = await database;

    // Utilisation d'un Batch pour garantir l'atomicité et la performance
    Batch batch = db.batch();

    for (var p in products) {
      // 1. Préparation des données pour SQLite
      final Map<String, dynamic> productData = {
        'id': p['id'],
        'productName': p['productName'],
        'productPrice': (p['productPrice'] as num?)?.toDouble() ?? 0.0,
        'prixAchat': (p['prixAchat'] as num?)?.toDouble() ?? 0.0,
        'productQte': (p['productQte'] as num?)?.toDouble() ?? 0.0,
        'stockAlert': (p['stockAlert'] as num?)?.toDouble() ?? 0.0,
        'productQrCode':
            p['productQrCode']?.toString(), // Intégration du QR Code
        'codeStructure': p['codeStructure'],
        'categoryId': p['categoryId'],
        'isActive': _parseBool(p['active']),
        'lastUpdated': DateTime.now().toIso8601String(),
        'version': p['version'] ?? 0,
        'deleted': p['deleted'] == true ? 1 : 0,
        // Note : 'photoPath' n'est pas inséré ici, il sera mis à jour après téléchargement
      };

      batch.insert('products', productData,
          conflictAlgorithm: ConflictAlgorithm.replace);

      // 2. Gestion de l'image en arrière-plan (sans bloquer la synchro)
      final String? imageUrl = p['photo'] ?? p['productPhotoUrl'];
      if (imageUrl != null && imageUrl.isNotEmpty) {
        final String productId = p['id'].toString();

        // On lance le téléchargement sans 'await' pour ne pas ralentir le batch
        FileStorageHelper.saveImageLocally(imageUrl, productId)
            .then((localPath) {
          if (localPath != null) {
            // Mise à jour différée du chemin de l'image en base
            db.update('products', {'photoPath': localPath},
                where: 'id = ?', whereArgs: [productId]);
          }
        });
      }
    }

    // Exécution de toutes les insertions en une seule transaction
    await batch.commit(noResult: true);
    debugPrint("✅ Synchronisation des produits terminée.");
  }

// Dans votre DatabaseHelper, assurez-vous d'avoir cette méthode pour la recherche par QR
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
            'lastUpdated':
                cmd['lastUpdated'] ?? DateTime.now().toIso8601String(),
            'version': cmd['version'] ?? 0,
            'deleted': cmd['deleted'] == 1 ? 1 : 0,
            'isSynced': cmd['isSynced'] ?? 1
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
      if (cmd['items'] != null) {
        batch.delete('command_lines',
            where: 'commandId = ?', whereArgs: [cmd['id']]);
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
  Future<List<Map<String, dynamic>>> getLocalStructuresByUser(
      String userId) async {
    final db = await database;

    // 1. Voyons combien de structures totales existent en base
    final totalStructs = await db.rawQuery('SELECT COUNT(*) FROM structures');
    // 2. Voyons combien de liens existent pour cet utilisateur
    final userLinks = await db
        .rawQuery('SELECT * FROM user_structures WHERE user_id = ?', [userId]);

    debugPrint(
        "🔍 [DEBUG SYNC] Total structures en base : ${totalStructs.first.values.first}");
    debugPrint(
        "🔍 [DEBUG SYNC] Liens trouvés pour user $userId : ${userLinks.length}");

    // 3. Exécution de la jointure
    final results = await db.rawQuery('''
    SELECT s.* FROM structures s
    INNER JOIN user_structures us ON s.id = us.structure_id
    WHERE us.user_id = ? AND s.isActive = 1
  ''', [userId]);

    debugPrint(
        "🔍 [DEBUG SYNC] Résultat final après JOIN : ${results.length} structures trouvées.");

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

  Future<List<Map<String, dynamic>>> getLocalEntities(
      String tableName, String codeStructure) async {
    final db = await database;
    return await db.query(tableName,
        where: 'codeStructure = ? AND (deleted = 0 OR deleted IS NULL)',
        whereArgs: [codeStructure]);
  }

  Future<List<Map<String, dynamic>>> getLocalCommands(
      String codeStructure) async {
    final db = await database;
    final List<Map<String, dynamic>> commandMaps = await db.query('commands',
        where: 'codeStructure = ? AND deleted = 0',
        whereArgs: [codeStructure],
        orderBy: 'orderDate DESC');
    List<Map<String, dynamic>> fullCommands = [];
    for (var cmdMap in commandMaps) {
      var mutableCmd = Map<String, dynamic>.from(cmdMap);
      final List<Map<String, dynamic>> items = await db.query('command_lines',
          where: 'commandId = ?', whereArgs: [cmdMap['id']]);
      mutableCmd['items'] = items;
      fullCommands.add(mutableCmd);
    }
    return fullCommands;
  }

  // --- 4. ACTIONS & SYNC QUEUE ---
  Future<void> updateProductStock(String productId, double quantitySold) async {
    final db = await database;
    await db.execute(
        'UPDATE products SET productQte = productQte - ? WHERE id = ?',
        [quantitySold, productId]);
  }

  Future<void> updateEntityPhotoPath(
      String tableName, String id, String path) async {
    final db = await database;
    debugPrint(
        "💾 [DB UPDATE] Mise à jour ID $id dans table $tableName avec path: $path");
    await db.update(tableName, {'photoPath': path},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> addToSyncQueue(String action, String tableName, String entityId,
      Map<String, dynamic> data) async {
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

  // --- 5. CUSTOMERS ---
// --- 5. CUSTOMERS ---
  Future<void> saveCustomerLocal(Map<String, dynamic> customer) async {
    final db = await database;
    await db.insert(
        'customers',
        {
          'id': customer['id'],
          'numCust': customer['numCust'],
          'codePin': customer['codePin'],
          'customerName': customer['customerName'],
          'codeStructure': customer['codeStructure'], // ✅ AJOUT ICI
          'createdDate':
          customer['createdDate'] ?? DateTime.now().toIso8601String(),
          'version': customer['version'] ?? 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, dynamic>?> getCustomerById(String id) async {
    final db = await database;
    final List<Map<String, dynamic>> maps =
        await db.query('customers', where: 'id = ?', whereArgs: [id]);
    return maps.isNotEmpty ? maps.first : null;
  }

  Future<void> deleteCustomerLocal(String id) async {
    final db = await database;
    await db.delete('customers', where: 'id = ?', whereArgs: [id]);
  }

  Future<Map<String, dynamic>?> getProductById(String id) async {
    final db = await database;
    final List<Map<String, dynamic>> maps =
        await db.query('products', where: 'id = ?', whereArgs: [id], limit: 1);
    return maps.isNotEmpty ? maps.first : null;
  }

  Future<void> updateCustomerCodePinOffline(
      String userId, String newCode) async {
    final db = await database;

    // 1. Mise à jour de la table des utilisateurs locaux
    await db.update('users',
        {'codeUser': newCode, 'updatedAt': DateTime.now().toIso8601String()},
        where: 'id = ?', whereArgs: [userId]);

    // 2. Insertion dans la file d'attente avec la clé EXACTE attendue par Spring Boot
    await db.insert('sync_queue', {
      'action': 'UPDATE_PASSWORD',
      'tableName': 'users',
      'entityId': userId,
      'data': jsonEncode({
        'newPassword': newCode
      }), // ✅ "newPassword" correspond à request.get("newPassword")
      'timestamp': DateTime.now().millisecondsSinceEpoch.toString(),
      'status': 'PENDING'
    });

    debugPrint(
        "📝 [DB Helper] Changement PIN enregistré dans la queue avec 'newPassword'.");
  }

  int _parseBool(dynamic value) {
    if (value == null) return 0;
    if (value is bool) return value ? 1 : 0;
    if (value is String)
      return (value.toLowerCase() == 'true' || value == '1') ? 1 : 0;
    if (value is int) return value == 1 ? 1 : 0;
    return 0;
  }

  Future<List<Map<String, dynamic>>> getCategoriesByStructureLocal(
      String structureId) async {
    final db = await database;
    return await db.query('categories',
        where: 'codeStructure = ?', whereArgs: [structureId]);
  }

  Future<List<Map<String, dynamic>>> getProductsByStructureLocal(
      String structureId) async {
    final db = await database;
    return await db.query('products',
        where: 'codeStructure = ?', whereArgs: [structureId]);
  }
// ✅ CORRECTION STRICTE : Authentification locale sécurisée

  Future<Map<String, dynamic>?> checkLoginOffline(
      String identifier, String codePin) async {
    final cleanIdentifier = identifier.trim();
    final cleanPin = codePin.trim();

    if (cleanIdentifier.isEmpty || cleanPin.isEmpty) return null;

    final db = await database;

    // ✅ CORRECTION : Ajout du 4ème argument pour codeUser
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
      debugPrint("❌ [AUTH] Aucun utilisateur trouvé avec cet identifiant.");
      return null;
    }

    final user = results.first;
    final String? storedHash = user['userPassword'] as String?;

    // 2. Vérification du hash
    if (storedHash != null && BCrypt.checkpw(cleanPin, storedHash)) {
      debugPrint("🔐 [AUTH OFFLINE] Succès : Mot de passe validé via BCrypt.");
      return user;
    }

    debugPrint("❌ [AUTH OFFLINE] Mot de passe incorrect.");
    return null;
  }

  // DANS DatabaseHelper.dart

  Future<List<Map<String, dynamic>>> getProductsInAlert(
      String structureIdentifier) async {
    final db = await database;

    // Requête robuste qui gère à la fois le codeStructure direct ou via l'ID de la structure
    final results = await db.rawQuery('''
    SELECT p.* FROM products p
    LEFT JOIN structures s ON p.codeStructure = s.codeStructure OR p.codeStructure = s.id
    WHERE (p.codeStructure = ? OR s.id = ? OR s.idStructure = ?)
    AND CAST(p.productQte AS REAL) <= CAST(p.stockAlert AS REAL)
    AND p.isActive = 1 
    AND p.deleted = 0
  ''', [structureIdentifier, structureIdentifier, structureIdentifier]);

    debugPrint(
        "🔍 [DEBUG ALERTE] Identifiant: $structureIdentifier | Alertes trouvées : ${results.length}");
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

  /// 🔹 Met à jour une structure localement (avec prise en compte du chemin de la photo)

  /// 🔹 Met à jour une structure localement en ciblant uniquement les colonnes existantes

  /// 🔹 Met à jour une structure localement de manière sécurisée

  /// 🔹 Met à jour une structure localement en sécurisant le typage pour SQLite
  Future<void> updateStructureLocal(
      String id, Map<String, dynamic> data) async {
    final db = await database;

    // Construction sécurisée des champs pour SQLite
    final Map<String, dynamic> updateFields = {
      if (data['idStructure'] != null)
        'idStructure': data['idStructure'].toString(),
      if (data['nomStructure'] != null)
        'nomStructure': data['nomStructure'].toString(),
      if (data['codeStructure'] != null)
        'codeStructure': data['codeStructure'].toString(),
      if (data['emailStructure'] != null)
        'emailStructure': data['emailStructure'].toString(),
      if (data['phone1Structure'] != null)
        'phone1Structure': data['phone1Structure'].toString(),
      if (data['phone2Structure'] != null)
        'phone2Structure': data['phone2Structure'].toString(),
      if (data['paysStructure'] != null)
        'paysStructure': data['paysStructure'].toString(),
      if (data['villeStructure'] != null)
        'villeStructure': data['villeStructure'].toString(),
      if (data['rueStructure'] != null)
        'rueStructure': data['rueStructure'].toString(),
      if (data['codePoste'] != null) 'codePoste': data['codePoste'].toString(),
      if (data['endSub'] != null) 'endSub': data['endSub'].toString(),
      if (data['startSub'] != null) 'startSub': data['startSub'].toString(),
      if (data['descriptionStructure'] != null)
        'descriptionStructure': data['descriptionStructure'].toString(),
      if (data['geoLocStructure'] != null)
        'geoLocStructure': data['geoLocStructure'].toString(),
      if (data['planStructure'] != null)
        'planStructure': data['planStructure'].toString(),
      if (data['typeStructure'] != null)
        'typeStructure': data['typeStructure'].toString(),
      if (data['disponibiliteStructure'] != null)
        'disponibiliteStructure': data['disponibiliteStructure'].toString(),
      if (data['structPhotoUrl'] != null)
        'structPhotoUrl': data['structPhotoUrl'].toString(),
      if (data['photoPath'] != null) 'photoPath': data['photoPath'].toString(),
      if (data['photoStructure'] != null)
        'photoStructure': data['photoStructure'].toString(),

      // Conversions numériques
      if (data['priorite'] != null)
        'priorite': int.tryParse(data['priorite'].toString()) ?? 0,
      if (data['version'] != null)
        'version': int.tryParse(data['version'].toString()) ?? 0,
      if (data['cout'] != null)
        'cout': double.tryParse(data['cout'].toString()) ?? 0.0,

      // Conversions booléennes pour SQLite (0 ou 1)
      if (data['isActive'] != null) 'isActive': _parseBool(data['isActive']),
      if (data['active'] != null) 'active': _parseBool(data['active']),
      if (data['deleted'] != null) 'deleted': _parseBool(data['deleted']),

      // 🔴 SÉCURISATION DU CHAMP 'users' (Empêche l'erreur HashMap)
      if (data['users'] != null)
        'users':
            data['users'] is String ? data['users'] : jsonEncode(data['users']),

      'lastUpdated': DateTime.now().toIso8601String(),
    };

    int rowsAffected = await db.update(
      'structures',
      updateFields,
      where: 'id = ?',
      whereArgs: [id],
    );

    debugPrint(
        "💾 [DB] Structure $id mise à jour localement. Lignes modifiées : $rowsAffected");
  }

  Future<Map<String, dynamic>?> getCustomerByNumCustLocal(
      String numCust) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'customers',
      where: 'numCust = ?',
      whereArgs: [numCust],
      limit: 1,
    );
    return maps.isNotEmpty ? maps.first : null;
  }


  /// 🔄 Récupère la liste locale des clients pour une structure spécifique
  Future<List<Map<String, dynamic>>> getLocalCustomersByStructure(String codeStructure) async {
    final db = await database;

    final List<Map<String, dynamic>> results = await db.query(
      'customers',
      where: 'codeStructure = ?',
      whereArgs: [codeStructure],
      orderBy: 'customerName ASC',
    );

    debugPrint("👥 [DB] ${results.length} clients trouvés en local pour la structure : $codeStructure");
    return results;
  }

  Future<void> syncCustomersLocal(List<dynamic> customers) async {
    debugPrint("📥 [DB] Données brutes reçues pour les clients : $customers"); // <-- Ajoute ceci
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
          'createdDate': cust['createdDate'] ?? DateTime.now().toIso8601String(),
          'version': cust['version'] ?? 0,
          'isSynced': 1,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
    debugPrint("✅ [DB] ${customers.length} clients synchronisés.");
  }
}
