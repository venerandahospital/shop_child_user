import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/store.dart';
import '../models/item.dart';
import '../models/sale.dart';
import '../models/sale_item.dart';
import '../models/debt.dart';
import '../models/debt_payment.dart';
import '../models/client.dart';
import '../models/stock_receipt.dart';
import '../models/expense.dart';
import '../models/product_category.dart';
import '../models/unit.dart';
import '../models/packaging.dart';
import '../models/expense_category.dart';
import '../models/asset.dart';
import '../models/loan.dart';
import '../models/cart_draft.dart';
import '../models/service_transaction.dart';
import '../utils/meter_fixed_stock_items.dart';
import 'mother_data_cache.dart';

class LocalDbService {
  LocalDbService._();

  static final LocalDbService instance = LocalDbService._();

  static const _mainDbName = 'shop_manager_retail_supermarket.db';
  static const _authDbName = 'shop_manager_auth.db';
  static const _legacyDbName = 'shop_manager.db';
  static const _dbVersion = 30;
  final ValueNotifier<int> transactionVersion = ValueNotifier<int>(0);
  static const _metaBusinessName = 'business_name';
  static const _metaBusinessCode = 'business_code';
  static const _metaBusinessOwnerName = 'business_owner_name';
  static const _metaBusinessOwnerEmail = 'business_owner_email';
  static const _metaPrimaryCodeMigrationV1 = 'primary_code_migration_v1';

  Database? _db;

  void _notifyDataChanged() {
    transactionVersion.value = transactionVersion.value + 1;
  }

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<void> _setAppMeta(String key, String value) async {
    final db = await database;
    await db.insert(
      'app_meta',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> _getAppMeta(String key) async {
    final db = await database;
    final rows = await db.query(
      'app_meta',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> setAppMeta(String key, String value) async {
    await _setAppMeta(key, value);
  }

  Future<String?> getAppMeta(String key) async {
    return _getAppMeta(key);
  }

  Future<bool> hasBusinessProfile() async {
    final code = await _getAppMeta(_metaBusinessCode);
    return (code ?? '').trim().isNotEmpty;
  }

  Future<Map<String, String?>> getBusinessProfile() async {
    final name = await _getAppMeta(_metaBusinessName);
    final code = await _getAppMeta(_metaBusinessCode);
    final ownerName = await _getAppMeta(_metaBusinessOwnerName);
    final ownerEmail = await _getAppMeta(_metaBusinessOwnerEmail);
    return {
      'name': name,
      'code': code,
      'ownerName': ownerName,
      'ownerEmail': ownerEmail,
    };
  }

  Future<void> createBusinessProfile({
    required String businessName,
    required String businessCode,
    required String ownerName,
    required String ownerEmail,
  }) async {
    if (await hasBusinessProfile()) return;
    await _setAppMeta(_metaBusinessName, businessName.trim());
    await _setAppMeta(_metaBusinessCode, businessCode.trim().toUpperCase());
    await _setAppMeta(_metaBusinessOwnerName, ownerName.trim());
    await _setAppMeta(_metaBusinessOwnerEmail, ownerEmail.trim().toLowerCase());
    _notifyDataChanged();
  }

  String _dbName() {
    return _mainDbName;
  }

  Future<Database> _initDb() async {
    final path = await getDatabasePath();
    await _migrateLegacyDatabaseIfNeeded(path);

    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE stores (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            description TEXT,
            is_default INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            store_id INTEGER,
            name TEXT NOT NULL,
            sku TEXT,
            barcode TEXT,
            category TEXT,
            unit TEXT,
            unit_short TEXT,
            shelf_number TEXT,
            image_url TEXT,
            image_url_2 TEXT,
            image_url_3 TEXT,
            packaging_id INTEGER,
            variant_group TEXT,
            units_per_package REAL,
            cost_price REAL NOT NULL DEFAULT 0,
            selling_price REAL NOT NULL DEFAULT 0,
            stock_qty REAL NOT NULL DEFAULT 0,
            reorder_level REAL NOT NULL DEFAULT 0,
            restock_to REAL NOT NULL DEFAULT 0,
            special_roll_meters_total REAL NOT NULL DEFAULT 0,
            special_roll_meters_sold REAL NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE product_categories (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            main_category TEXT NOT NULL,
            sub_category TEXT NOT NULL,
            UNIQUE(main_category, sub_category)
          )
        ''');

        await db.execute('''
          CREATE TABLE units (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            unit_name TEXT NOT NULL,
            unit_short_name TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE packagings (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            short_name TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE expense_categories (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            parent_id INTEGER
          )
        ''');

        await db.execute('''
          CREATE TABLE sales (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            store_id INTEGER,
            total_amount REAL NOT NULL,
            overall_discount REAL NOT NULL DEFAULT 0,
            amount_received REAL,
            balance REAL,
            customer_name TEXT,
            customer_phone TEXT,
            customer_address TEXT,
            payment_method TEXT NOT NULL DEFAULT 'cash',
            created_at TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE sale_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            sale_id INTEGER,
            item_id INTEGER,
            quantity REAL NOT NULL,
            unit_price REAL NOT NULL,
            product_discount REAL NOT NULL DEFAULT 0,
            line_total REAL NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE debts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            store_id INTEGER,
            customer_name TEXT NOT NULL,
            phone TEXT,
            address TEXT,
            amount REAL NOT NULL,
            is_paid INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE stock_receipts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            store_id INTEGER,
            item_id INTEGER NOT NULL,
            quantity REAL NOT NULL,
            unit_cost REAL NOT NULL,
            total_cost REAL NOT NULL,
            unit_sell REAL NOT NULL,
            old_qty REAL NOT NULL,
            new_qty REAL NOT NULL,
            brand TEXT,
            expiry_date TEXT,
            received_at TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE stock_transfers (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            store_id INTEGER,
            from_item_id INTEGER NOT NULL,
            to_item_id INTEGER NOT NULL,
            from_quantity REAL NOT NULL,
            to_quantity REAL NOT NULL,
            conversion_factor REAL NOT NULL,
            old_from_qty REAL NOT NULL,
            new_from_qty REAL NOT NULL,
            old_to_qty REAL NOT NULL,
            new_to_qty REAL NOT NULL,
            notes TEXT,
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE app_meta (
            key TEXT PRIMARY KEY,
            value TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE clients (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            store_id INTEGER,
            name TEXT NOT NULL,
            phone TEXT,
            address TEXT,
            created_at TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE debt_payments (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            store_id INTEGER,
            customer_name TEXT NOT NULL,
            paid_amount REAL NOT NULL,
            remaining_balance REAL NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE client_account_transactions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            store_id INTEGER,
            client_id INTEGER NOT NULL,
            transaction_type TEXT NOT NULL,
            amount REAL NOT NULL,
            note TEXT,
            created_at TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE expenses (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            store_id INTEGER,
            title TEXT NOT NULL,
            category TEXT,
            paid_by TEXT,
            received_by TEXT,
            notes TEXT,
            amount REAL NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE service_transactions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            store_id INTEGER,
            title TEXT NOT NULL,
            notes TEXT,
            amount REAL NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE auth_accounts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            email TEXT NOT NULL UNIQUE,
            password TEXT NOT NULL,
            name TEXT NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE assets (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            store_id INTEGER,
            name TEXT NOT NULL,
            purchase_cost REAL NOT NULL DEFAULT 0,
            current_value REAL NOT NULL DEFAULT 0,
            purchase_date TEXT NOT NULL,
            notes TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE asset_depreciations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            asset_id INTEGER NOT NULL,
            amount REAL NOT NULL,
            note TEXT,
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE loans (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            store_id INTEGER,
            client_id INTEGER NOT NULL,
            principal_amount REAL NOT NULL,
            annual_interest_percent REAL NOT NULL DEFAULT 0,
            expected_payment_date TEXT NOT NULL,
            interest_amount REAL NOT NULL DEFAULT 0,
            total_due REAL NOT NULL DEFAULT 0,
            note TEXT,
            status TEXT NOT NULL DEFAULT 'active',
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE loan_payments (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            store_id INTEGER,
            loan_id INTEGER NOT NULL,
            client_id INTEGER NOT NULL,
            paid_amount REAL NOT NULL,
            remaining_balance REAL NOT NULL,
            note TEXT,
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE cart_drafts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            payload TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE item_barcodes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            item_id INTEGER NOT NULL,
            code TEXT NOT NULL COLLATE NOCASE UNIQUE,
            created_at TEXT NOT NULL
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS stock_receipts (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              store_id INTEGER,
              item_id INTEGER NOT NULL,
              quantity REAL NOT NULL,
              unit_cost REAL NOT NULL,
              total_cost REAL NOT NULL,
              unit_sell REAL NOT NULL,
              old_qty REAL NOT NULL,
              new_qty REAL NOT NULL,
              brand TEXT,
              expiry_date TEXT,
              received_at TEXT NOT NULL
            )
          ''');
        }
        if (oldVersion < 3) {
          await db.execute('ALTER TABLE sales ADD COLUMN amount_received REAL');
          await db.execute('ALTER TABLE sales ADD COLUMN balance REAL');
          await db.execute('ALTER TABLE sales ADD COLUMN customer_name TEXT');
          await db.execute('ALTER TABLE sales ADD COLUMN customer_phone TEXT');
          await db.execute(
            'ALTER TABLE sales ADD COLUMN customer_address TEXT',
          );
          await db.execute('ALTER TABLE debts ADD COLUMN address TEXT');
        }
        // Ensure clients table exists for upgrades from older versions
        if (oldVersion < 4) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS clients (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              store_id INTEGER,
              name TEXT NOT NULL,
              phone TEXT,
              address TEXT,
              created_at TEXT NOT NULL
            )
          ''');
        }
        if (oldVersion < 5) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS debt_payments (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              store_id INTEGER,
              customer_name TEXT NOT NULL,
              paid_amount REAL NOT NULL,
              remaining_balance REAL NOT NULL,
              created_at TEXT NOT NULL
            )
          ''');
        }
        if (oldVersion < 6) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS expenses (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              store_id INTEGER,
              title TEXT NOT NULL,
              category TEXT,
              paid_by TEXT,
              received_by TEXT,
              notes TEXT,
              amount REAL NOT NULL,
              created_at TEXT NOT NULL
            )
          ''');
        }
        if (oldVersion < 7) {
          await db.execute('ALTER TABLE expenses ADD COLUMN paid_by TEXT');
          await db.execute('ALTER TABLE expenses ADD COLUMN received_by TEXT');
        }
        if (oldVersion < 8) {
          await db.execute('ALTER TABLE items ADD COLUMN unit_short TEXT');
        }
        if (oldVersion < 9) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS product_categories (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              main_category TEXT NOT NULL,
              sub_category TEXT NOT NULL,
              UNIQUE(main_category, sub_category)
            )
          ''');
        }
        if (oldVersion < 10) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS units (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              unit_name TEXT NOT NULL,
              unit_short_name TEXT NOT NULL
            )
          ''');
        }
        if (oldVersion < 11) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS expense_categories (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              main_category TEXT NOT NULL,
              sub_category TEXT NOT NULL,
              UNIQUE(main_category, sub_category)
            )
          ''');
        }
        if (oldVersion < 12) {
          await db.execute('''
            CREATE TABLE expense_categories_new (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              parent_id INTEGER
            )
          ''');
          try {
            final rows = await db.query('expense_categories');
            for (final row in rows) {
              final main = row['main_category'] as String? ?? '';
              final sub = row['sub_category'] as String? ?? '';
              if (main.isNotEmpty) {
                final id = await db.insert('expense_categories_new', {
                  'name': main,
                  'parent_id': null,
                });
                if (sub.isNotEmpty) {
                  await db.insert('expense_categories_new', {
                    'name': sub,
                    'parent_id': id,
                  });
                }
              }
            }
          } catch (_) {}
          await db.execute('DROP TABLE IF EXISTS expense_categories');
          await db.execute(
            'ALTER TABLE expense_categories_new RENAME TO expense_categories',
          );
        }
        if (oldVersion < 13) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS auth_accounts (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              email TEXT NOT NULL UNIQUE,
              password TEXT NOT NULL,
              name TEXT NOT NULL,
              created_at TEXT NOT NULL
            )
          ''');
        }
        if (oldVersion < 14) {
          await db.execute('ALTER TABLE items ADD COLUMN image_url TEXT');
        }
        if (oldVersion < 15) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS stock_transfers (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              store_id INTEGER,
              from_item_id INTEGER NOT NULL,
              to_item_id INTEGER NOT NULL,
              from_quantity REAL NOT NULL,
              to_quantity REAL NOT NULL,
              conversion_factor REAL NOT NULL,
              old_from_qty REAL NOT NULL,
              new_from_qty REAL NOT NULL,
              old_to_qty REAL NOT NULL,
              new_to_qty REAL NOT NULL,
              notes TEXT,
              created_at TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS app_meta (
              key TEXT PRIMARY KEY,
              value TEXT
            )
          ''');
        }
        if (oldVersion < 16) {
          await db.execute('ALTER TABLE items ADD COLUMN packaging_id INTEGER');
          await db.execute('ALTER TABLE items ADD COLUMN variant_group TEXT');
          await db.execute('ALTER TABLE items ADD COLUMN units_per_package REAL');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS packagings (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              short_name TEXT
            )
          ''');
        }
        if (oldVersion < 17) {
          await db.execute('ALTER TABLE items ADD COLUMN restock_to REAL NOT NULL DEFAULT 0');
        }
        if (oldVersion < 18) {
          await db.execute(
            'ALTER TABLE sales ADD COLUMN overall_discount REAL NOT NULL DEFAULT 0',
          );
          await db.execute(
            'ALTER TABLE sale_items ADD COLUMN product_discount REAL NOT NULL DEFAULT 0',
          );
        }
        if (oldVersion < 19) {
          await db.execute('ALTER TABLE items ADD COLUMN barcode TEXT');
        }
        if (oldVersion < 20) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS client_account_transactions (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              store_id INTEGER,
              client_id INTEGER NOT NULL,
              transaction_type TEXT NOT NULL,
              amount REAL NOT NULL,
              note TEXT,
              created_at TEXT NOT NULL
            )
          ''');
        }
        if (oldVersion < 21) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS assets (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              store_id INTEGER,
              name TEXT NOT NULL,
              purchase_cost REAL NOT NULL DEFAULT 0,
              current_value REAL NOT NULL DEFAULT 0,
              purchase_date TEXT NOT NULL,
              notes TEXT,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS asset_depreciations (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              asset_id INTEGER NOT NULL,
              amount REAL NOT NULL,
              note TEXT,
              created_at TEXT NOT NULL
            )
          ''');
        }
        if (oldVersion < 22) {
          await db.execute('ALTER TABLE items ADD COLUMN image_url_2 TEXT');
          await db.execute('ALTER TABLE items ADD COLUMN image_url_3 TEXT');
        }
        if (oldVersion < 23) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS loans (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              store_id INTEGER,
              client_id INTEGER NOT NULL,
              principal_amount REAL NOT NULL,
              annual_interest_percent REAL NOT NULL DEFAULT 0,
              expected_payment_date TEXT NOT NULL,
              interest_amount REAL NOT NULL DEFAULT 0,
              total_due REAL NOT NULL DEFAULT 0,
              note TEXT,
              status TEXT NOT NULL DEFAULT 'active',
              created_at TEXT NOT NULL
            )
          ''');
        }
        if (oldVersion < 24) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS cart_drafts (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              title TEXT NOT NULL,
              payload TEXT NOT NULL,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            )
          ''');
        }
        if (oldVersion < 25) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS item_barcodes (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              item_id INTEGER NOT NULL,
              code TEXT NOT NULL COLLATE NOCASE UNIQUE,
              created_at TEXT NOT NULL
            )
          ''');
        }
        if (oldVersion < 26) {
          await db.execute('ALTER TABLE items ADD COLUMN shelf_number TEXT');
        }
        if (oldVersion < 27) {
          await db.execute(
            "ALTER TABLE sales ADD COLUMN payment_method TEXT NOT NULL DEFAULT 'cash'",
          );
        }
        if (oldVersion < 28) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS loan_payments (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              store_id INTEGER,
              loan_id INTEGER NOT NULL,
              client_id INTEGER NOT NULL,
              paid_amount REAL NOT NULL,
              remaining_balance REAL NOT NULL,
              note TEXT,
              created_at TEXT NOT NULL
            )
          ''');
        }
        if (oldVersion < 29) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS service_transactions (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              store_id INTEGER,
              title TEXT NOT NULL,
              notes TEXT,
              amount REAL NOT NULL,
              created_at TEXT NOT NULL
            )
          ''');
        }
        if (oldVersion < 30) {
          await db.execute(
            'ALTER TABLE items ADD COLUMN special_roll_meters_total REAL NOT NULL DEFAULT 0',
          );
          await db.execute(
            'ALTER TABLE items ADD COLUMN special_roll_meters_sold REAL NOT NULL DEFAULT 0',
          );
        }
      },
      onOpen: (db) async {
        // Safety net: if DB version is already 4 but old migration missed this table.
        await db.execute('''
          CREATE TABLE IF NOT EXISTS clients (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            store_id INTEGER,
            name TEXT NOT NULL,
            phone TEXT,
            address TEXT,
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS debt_payments (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            store_id INTEGER,
            customer_name TEXT NOT NULL,
            paid_amount REAL NOT NULL,
            remaining_balance REAL NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS client_account_transactions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            store_id INTEGER,
            client_id INTEGER NOT NULL,
            transaction_type TEXT NOT NULL,
            amount REAL NOT NULL,
            note TEXT,
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS expenses (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            store_id INTEGER,
            title TEXT NOT NULL,
            category TEXT,
            paid_by TEXT,
            received_by TEXT,
            notes TEXT,
            amount REAL NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS auth_accounts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            email TEXT NOT NULL UNIQUE,
            password TEXT NOT NULL,
            name TEXT NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS assets (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            store_id INTEGER,
            name TEXT NOT NULL,
            purchase_cost REAL NOT NULL DEFAULT 0,
            current_value REAL NOT NULL DEFAULT 0,
            purchase_date TEXT NOT NULL,
            notes TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS asset_depreciations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            asset_id INTEGER NOT NULL,
            amount REAL NOT NULL,
            note TEXT,
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS loans (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            store_id INTEGER,
            client_id INTEGER NOT NULL,
            principal_amount REAL NOT NULL,
            annual_interest_percent REAL NOT NULL DEFAULT 0,
            expected_payment_date TEXT NOT NULL,
            interest_amount REAL NOT NULL DEFAULT 0,
            total_due REAL NOT NULL DEFAULT 0,
            note TEXT,
            status TEXT NOT NULL DEFAULT 'active',
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS loan_payments (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            store_id INTEGER,
            loan_id INTEGER NOT NULL,
            client_id INTEGER NOT NULL,
            paid_amount REAL NOT NULL,
            remaining_balance REAL NOT NULL,
            note TEXT,
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS cart_drafts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            payload TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS item_barcodes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            item_id INTEGER NOT NULL,
            code TEXT NOT NULL COLLATE NOCASE UNIQUE,
            created_at TEXT NOT NULL
          )
        ''');
        try {
          await db.execute('ALTER TABLE items ADD COLUMN image_url TEXT');
        } catch (_) {
          // Column already exists.
        }
        try {
          await db.execute('ALTER TABLE items ADD COLUMN packaging_id INTEGER');
        } catch (_) {}
        try {
          await db.execute('ALTER TABLE items ADD COLUMN variant_group TEXT');
        } catch (_) {}
        try {
          await db.execute('ALTER TABLE items ADD COLUMN units_per_package REAL');
        } catch (_) {}
        try {
          await db.execute('ALTER TABLE items ADD COLUMN restock_to REAL NOT NULL DEFAULT 0');
        } catch (_) {}
        try {
          await db.execute('ALTER TABLE items ADD COLUMN barcode TEXT');
        } catch (_) {}
        try {
          await db.execute(
            'ALTER TABLE sales ADD COLUMN overall_discount REAL NOT NULL DEFAULT 0',
          );
        } catch (_) {}
        try {
          await db.execute(
            'ALTER TABLE sale_items ADD COLUMN product_discount REAL NOT NULL DEFAULT 0',
          );
        } catch (_) {}
        await db.execute('''
          CREATE TABLE IF NOT EXISTS packagings (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            short_name TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS stock_transfers (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            store_id INTEGER,
            from_item_id INTEGER NOT NULL,
            to_item_id INTEGER NOT NULL,
            from_quantity REAL NOT NULL,
            to_quantity REAL NOT NULL,
            conversion_factor REAL NOT NULL,
            old_from_qty REAL NOT NULL,
            new_from_qty REAL NOT NULL,
            old_to_qty REAL NOT NULL,
            new_to_qty REAL NOT NULL,
            notes TEXT,
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS app_meta (
            key TEXT PRIMARY KEY,
            value TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS service_transactions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            store_id INTEGER,
            title TEXT NOT NULL,
            notes TEXT,
            amount REAL NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');
        await _migrateAuthDatabaseIntoMainDb(db);
      },
    );
  }

  Future<void> _migrateAuthDatabaseIntoMainDb(Database mainDb) async {
    try {
      final dbPath = await getDatabasesPath();
      final authPath = p.join(dbPath, _authDbName);
      final authFile = File(authPath);
      if (!await authFile.exists()) return;
      final legacyAuthDb = await openDatabase(
        authPath,
        readOnly: true,
      );
      try {
        final rows = await legacyAuthDb.query('auth_accounts');
        for (final row in rows) {
          final email = (row['email'] as String? ?? '').trim().toLowerCase();
          if (email.isEmpty) continue;
          await mainDb.insert(
            'auth_accounts',
            {
              'email': email,
              'password': (row['password'] as String?) ?? '',
              'name': (row['name'] as String?) ?? 'Shop Admin',
              'created_at': (row['created_at'] as String?) ??
                  DateTime.now().toIso8601String(),
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      } finally {
        await legacyAuthDb.close();
      }
    } catch (_) {
      // Keep app usable even if legacy auth migration fails.
    }
  }

  Future<void> _migrateLegacyDatabaseIfNeeded(String targetPath) async {
    final targetFile = File(targetPath);
    if (await targetFile.exists()) return;

    final dbPath = await getDatabasesPath();
    final legacyPath = p.join(dbPath, _legacyDbName);
    final legacyFile = File(legacyPath);
    if (!await legacyFile.exists()) return;

    await legacyFile.copy(targetPath);
  }

  Future<String> getDatabasePath() async {
    final dbPath = await getDatabasesPath();
    return p.join(dbPath, _dbName());
  }

  Future<void> closeDatabase() async {
    if (_db != null) {
      await _db!.close();
      _db = null;
    }
  }

  Future<void> replaceDatabaseFromFile(String sourceFilePath) async {
    await closeDatabase();
    final targetPath = await getDatabasePath();
    final sourceFile = File(sourceFilePath);
    if (!await sourceFile.exists()) {
      throw Exception('Source backup file does not exist.');
    }
    await sourceFile.copy(targetPath);
    _db = await _initDb();
    _notifyDataChanged();
  }

  // ===== STORES =====

  Future<int> upsertStore(Store store) async {
    final db = await database;
    if (store.id == null) {
      final id = await db.insert('stores', store.toMap());
      if (store.isDefault) {
        await _setDefaultStore(id);
      }
      return id;
    } else {
      await db.update(
        'stores',
        store.toMap(),
        where: 'id = ?',
        whereArgs: [store.id],
      );
      if (store.isDefault) {
        await _setDefaultStore(store.id!);
      }
      return store.id!;
    }
  }

  Future<void> _setDefaultStore(int storeId) async {
    final db = await database;
    await db.update('stores', {'is_default': 0});
    await db.update(
      'stores',
      {'is_default': 1},
      where: 'id = ?',
      whereArgs: [storeId],
    );
  }

  Future<List<Store>> getStores() async {
    final cache = MotherDataCache.instance;
    if (cache.storesApplied) {
      return cache.getStores();
    }
    final db = await database;
    final maps = await db.query('stores', orderBy: 'created_at DESC');
    return maps.map(Store.fromMap).toList();
  }

  // ===== CLIENTS =====

  String _firstSecondNameKey(String? rawName) {
    final parts = (rawName ?? '')
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '';
    if (parts.length == 1) return parts.first;
    return '${parts[0]} ${parts[1]}';
  }

  Future<int> upsertClient(Client client) async {
    final db = await database;
    final incomingKey = _firstSecondNameKey(client.name);
    if (incomingKey.isNotEmpty) {
      final existing = await db.query(
        'clients',
        orderBy: 'id ASC',
      );
      final duplicate = existing.firstWhere(
        (row) =>
            _firstSecondNameKey(row['name'] as String?) == incomingKey &&
            (row['id'] as int?) != client.id,
        orElse: () => const <String, Object?>{},
      );
      if (duplicate.isNotEmpty) {
        throw StateError('A client with the same first and second name already exists.');
      }
    }
    int result;
    if (client.id == null) {
      final insertedId = await db.insert('clients', client.toMap());
      await ensureClientAccount(
        clientId: insertedId,
        storeId: client.storeId,
      );
      result = insertedId;
    } else {
      result = await db.update(
        'clients',
        client.toMap(),
        where: 'id = ?',
        whereArgs: [client.id],
      );
      await ensureClientAccount(
        clientId: client.id!,
        storeId: client.storeId,
      );
    }
    _notifyDataChanged();
    return result;
  }

  Future<Client?> getClientByNormalizedName(String customerName) async {
    final cache = MotherDataCache.instance;
    if (cache.clientsApplied) {
      return cache.getClientByNormalizedName(customerName);
    }
    final db = await database;
    final rows = await db.query(
      'clients',
      where: 'lower(trim(name)) = lower(trim(?))',
      whereArgs: [customerName],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Client.fromMap(rows.first);
  }

  Future<void> ensureClientAccount({
    required int clientId,
    int? storeId,
  }) async {
    final db = await database;
    final existing = await db.query(
      'client_account_transactions',
      where: 'client_id = ?',
      whereArgs: [clientId],
      limit: 1,
    );
    if (existing.isNotEmpty) return;
    await db.insert('client_account_transactions', {
      'store_id': storeId,
      'client_id': clientId,
      'transaction_type': 'account_opened',
      'amount': 0.0,
      'note': 'Client account opened',
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<double> getClientAccountBalance(int clientId) async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT SUM(amount) AS total FROM client_account_transactions WHERE client_id = ?',
      [clientId],
    );
    return (rows.first['total'] as num?)?.toDouble() ?? 0;
  }

  Future<List<Map<String, Object?>>> getClientAccountTransactions(
    int clientId,
  ) async {
    final db = await database;
    final rows = await db.query(
      'client_account_transactions',
      where: 'client_id = ?',
      whereArgs: [clientId],
      orderBy: 'datetime(created_at) DESC, id DESC',
    );
    return rows.map((row) => Map<String, Object?>.from(row)).toList();
  }

  Future<void> recordClientAccountTransaction({
    required int clientId,
    required int? storeId,
    required String transactionType,
    required double amount,
    String? note,
    bool enforceNonNegative = true,
  }) async {
    if (amount == 0) {
      throw ArgumentError('Amount must be non-zero.');
    }
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.rawQuery(
        'SELECT SUM(amount) AS total FROM client_account_transactions WHERE client_id = ?',
        [clientId],
      );
      final current = (rows.first['total'] as num?)?.toDouble() ?? 0;
      final next = current + amount;
      if (enforceNonNegative && next < 0) {
        throw StateError('Insufficient client account balance.');
      }
      await txn.insert('client_account_transactions', {
        'store_id': storeId,
        'client_id': clientId,
        'transaction_type': transactionType.trim().isEmpty
            ? 'adjustment'
            : transactionType.trim(),
        'amount': amount,
        'note': (note ?? '').trim().isEmpty ? null : note!.trim(),
        'created_at': DateTime.now().toIso8601String(),
      });
    });
    _notifyDataChanged();
  }

  Future<List<Client>> getClients({int? storeId}) async {
    final cache = MotherDataCache.instance;
    if (cache.clientsApplied) {
      return cache.getClients(storeId: storeId);
    }
    final db = await database;
    final maps = await db.query(
      'clients',
      where: storeId != null ? 'store_id = ?' : null,
      whereArgs: storeId != null ? [storeId] : null,
      orderBy: 'name COLLATE NOCASE ASC',
    );
    return maps.map(Client.fromMap).toList();
  }

  Future<Store?> getDefaultStore() async {
    final cache = MotherDataCache.instance;
    if (cache.storesApplied) {
      final d = cache.getDefaultStore();
      if (d != null) return d;
      final all = cache.getStores();
      return all.isNotEmpty ? all.first : null;
    }
    final db = await database;
    final maps = await db.query('stores', where: 'is_default = 1', limit: 1);
    if (maps.isEmpty) return null;
    return Store.fromMap(maps.first);
  }

  // ===== AUTH ACCOUNTS =====

  Future<void> upsertAuthAccount({
    required String email,
    required String password,
    required String name,
  }) async {
    final db = await database;
    final normalizedEmail = email.trim().toLowerCase();
    final now = DateTime.now().toIso8601String();
    final existing = await db.query(
      'auth_accounts',
      where: 'email = ?',
      whereArgs: [normalizedEmail],
      limit: 1,
    );
    if (existing.isEmpty) {
      await db.insert('auth_accounts', {
        'email': normalizedEmail,
        'password': password,
        'name': name,
        'created_at': now,
      });
    } else {
      await db.update(
        'auth_accounts',
        {
          'password': password,
          'name': name,
        },
        where: 'email = ?',
        whereArgs: [normalizedEmail],
      );
    }
    _notifyDataChanged();
  }

  Future<Map<String, String>?> getAuthAccountByEmail(String email) async {
    final db = await database;
    final normalizedEmail = email.trim().toLowerCase();
    final rows = await db.query(
      'auth_accounts',
      where: 'email = ?',
      whereArgs: [normalizedEmail],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return {
      'email': (row['email'] as String?) ?? normalizedEmail,
      'password': (row['password'] as String?) ?? '',
      'name': (row['name'] as String?) ?? 'Shop Admin',
    };
  }

  Future<bool> hasAnyAuthAccount() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM auth_accounts',
    );
    final count = (result.first['count'] as num?)?.toInt() ?? 0;
    return count > 0;
  }

  Future<int> updateAuthAccountByEmail({
    required String oldEmail,
    required String newEmail,
    required String password,
    required String name,
  }) async {
    final db = await database;
    final result = await db.update(
      'auth_accounts',
      {
        'email': newEmail.trim().toLowerCase(),
        'password': password,
        'name': name,
      },
      where: 'email = ?',
      whereArgs: [oldEmail.trim().toLowerCase()],
    );
    if (result > 0) _notifyDataChanged();
    return result;
  }

  // ===== ITEMS =====

  Future<int> applySpecialItemSaleOutcome({
    required int itemId,
    required bool stillAvailable,
    required double metersSold,
  }) async {
    final db = await database;
    final rows = await db.query(
      'items',
      where: 'id = ?',
      whereArgs: [itemId],
      limit: 1,
    );
    if (rows.isEmpty) return 0;
    final item = Item.fromMap(rows.first);
    final sold = item.specialRollMetersSold + (metersSold < 0 ? 0 : metersSold);
    if (!stillAvailable) {
      final updated = item.copyWith(
        stockQty: kSpecialItemUnavailableStock,
        specialRollMetersSold: sold,
      );
      final result = await db.update(
        'items',
        updated.toMap(),
        where: 'id = ?',
        whereArgs: [itemId],
      );
      if (result > 0) _notifyDataChanged();
      return result;
    }
    if (!isMeterSoldFixedStockItemName(item.name)) return 0;
    final updated = item.copyWith(specialRollMetersSold: sold);
    final result = await db.update(
      'items',
      updated.toMap(),
      where: 'id = ?',
      whereArgs: [itemId],
    );
    if (result > 0) _notifyDataChanged();
    return result;
  }

  Future<int> upsertItem(Item item) async {
    final db = await database;
    Item itemToSave = item;
    if (isMeterSoldFixedStockItemName(item.name)) {
      if (item.id == null) {
        itemToSave = item.copyWith(stockQty: kSpecialItemUnavailableStock);
      } else {
        final sq = item.stockQty;
        itemToSave = item.copyWith(
          stockQty: sq > 0
              ? kSpecialItemAvailableStock
              : kSpecialItemUnavailableStock,
        );
      }
    }
    if (itemToSave.id == null) {
      final id = await db.transaction<int>((txn) async {
        var toInsert = itemToSave;
        final skuEmpty = (toInsert.sku ?? '').trim().isEmpty;
        final bcEmpty = (toInsert.barcode ?? '').trim().isEmpty;
        if (skuEmpty && bcEmpty) {
          final gen = await _generateNextInternalSkuForExecutor(txn);
          toInsert = toInsert.copyWith(sku: gen, barcode: gen);
        } else if (!skuEmpty && bcEmpty) {
          toInsert = toInsert.copyWith(barcode: toInsert.sku);
        } else if (skuEmpty && !bcEmpty) {
          toInsert = toInsert.copyWith(sku: toInsert.barcode);
        }
        return txn.insert('items', toInsert.toMap());
      });
      _notifyDataChanged();
      return id;
    }
    final result = await db.update(
      'items',
      itemToSave.toMap(),
      where: 'id = ?',
      whereArgs: [itemToSave.id],
    );
    _notifyDataChanged();
    return result;
  }

  Future<Item?> getItemById(int id) async {
    if (id <= 0) return null;
    final db = await database;
    final rows = await db.query(
      'items',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Item.fromMap(Map<String, dynamic>.from(rows.first));
  }

  String _normalizeCode(String? raw) => (raw ?? '').trim().toLowerCase();

  List<String> normalizeBarcodeList(Iterable<String> rawCodes) {
    final seen = <String>{};
    final result = <String>[];
    for (final raw in rawCodes) {
      final normalized = _normalizeCode(raw);
      if (normalized.isEmpty || seen.contains(normalized)) continue;
      seen.add(normalized);
      result.add(raw.trim());
    }
    return result;
  }

  Future<String> generateNextInternalSku() async {
    final db = await database;
    return _generateNextInternalSkuForExecutor(db);
  }

  Future<String> _generateNextInternalSkuForExecutor(DatabaseExecutor exec) async {
    final rows = await exec.query('items', columns: ['sku', 'barcode']);
    final taken = <String>{};
    final pattern = RegExp(r'^ITM(\d{6})$');
    var next = 1;
    for (final row in rows) {
      for (final key in ['sku', 'barcode']) {
        final code = (row[key] as String?)?.trim().toUpperCase() ?? '';
        if (code.isEmpty) continue;
        taken.add(code);
        final match = pattern.firstMatch(code);
        final number = int.tryParse(match?.group(1) ?? '');
        if (number != null && number >= next) next = number + 1;
      }
    }
    while (true) {
      final candidate = 'ITM${next.toString().padLeft(6, '0')}';
      if (!taken.contains(candidate)) return candidate;
      next++;
    }
  }

  /// One-time migration:
  /// - Ensure each item has an autogenerated primary code (ITM######) as SKU.
  /// - Move any pre-existing SKU/barcode into optional accepted codes list.
  Future<int> ensureGeneratedPrimaryCodesAndMoveLegacyCodes() async {
    final alreadyDone = (await _getAppMeta(_metaPrimaryCodeMigrationV1) ?? '').trim();
    if (alreadyDone == '1') return 0;

    final db = await database;
    const pattern = r'^ITM(\d{6})$';
    final generatedPattern = RegExp(pattern);
    var changed = 0;

    await db.transaction((txn) async {
      final itemRows = await txn.query(
        'items',
        columns: ['id', 'sku', 'barcode'],
      );

      final taken = <String>{};
      var next = 1;

      for (final row in itemRows) {
        for (final key in ['sku', 'barcode']) {
          final code = (row[key] as String? ?? '').trim().toUpperCase();
          if (code.isEmpty) continue;
          taken.add(code);
          final match = generatedPattern.firstMatch(code);
          final number = int.tryParse(match?.group(1) ?? '');
          if (number != null && number >= next) next = number + 1;
        }
      }

      for (final row in itemRows) {
        final itemId = row['id'] as int?;
        if (itemId == null) continue;

        final oldSku = (row['sku'] as String? ?? '').trim();
        final oldBarcode = (row['barcode'] as String? ?? '').trim();
        var newSku = oldSku;

        final legacyCodes = <String>[];
        var rowChanged = false;

        if (!generatedPattern.hasMatch(oldSku.toUpperCase())) {
          if (oldSku.isNotEmpty) legacyCodes.add(oldSku);
          while (true) {
            final candidate = 'ITM${next.toString().padLeft(6, '0')}';
            if (!taken.contains(candidate)) {
              newSku = candidate;
              taken.add(candidate);
              break;
            }
            next++;
          }
          rowChanged = true;
        }

        if (oldBarcode.isNotEmpty &&
            oldBarcode.toUpperCase() != newSku.toUpperCase()) {
          legacyCodes.add(oldBarcode);
          rowChanged = true;
        }

        final existingAliases = await txn.query(
          'item_barcodes',
          columns: ['code'],
          where: 'item_id = ?',
          whereArgs: [itemId],
          orderBy: 'id ASC',
        );
        for (final alias in existingAliases) {
          final code = (alias['code'] as String? ?? '').trim();
          if (code.isEmpty) continue;
          if (code.toUpperCase() == newSku.toUpperCase()) continue;
          legacyCodes.add(code);
        }

        final normalizedLegacy = normalizeBarcodeList(legacyCodes)
            .where((code) => code.toUpperCase() != newSku.toUpperCase())
            .toList();

        await txn.update(
          'items',
          {
            'sku': newSku,
            'barcode': newSku,
          },
          where: 'id = ?',
          whereArgs: [itemId],
        );

        await txn.delete(
          'item_barcodes',
          where: 'item_id = ?',
          whereArgs: [itemId],
        );
        for (final code in normalizedLegacy) {
          await txn.insert(
            'item_barcodes',
            {
              'item_id': itemId,
              'code': code.trim(),
              'created_at': DateTime.now().toIso8601String(),
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }

        if (rowChanged || normalizedLegacy.isNotEmpty) {
          changed++;
        }
      }

      await txn.insert(
        'app_meta',
        {
          'key': _metaPrimaryCodeMigrationV1,
          'value': '1',
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });

    if (changed > 0) _notifyDataChanged();
    return changed;
  }

  Future<String?> findConflictingBarcode(
    Iterable<String> codes, {
    int? excludingItemId,
  }) async {
    final db = await database;
    for (final raw in normalizeBarcodeList(codes)) {
      final code = raw.trim();
      if (code.isEmpty) continue;
      final itemRows = await db.query(
        'items',
        columns: ['id'],
        where: '(sku = ? COLLATE NOCASE OR barcode = ? COLLATE NOCASE)',
        whereArgs: [code, code],
      );
      final itemConflict = itemRows.where((row) {
        final id = row['id'] as int?;
        return id != null && id != excludingItemId;
      }).isNotEmpty;
      if (itemConflict) return code;
      final aliasRows = await db.query(
        'item_barcodes',
        columns: ['item_id'],
        where: 'code = ? COLLATE NOCASE',
        whereArgs: [code],
      );
      final aliasConflict = aliasRows.where((row) {
        final id = row['item_id'] as int?;
        return id != null && id != excludingItemId;
      }).isNotEmpty;
      if (aliasConflict) return code;
    }
    return null;
  }

  Future<void> replaceItemBarcodes({
    required int itemId,
    required Iterable<String> barcodes,
  }) async {
    final db = await database;
    final normalized = normalizeBarcodeList(barcodes);
    await db.transaction((txn) async {
      await txn.delete('item_barcodes', where: 'item_id = ?', whereArgs: [itemId]);
      for (final code in normalized) {
        await txn.insert('item_barcodes', {
          'item_id': itemId,
          'code': code.trim(),
          'created_at': DateTime.now().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
    _notifyDataChanged();
  }

  Future<List<String>> getItemBarcodes(int itemId) async {
    final db = await database;
    final rows = await db.query(
      'item_barcodes',
      columns: ['code'],
      where: 'item_id = ?',
      whereArgs: [itemId],
      orderBy: 'id ASC',
    );
    return rows
        .map((row) => (row['code'] as String? ?? '').trim())
        .where((code) => code.isNotEmpty)
        .toList();
  }

  Future<Map<int, List<String>>> getItemBarcodesMap({
    Iterable<int>? itemIds,
  }) async {
    final db = await database;
    final whereIds = itemIds?.where((id) => id > 0).toList() ?? <int>[];
    final rows = whereIds.isEmpty
        ? await db.query(
            'item_barcodes',
            columns: ['item_id', 'code'],
            orderBy: 'item_id ASC, id ASC',
          )
        : await db.query(
            'item_barcodes',
            columns: ['item_id', 'code'],
            where:
                'item_id IN (${List.filled(whereIds.length, '?').join(',')})',
            whereArgs: whereIds,
            orderBy: 'item_id ASC, id ASC',
          );
    final map = <int, List<String>>{};
    for (final row in rows) {
      final itemId = row['item_id'] as int?;
      final code = (row['code'] as String? ?? '').trim();
      if (itemId == null || code.isEmpty) continue;
      map.putIfAbsent(itemId, () => []).add(code);
    }
    return map;
  }

  Future<Item?> findItemByAnyCode(
    String code, {
    int? excludingItemId,
  }) async {
    final normalized = code.trim();
    if (normalized.isEmpty) return null;
    final db = await database;
    final directRows = await db.query(
      'items',
      where: '(sku = ? COLLATE NOCASE OR barcode = ? COLLATE NOCASE)',
      whereArgs: [normalized, normalized],
      limit: 5,
    );
    for (final row in directRows) {
      final id = row['id'] as int?;
      if (id != null && id != excludingItemId) {
        return Item.fromMap(row);
      }
    }
    final aliasRows = await db.query(
      'item_barcodes',
      columns: ['item_id'],
      where: 'code = ? COLLATE NOCASE',
      whereArgs: [normalized],
      limit: 5,
    );
    for (final row in aliasRows) {
      final itemId = row['item_id'] as int?;
      if (itemId == null || itemId == excludingItemId) continue;
      final itemRows = await db.query(
        'items',
        where: 'id = ?',
        whereArgs: [itemId],
        limit: 1,
      );
      if (itemRows.isNotEmpty) return Item.fromMap(itemRows.first);
    }
    return null;
  }

  Future<int> deleteItem(int itemId) async {
    final db = await database;
    final result = await db.delete(
      'items',
      where: 'id = ?',
      whereArgs: [itemId],
    );
    if (result > 0) _notifyDataChanged();
    return result;
  }

  /// Adjusts item stock by [delta]. Negative delta = reduce stock (e.g. sale), positive = add back (e.g. remove from cart).
  Future<int> adjustItemStock(int itemId, double delta) async {
    final db = await database;
    final rows = await db.query(
      'items',
      where: 'id = ?',
      whereArgs: [itemId],
      limit: 1,
    );
    if (rows.isEmpty) return 0;
    final item = Item.fromMap(rows.first);
    if (isMeterSoldFixedStockItemName(item.name)) {
      return 0;
    }
    final newQty = item.stockQty + delta;
    if (newQty < 0) return 0;
    final result = await db.update(
      'items',
      item.copyWith(stockQty: newQty).toMap(),
      where: 'id = ?',
      whereArgs: [itemId],
    );
    if (result > 0) _notifyDataChanged();
    return result;
  }

  Future<List<Item>> getItems({int? storeId}) async {
    final cache = MotherDataCache.instance;
    if (cache.itemsApplied) {
      return cache.getItems(storeId: storeId);
    }
    final db = await database;
    final maps = await db.query(
      'items',
      where: storeId != null ? 'store_id = ?' : null,
      whereArgs: storeId != null ? [storeId] : null,
      orderBy: 'name COLLATE NOCASE ASC',
    );
    return maps.map(Item.fromMap).toList();
  }

  Future<List<Item>> getOutOfStockItems({int? storeId}) async {
    final db = await database;
    final maps = await db.query(
      'items',
      where: storeId != null
          ? 'store_id = ? AND stock_qty <= 0'
          : 'stock_qty <= 0',
      whereArgs: storeId != null ? [storeId] : null,
      orderBy: 'name COLLATE NOCASE ASC',
    );
    return maps.map(Item.fromMap).toList();
  }

  Future<List<Item>> getReorderItems({int? storeId}) async {
    final cache = MotherDataCache.instance;
    if (cache.itemsApplied) {
      return cache.getReorderItems(storeId: storeId);
    }
    final db = await database;
    final maps = await db.query(
      'items',
      where: storeId != null
          ? 'store_id = ? AND (stock_qty <= reorder_level OR stock_qty <= 0)'
          : '(stock_qty <= reorder_level OR stock_qty <= 0)',
      whereArgs: storeId != null ? [storeId] : null,
      orderBy: 'name COLLATE NOCASE ASC',
    );
    return maps
        .map(Item.fromMap)
        .where((e) => !isMeterSoldFixedStockItemName(e.name))
        .toList();
  }

  // ===== PRODUCT CATEGORIES =====

  Future<int> insertCategory(ProductCategory category) async {
    final db = await database;
    final result = await db.insert('product_categories', category.toMap());
    _notifyDataChanged();
    return result;
  }

  Future<List<ProductCategory>> getCategories() async {
    final db = await database;
    final maps = await db.query(
      'product_categories',
      orderBy:
          'main_category COLLATE NOCASE ASC, sub_category COLLATE NOCASE ASC',
    );
    return maps.map(ProductCategory.fromMap).toList();
  }

  Future<int> updateCategory(ProductCategory category) async {
    if (category.id == null) return 0;
    final db = await database;
    final result = await db.update(
      'product_categories',
      category.toMap(),
      where: 'id = ?',
      whereArgs: [category.id],
    );
    if (result > 0) _notifyDataChanged();
    return result;
  }

  Future<int> deleteCategoryById(int id) async {
    final db = await database;
    final result = await db.delete(
      'product_categories',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (result > 0) _notifyDataChanged();
    return result;
  }

  /// Returns categories grouped by main_category for display (main -> list of sub).
  Future<Map<String, List<String>>> getCategoriesGroupedByMain() async {
    final list = await getCategories();
    final map = <String, List<String>>{};
    for (final c in list) {
      map.putIfAbsent(c.mainCategory, () => []).add(c.subCategory);
    }
    return map;
  }

  // ===== UNITS =====

  Future<int> insertUnit(Unit unit) async {
    final db = await database;
    final result = await db.insert('units', unit.toMap());
    _notifyDataChanged();
    return result;
  }

  Future<int> updateUnit(Unit unit) async {
    if (unit.id == null) return 0;
    final db = await database;
    final result = await db.update(
      'units',
      unit.toMap(),
      where: 'id = ?',
      whereArgs: [unit.id],
    );
    if (result > 0) _notifyDataChanged();
    return result;
  }

  Future<int> deleteUnit(int unitId) async {
    final db = await database;
    final result = await db.delete(
      'units',
      where: 'id = ?',
      whereArgs: [unitId],
    );
    if (result > 0) _notifyDataChanged();
    return result;
  }

  Future<List<Unit>> getUnits() async {
    final db = await database;
    final maps = await db.query(
      'units',
      orderBy: 'unit_name COLLATE NOCASE ASC',
    );
    return maps.map(Unit.fromMap).toList();
  }

  // ===== PACKAGINGS =====

  Future<int> insertPackaging(Packaging packaging) async {
    final db = await database;
    final result = await db.insert('packagings', packaging.toMap());
    _notifyDataChanged();
    return result;
  }

  Future<int> updatePackaging(Packaging packaging) async {
    if (packaging.id == null) return 0;
    final db = await database;
    final result = await db.update(
      'packagings',
      packaging.toMap(),
      where: 'id = ?',
      whereArgs: [packaging.id],
    );
    if (result > 0) _notifyDataChanged();
    return result;
  }

  Future<int> deletePackaging(int packagingId) async {
    final db = await database;
    final result = await db.delete(
      'packagings',
      where: 'id = ?',
      whereArgs: [packagingId],
    );
    if (result > 0) _notifyDataChanged();
    return result;
  }

  Future<List<Packaging>> getPackagings() async {
    final db = await database;
    final maps = await db.query(
      'packagings',
      orderBy: 'name COLLATE NOCASE ASC',
    );
    return maps.map(Packaging.fromMap).toList();
  }

  // ===== EXPENSE CATEGORIES =====

  Future<int> insertExpenseCategory(ExpenseCategory category) async {
    final db = await database;
    final result = await db.insert('expense_categories', category.toMap());
    _notifyDataChanged();
    return result;
  }

  Future<int> updateExpenseCategory(ExpenseCategory category) async {
    if (category.id == null) return 0;
    final db = await database;
    final result = await db.update(
      'expense_categories',
      category.toMap(),
      where: 'id = ?',
      whereArgs: [category.id],
    );
    if (result > 0) _notifyDataChanged();
    return result;
  }

  Future<int> deleteExpenseCategory(int id) async {
    final db = await database;
    final rows = await db.query(
      'expense_categories',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    final parentId = rows.isNotEmpty ? rows.first['parent_id'] as int? : null;
    await db.update(
      'expense_categories',
      {'parent_id': parentId},
      where: 'parent_id = ?',
      whereArgs: [id],
    );
    final result = await db.delete(
      'expense_categories',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (result > 0) _notifyDataChanged();
    return result;
  }

  Future<List<ExpenseCategory>> getExpenseCategories() async {
    final db = await database;
    final maps = await db.query(
      'expense_categories',
      orderBy: 'name COLLATE NOCASE ASC',
    );
    final list = maps.map(ExpenseCategory.fromMap).toList();
    return _computeExpenseCategoryPaths(list);
  }

  /// Returns categories with path computed. Use for expense dropdown and for parent dropdown.
  Future<List<ExpenseCategory>> getExpenseCategoriesWithPath() async {
    return getExpenseCategories();
  }

  /// Excludes [categoryId] and any of its descendants. Use for parent dropdown when editing.
  List<ExpenseCategory> excludeSelfAndDescendants(
    List<ExpenseCategory> categories,
    int? categoryId,
  ) {
    if (categoryId == null) return categories;
    final idsToExclude = <int>{categoryId};
    void collectDescendants(int id) {
      for (final c in categories) {
        if (c.parentId == id) {
          if (c.id != null) {
            idsToExclude.add(c.id!);
            collectDescendants(c.id!);
          }
        }
      }
    }

    collectDescendants(categoryId);
    return categories
        .where((c) => c.id == null || !idsToExclude.contains(c.id!))
        .toList();
  }

  static List<ExpenseCategory> _computeExpenseCategoryPaths(
    List<ExpenseCategory> list,
  ) {
    final idToCat = {for (final c in list) c.id: c};
    final result = <ExpenseCategory>[];
    for (final cat in list) {
      final pathParts = <String>[];
      ExpenseCategory? c = cat;
      final seen = <int?>{};
      while (c != null) {
        if (c.id != null && seen.contains(c.id)) break;
        if (c.id != null) seen.add(c.id);
        pathParts.insert(0, c.name);
        c = c.parentId != null ? idToCat[c.parentId] : null;
      }
      final path = pathParts.join(' > ');
      result.add(cat.copyWith(path: path));
    }
    result.sort((a, b) => (a.path ?? a.name).compareTo(b.path ?? b.name));
    return result;
  }

  Future<int> receiveStock({
    required int itemId,
    required double quantity,
    double? unitCost,
    double? totalCost,
    double? sellingPrice,
    String? brand,
    DateTime? expiryDate,
    DateTime? receivedAt,
    int? storeId,
  }) async {
    final db = await database;
    final effectiveTotal = totalCost ?? (quantity * (unitCost ?? 0));
    final effectiveUnitCost = quantity > 0 ? effectiveTotal / quantity : 0.0;

    final updatedRows = await db.transaction<int>((txn) async {
      final maps = await txn.query(
        'items',
        where: 'id = ?',
        whereArgs: [itemId],
        limit: 1,
      );
      if (maps.isEmpty) return 0;

      final item = Item.fromMap(maps.first);
      final fixedStock = isMeterSoldFixedStockItemName(item.name);
      final oldQty = item.stockQty;
      final metresOnRoll = fixedStock ? quantity : 0.0;
      final receiptQty = fixedStock ? 1.0 : quantity;
      final newQty = fixedStock
          ? kSpecialItemAvailableStock
          : oldQty + quantity;
      final unitCostForReceipt = fixedStock
          ? (metresOnRoll > 0 ? effectiveTotal / metresOnRoll : effectiveUnitCost)
          : effectiveUnitCost;

      final receipt = StockReceipt(
        storeId: storeId ?? item.storeId,
        itemId: itemId,
        quantity: receiptQty,
        unitCost: unitCostForReceipt,
        totalCost: effectiveTotal,
        unitSell: item.sellingPrice,
        oldQty: oldQty,
        newQty: newQty,
        brand: brand,
        expiryDate: expiryDate,
        receivedAt: receivedAt,
      );

      await txn.insert('stock_receipts', receipt.toMap());

      final updated = fixedStock
          ? item.copyWith(
              stockQty: kSpecialItemAvailableStock,
              specialRollMetersTotal: metresOnRoll,
              specialRollMetersSold: 0,
              costPrice: unitCostForReceipt,
              sellingPrice: sellingPrice ?? item.sellingPrice,
            )
          : item.copyWith(
              stockQty: newQty,
              costPrice: effectiveUnitCost,
              sellingPrice: sellingPrice ?? item.sellingPrice,
            );
      return txn.update(
        'items',
        updated.toMap(),
        where: 'id = ?',
        whereArgs: [itemId],
      );
    });
    if (updatedRows > 0) _notifyDataChanged();
    return updatedRows;
  }

  Future<int> transferStock({
    required int fromItemId,
    required int toItemId,
    required double fromQuantity,
    required double conversionFactor,
    double? toCostPrice,
    double? toSellingPrice,
    double? fromCostPrice,
    int? storeId,
    String? notes,
  }) async {
    if (fromItemId == toItemId) {
      throw ArgumentError('Source and destination item must be different.');
    }
    if (fromQuantity <= 0 || conversionFactor <= 0) {
      throw ArgumentError('Quantity and conversion factor must be greater than zero.');
    }
    final db = await database;
    final toQuantity = fromQuantity * conversionFactor;
    final changed = await db.transaction<int>((txn) async {
      final fromRows = await txn.query(
        'items',
        where: 'id = ?',
        whereArgs: [fromItemId],
        limit: 1,
      );
      final toRows = await txn.query(
        'items',
        where: 'id = ?',
        whereArgs: [toItemId],
        limit: 1,
      );
      if (fromRows.isEmpty || toRows.isEmpty) {
        throw StateError('Source or destination item not found.');
      }

      final fromItem = Item.fromMap(fromRows.first);
      final toItem = Item.fromMap(toRows.first);
      if (isMeterSoldFixedStockItemName(fromItem.name) ||
          isMeterSoldFixedStockItemName(toItem.name)) {
        throw ArgumentError(
          'Transfers are not supported for fixed-stock items (Ekiveera, carpet, ebinyobwa).',
        );
      }
      final oldFromQty = fromItem.stockQty;
      final oldToQty = toItem.stockQty;
      if (oldFromQty < fromQuantity) {
        throw StateError('Not enough source stock for this transfer.');
      }
      final newFromQty = oldFromQty - fromQuantity;
      final newToQty = oldToQty + toQuantity;

      final fromUpdate = fromCostPrice != null && fromCostPrice > 0
          ? fromItem.copyWith(stockQty: newFromQty, costPrice: fromCostPrice)
          : fromItem.copyWith(stockQty: newFromQty);
      await txn.update(
        'items',
        fromUpdate.toMap(),
        where: 'id = ?',
        whereArgs: [fromItemId],
      );
      final updatedTo = toItem.copyWith(
        stockQty: newToQty,
        costPrice: toCostPrice ?? toItem.costPrice,
        sellingPrice: toSellingPrice ?? toItem.sellingPrice,
      );
      await txn.update(
        'items',
        updatedTo.toMap(),
        where: 'id = ?',
        whereArgs: [toItemId],
      );

      return txn.insert('stock_transfers', {
        'store_id': storeId ?? fromItem.storeId ?? toItem.storeId,
        'from_item_id': fromItemId,
        'to_item_id': toItemId,
        'from_quantity': fromQuantity,
        'to_quantity': toQuantity,
        'conversion_factor': conversionFactor,
        'old_from_qty': oldFromQty,
        'new_from_qty': newFromQty,
        'old_to_qty': oldToQty,
        'new_to_qty': newToQty,
        'notes': notes,
        'created_at': DateTime.now().toIso8601String(),
      });
    });
    if (changed > 0) _notifyDataChanged();
    return changed;
  }

  Future<List<Map<String, Object?>>> getStockReceiptsWithDetails() async {
    final db = await database;
    return db.rawQuery('''
      SELECT
        r.id,
        r.store_id,
        r.item_id,
        r.quantity,
        r.unit_cost,
        r.total_cost,
        r.unit_sell,
        r.old_qty,
        r.new_qty,
        r.brand,
        r.expiry_date,
        r.received_at,
        i.name AS item_name,
        i.unit AS item_unit,
        s.name AS store_name
      FROM stock_receipts r
      LEFT JOIN items i ON i.id = r.item_id
      LEFT JOIN stores s ON s.id = r.store_id
      ORDER BY r.received_at DESC
    ''');
  }

  Future<List<Map<String, Object?>>> getStockReceiptsForItemWithDetails(
    int itemId,
  ) async {
    final db = await database;
    return db.rawQuery(
      '''
      SELECT
        r.id,
        r.store_id,
        r.item_id,
        r.quantity,
        r.unit_cost,
        r.total_cost,
        r.unit_sell,
        r.old_qty,
        r.new_qty,
        r.brand,
        r.expiry_date,
        r.received_at,
        i.name AS item_name,
        i.unit AS item_unit,
        s.name AS store_name
      FROM stock_receipts r
      LEFT JOIN items i ON i.id = r.item_id
      LEFT JOIN stores s ON s.id = r.store_id
      WHERE r.item_id = ?
      ORDER BY r.received_at DESC
    ''',
      [itemId],
    );
  }

  // ===== SALES =====

  bool _isServiceSaleCategory(String? category) {
    final raw = (category ?? '').trim();
    if (raw.isEmpty) return false;
    String? sale;
    for (final part in raw.split('|').map((p) => p.trim())) {
      if (part.toLowerCase().startsWith('sale:')) {
        sale = part.substring(part.indexOf(':') + 1).trim().toLowerCase();
        break;
      }
    }
    sale ??= raw.toLowerCase();
    return sale == 'service';
  }

  Future<int> createSale(Sale sale, List<SaleItem> items) async {
    final db = await database;
    final saleId = await db.transaction<int>((txn) async {
      final saleId = await txn.insert('sales', sale.toMap());

      for (final item in items) {
        final saleItem = item.toMap()..['sale_id'] = saleId;
        await txn.insert('sale_items', saleItem);

        // Reduce stock at hand when the receipt is saved successfully
        final itemRows = await txn.query(
          'items',
          where: 'id = ?',
          whereArgs: [item.itemId],
          limit: 1,
        );
        if (itemRows.isNotEmpty) {
          final existing = Item.fromMap(itemRows.first);
          if (_isServiceSaleCategory(existing.category) ||
              isMeterSoldFixedStockItemName(existing.name)) {
            continue;
          }
          final newQty = existing.stockQty - item.quantity;
          if (newQty < -0.0001) {
            throw StateError(
              'Not enough stock for this item. Available: ${existing.stockQty}.',
            );
          }
          await txn.update(
            'items',
            existing.copyWith(stockQty: newQty).toMap(),
            where: 'id = ?',
            whereArgs: [item.itemId],
          );
        }
      }

      // If balance > 0, create a debt record (customer name etc. must be set by caller)
      final balance = sale.balance ?? 0;
      if (balance > 0 &&
          sale.customerName != null &&
          sale.customerName!.trim().isNotEmpty) {
        final debt = Debt(
          storeId: sale.storeId,
          customerName: sale.customerName!.trim(),
          phone: sale.customerPhone?.trim().isEmpty ?? true
              ? null
              : sale.customerPhone?.trim(),
          address: sale.customerAddress?.trim().isEmpty ?? true
              ? null
              : sale.customerAddress?.trim(),
          amount: balance,
        );
        await txn.insert('debts', debt.toMap());
      }

      return saleId;
    });
    if (saleId > 0) _notifyDataChanged();
    return saleId;
  }

  Future<List<Sale>> getAllSales() async {
    final db = await database;
    final maps = await db.query('sales', orderBy: 'created_at DESC');
    return maps.map(Sale.fromMap).toList();
  }

  Future<List<Map<String, Object?>>> getSalesWithItemDetails() async {
    final db = await database;
    return db.rawQuery('''
      SELECT
        s.id AS sale_id,
        s.total_amount,
        s.overall_discount,
        s.amount_received,
        s.balance,
        s.customer_name,
        s.customer_phone,
        s.customer_address,
        s.payment_method,
        s.created_at,
        si.quantity,
        si.unit_price,
        si.product_discount,
        si.line_total,
        i.name AS item_name,
        i.unit AS item_unit,
        i.category AS item_category
      FROM sales s
      JOIN sale_items si ON si.sale_id = s.id
      LEFT JOIN items i ON i.id = si.item_id
      ORDER BY s.created_at DESC, si.id ASC
    ''');
  }

  Future<List<Map<String, Object?>>> getSalesWithItemDetailsInRange({
    required DateTime start,
    required DateTime end,
  }) async {
    final db = await database;
    return db.rawQuery(
      '''
      SELECT
        s.id AS sale_id,
        s.total_amount,
        s.overall_discount,
        s.amount_received,
        s.balance,
        s.customer_name,
        s.customer_phone,
        s.customer_address,
        s.payment_method,
        s.created_at,
        si.quantity,
        si.unit_price,
        si.product_discount,
        si.line_total,
        i.name AS item_name,
        i.unit AS item_unit,
        i.category AS item_category
      FROM sales s
      JOIN sale_items si ON si.sale_id = s.id
      LEFT JOIN items i ON i.id = si.item_id
      WHERE s.created_at >= ? AND s.created_at <= ?
      ORDER BY s.created_at DESC, si.id ASC
      ''',
      [start.toIso8601String(), end.toIso8601String()],
    );
  }

  Future<List<Map<String, Object?>>> getSalesWithItemDetailsByCustomer(
    String customerName,
  ) async {
    final db = await database;
    return db.rawQuery(
      '''
      SELECT
        s.id AS sale_id,
        s.total_amount,
        s.overall_discount,
        s.amount_received,
        s.balance,
        s.customer_name,
        s.customer_phone,
        s.customer_address,
        s.payment_method,
        s.created_at,
        si.quantity,
        si.unit_price,
        si.product_discount,
        si.line_total,
        i.name AS item_name,
        i.unit AS item_unit,
        i.category AS item_category
      FROM sales s
      JOIN sale_items si ON si.sale_id = s.id
      LEFT JOIN items i ON i.id = si.item_id
      WHERE lower(trim(s.customer_name)) = lower(trim(?))
      ORDER BY s.created_at DESC, si.id ASC
      ''',
      [customerName],
    );
  }

  Future<List<Map<String, Object?>>> getSaleRowsForItem(int itemId) async {
    final db = await database;
    return db.rawQuery(
      '''
      SELECT
        si.id AS sale_item_id,
        si.sale_id,
        si.item_id,
        si.quantity,
        si.unit_price,
        si.line_total,
        s.created_at AS sold_at,
        s.store_id,
        s.customer_name
      FROM sale_items si
      JOIN sales s ON s.id = si.sale_id
      WHERE si.item_id = ?
      ORDER BY s.created_at DESC, si.id DESC
      ''',
      [itemId],
    );
  }

  Future<List<Map<String, Object?>>> getTransferRowsForItem(int itemId) async {
    final db = await database;
    return db.rawQuery(
      '''
      SELECT
        t.id,
        t.store_id,
        t.from_item_id,
        t.to_item_id,
        t.from_quantity,
        t.to_quantity,
        t.conversion_factor,
        t.old_from_qty,
        t.new_from_qty,
        t.old_to_qty,
        t.new_to_qty,
        t.notes,
        t.created_at,
        fi.name AS from_item_name,
        ti.name AS to_item_name
      FROM stock_transfers t
      LEFT JOIN items fi ON fi.id = t.from_item_id
      LEFT JOIN items ti ON ti.id = t.to_item_id
      WHERE t.from_item_id = ? OR t.to_item_id = ?
      ORDER BY t.created_at DESC, t.id DESC
      ''',
      [itemId, itemId],
    );
  }

  Future<List<Map<String, Object?>>> getStockTransfersWithDetails() async {
    final db = await database;
    return db.rawQuery(
      '''
      SELECT
        t.id,
        t.store_id,
        t.from_item_id,
        t.to_item_id,
        t.from_quantity,
        t.to_quantity,
        t.conversion_factor,
        t.old_from_qty,
        t.new_from_qty,
        t.old_to_qty,
        t.new_to_qty,
        t.notes,
        t.created_at,
        fi.name AS from_item_name,
        fi.unit AS from_item_unit,
        ti.name AS to_item_name,
        ti.unit AS to_item_unit
      FROM stock_transfers t
      LEFT JOIN items fi ON fi.id = t.from_item_id
      LEFT JOIN items ti ON ti.id = t.to_item_id
      ORDER BY t.created_at DESC, t.id DESC
      ''',
    );
  }

  Future<double> getTodaySalesTotal({int? storeId}) async {
    final db = await database;
    final now = DateTime.now();
    final todayKey =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final result = await db.rawQuery('''
      SELECT SUM(total_amount) as total
      FROM sales
      WHERE substr(created_at, 1, 10) = ?
      ${storeId != null ? 'AND store_id = ?' : ''}
      ''', storeId != null ? [todayKey, storeId] : [todayKey]);
    final value = result.first['total'] as num?;
    return value?.toDouble() ?? 0;
  }

  Future<int> getTodaySalesCount({int? storeId}) async {
    final db = await database;
    final now = DateTime.now();
    final todayKey =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final result = await db.rawQuery('''
      SELECT COUNT(*) as count
      FROM sales
      WHERE substr(created_at, 1, 10) = ?
      ${storeId != null ? 'AND store_id = ?' : ''}
      ''', storeId != null ? [todayKey, storeId] : [todayKey]);
    final value = result.first['count'] as int?;
    return value ?? 0;
  }

  // ===== DEBTS =====

  Future<int> upsertDebt(Debt debt) async {
    final db = await database;
    int result;
    if (debt.id == null) {
      result = await db.insert('debts', debt.toMap());
    } else {
      result = await db.update(
        'debts',
        debt.toMap(),
        where: 'id = ?',
        whereArgs: [debt.id],
      );
    }
    _notifyDataChanged();
    return result;
  }

  Future<int> markDebtsPaidByCustomer(String customerName) async {
    final db = await database;
    final result = await db.update(
      'debts',
      {'is_paid': 1},
      where: 'is_paid = 0 AND lower(trim(customer_name)) = lower(trim(?))',
      whereArgs: [customerName],
    );
    if (result > 0) _notifyDataChanged();
    return result;
  }

  Future<double> payDebtForCustomer({
    required String customerName,
    required double paymentAmount,
  }) async {
    if (paymentAmount <= 0) {
      throw ArgumentError('Payment amount must be greater than zero.');
    }
    final db = await database;
    final normalizedName = customerName.trim();

    final remainingBalance = await db.transaction<double>((txn) async {
      final result = await _applyDebtPaymentTxn(
        txn: txn,
        customerName: normalizedName,
        paymentAmount: paymentAmount,
      );
      return result.remaining;
    });

    _notifyDataChanged();
    return remainingBalance;
  }

  Future<double> payDebtForCustomerFromClientAccount({
    required int clientId,
    required String customerName,
    required double paymentAmount,
    int? storeId,
  }) async {
    if (paymentAmount <= 0) {
      throw ArgumentError('Payment amount must be greater than zero.');
    }
    final db = await database;
    final normalizedName = customerName.trim();
    final remainingBalance = await db.transaction<double>((txn) async {
      final balRows = await txn.rawQuery(
        'SELECT SUM(amount) AS total FROM client_account_transactions WHERE client_id = ?',
        [clientId],
      );
      final current = (balRows.first['total'] as num?)?.toDouble() ?? 0;
      if (current < paymentAmount) {
        throw StateError('Insufficient client account balance.');
      }
      final result = await _applyDebtPaymentTxn(
        txn: txn,
        customerName: normalizedName,
        paymentAmount: paymentAmount,
      );
      await txn.insert('client_account_transactions', {
        'store_id': storeId ?? result.storeId,
        'client_id': clientId,
        'transaction_type': 'debt_payment',
        'amount': -paymentAmount,
        'note': 'Debt payment for $normalizedName',
        'created_at': DateTime.now().toIso8601String(),
      });
      return result.remaining;
    });
    _notifyDataChanged();
    return remainingBalance;
  }

  Future<({double remaining, int? storeId})> _applyDebtPaymentTxn({
    required Transaction txn,
    required String customerName,
    required double paymentAmount,
  }) async {
    final saleRows = await txn.query(
      'sales',
      where: 'lower(trim(customer_name)) = lower(trim(?)) AND balance > 0',
      whereArgs: [customerName],
      orderBy: 'created_at ASC, id ASC',
    );
    double remainingForSales = paymentAmount;
    for (final row in saleRows) {
      if (remainingForSales <= 0) break;
      final saleId = row['id'] as int?;
      if (saleId == null) continue;
      final totalAmount = (row['total_amount'] as num?)?.toDouble() ?? 0;
      final amountReceived = (row['amount_received'] as num?)?.toDouble() ?? 0;
      final balance = (row['balance'] as num?)?.toDouble() ?? 0;
      if (balance <= 0) continue;
      final applied = remainingForSales >= balance ? balance : remainingForSales;
      final newReceived = amountReceived + applied;
      final newBalance = totalAmount - newReceived;
      await txn.update(
        'sales',
        {
          'amount_received': newReceived,
          'balance': newBalance < 0 ? 0 : newBalance,
        },
        where: 'id = ?',
        whereArgs: [saleId],
      );
      remainingForSales -= applied;
    }

    final rows = await txn.query(
      'debts',
      where: 'is_paid = 0 AND lower(trim(customer_name)) = lower(trim(?))',
      whereArgs: [customerName],
      orderBy: 'created_at ASC, id ASC',
    );
    double remainingPayment = paymentAmount;
    int? paymentStoreId;
    if (rows.isNotEmpty) {
      paymentStoreId = rows.first['store_id'] as int?;
    }
    for (final row in rows) {
      if (remainingPayment <= 0) break;
      final debtId = row['id'] as int?;
      if (debtId == null) continue;
      final amount = (row['amount'] as num?)?.toDouble() ?? 0;
      if (amount <= 0) {
        await txn.update(
          'debts',
          {'amount': 0, 'is_paid': 1},
          where: 'id = ?',
          whereArgs: [debtId],
        );
        continue;
      }
      if (remainingPayment >= amount) {
        remainingPayment -= amount;
        await txn.update(
          'debts',
          {'amount': 0, 'is_paid': 1},
          where: 'id = ?',
          whereArgs: [debtId],
        );
      } else {
        final newAmount = amount - remainingPayment;
        remainingPayment = 0;
        await txn.update(
          'debts',
          {'amount': newAmount, 'is_paid': 0},
          where: 'id = ?',
          whereArgs: [debtId],
        );
      }
    }

    final balanceRows = await txn.rawQuery(
      '''
      SELECT SUM(amount) as total
      FROM debts
      WHERE is_paid = 0 AND lower(trim(customer_name)) = lower(trim(?))
      ''',
      [customerName],
    );
    final total = (balanceRows.first['total'] as num?)?.toDouble() ?? 0;
    await txn.insert(
      'debt_payments',
      DebtPayment(
        storeId: paymentStoreId,
        customerName: customerName,
        paidAmount: paymentAmount,
        remainingBalance: total,
      ).toMap(),
    );
    return (remaining: total, storeId: paymentStoreId);
  }

  Future<List<DebtPayment>> getDebtPayments({String? customerName}) async {
    final db = await database;
    final maps = await db.query(
      'debt_payments',
      where: customerName != null
          ? 'lower(trim(customer_name)) = lower(trim(?))'
          : null,
      whereArgs: customerName != null ? [customerName] : null,
      orderBy: 'created_at DESC',
    );
    return maps.map(DebtPayment.fromMap).toList();
  }

  Future<List<Debt>> getDebts({int? storeId, bool? isPaid}) async {
    final db = await database;

    final where = <String>[];
    final args = <Object?>[];

    if (storeId != null) {
      where.add('store_id = ?');
      args.add(storeId);
    }
    if (isPaid != null) {
      where.add('is_paid = ?');
      args.add(isPaid ? 1 : 0);
    }

    final maps = await db.query(
      'debts',
      where: where.isNotEmpty ? where.join(' AND ') : null,
      whereArgs: args.isNotEmpty ? args : null,
      orderBy: 'created_at DESC',
    );

    return maps.map(Debt.fromMap).toList();
  }

  Future<double> getOutstandingDebtTotal({int? storeId}) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT SUM(amount) as total
      FROM debts
      WHERE is_paid = 0
      ${storeId != null ? 'AND store_id = ?' : ''}
      ''', storeId != null ? [storeId] : []);
    final value = result.first['total'] as num?;
    return value?.toDouble() ?? 0;
  }

  Future<double> getOutstandingDebtForCustomer(String customerName) async {
    final db = await database;
    final result = await db.rawQuery(
      '''
      SELECT SUM(amount) as total
      FROM debts
      WHERE is_paid = 0 AND lower(trim(customer_name)) = lower(trim(?))
      ''',
      [customerName],
    );
    final value = result.first['total'] as num?;
    return value?.toDouble() ?? 0;
  }

  Future<int> getOutOfStockCount({int? storeId}) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT COUNT(*) as count
      FROM items
      WHERE stock_qty <= 0
      ${storeId != null ? 'AND store_id = ?' : ''}
      ''', storeId != null ? [storeId] : []);
    final value = result.first['count'] as int?;
    return value ?? 0;
  }

  Future<int> getReorderCount({int? storeId}) async {
    final items = await getReorderItems(storeId: storeId);
    return items.length;
  }

  // ===== LOANS =====

  Future<List<Loan>> getLoans() async {
    final db = await database;
    final rows = await db.query(
      'loans',
      orderBy: 'datetime(created_at) DESC, id DESC',
    );
    return rows
        .map((r) => Loan.fromMap(Map<String, dynamic>.from(r)))
        .toList();
  }

  Future<int> upsertLoan(Loan loan) async {
    final db = await database;
    final map = Map<String, Object?>.from(loan.toMap());
    int result;
    if (loan.id == null) {
      map.remove('id');
      result = await db.insert('loans', map);
    } else {
      result = await db.update(
        'loans',
        map,
        where: 'id = ?',
        whereArgs: [loan.id],
      );
    }
    _notifyDataChanged();
    return result;
  }

  Future<List<Loan>> getLoansForClient(int clientId) async {
    final db = await database;
    final rows = await db.query(
      'loans',
      where: 'client_id = ?',
      whereArgs: [clientId],
      orderBy: 'datetime(created_at) DESC, id DESC',
    );
    return rows.map((r) => Loan.fromMap(Map<String, dynamic>.from(r))).toList();
  }

  Future<List<Map<String, Object?>>> getLoanPayments({
    int? loanId,
    int? clientId,
  }) async {
    final db = await database;
    final where = <String>[];
    final args = <Object?>[];
    if (loanId != null) {
      where.add('loan_id = ?');
      args.add(loanId);
    }
    if (clientId != null) {
      where.add('client_id = ?');
      args.add(clientId);
    }
    final rows = await db.query(
      'loan_payments',
      where: where.isNotEmpty ? where.join(' AND ') : null,
      whereArgs: args.isNotEmpty ? args : null,
      orderBy: 'datetime(created_at) DESC, id DESC',
    );
    return rows.map((e) => Map<String, Object?>.from(e)).toList();
  }

  Future<double> getLoanPaidAmount(int loanId) async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT SUM(paid_amount) AS total FROM loan_payments WHERE loan_id = ?',
      [loanId],
    );
    return (rows.first['total'] as num?)?.toDouble() ?? 0;
  }

  Future<double> payLoan({
    required int loanId,
    required int clientId,
    required double amount,
    int? storeId,
    String? note,
  }) async {
    if (amount <= 0) {
      throw ArgumentError('Payment amount must be greater than zero.');
    }
    final db = await database;
    final remaining = await db.transaction<double>((txn) async {
      final loanRows = await txn.query(
        'loans',
        where: 'id = ?',
        whereArgs: [loanId],
        limit: 1,
      );
      if (loanRows.isEmpty) {
        throw StateError('Loan not found.');
      }
      final loan = Loan.fromMap(Map<String, dynamic>.from(loanRows.first));
      final paidRows = await txn.rawQuery(
        'SELECT SUM(paid_amount) AS total FROM loan_payments WHERE loan_id = ?',
        [loanId],
      );
      final paidSoFar = (paidRows.first['total'] as num?)?.toDouble() ?? 0;
      final dueLeft = loan.totalDue - paidSoFar;
      if (dueLeft <= 0) {
        await txn.update(
          'loans',
          {'status': 'paid'},
          where: 'id = ?',
          whereArgs: [loanId],
        );
        return 0;
      }
      final applied = amount >= dueLeft ? dueLeft : amount;
      final remainingAfter = dueLeft - applied;
      await txn.insert('loan_payments', {
        'store_id': storeId ?? loan.storeId,
        'loan_id': loanId,
        'client_id': clientId,
        'paid_amount': applied,
        'remaining_balance': remainingAfter < 0 ? 0 : remainingAfter,
        'note': (note ?? '').trim().isEmpty ? null : note!.trim(),
        'created_at': DateTime.now().toIso8601String(),
      });
      await txn.update(
        'loans',
        {'status': remainingAfter <= 0 ? 'paid' : 'active'},
        where: 'id = ?',
        whereArgs: [loanId],
      );
      return remainingAfter < 0 ? 0 : remainingAfter;
    });
    _notifyDataChanged();
    return remaining;
  }

  // ===== EXPENSES =====

  Future<int> upsertExpense(Expense expense) async {
    final db = await database;
    final payload = Map<String, Object?>.from(expense.toMap());
    int result;
    if (expense.id == null) {
      result = await db.insert('expenses', payload);
    } else {
      result = await db.update(
        'expenses',
        payload,
        where: 'id = ?',
        whereArgs: [expense.id],
      );
    }
    _notifyDataChanged();
    return result;
  }

  Future<List<Expense>> getExpenses({int? storeId}) async {
    final db = await database;
    final where = <String>[];
    final args = <Object?>[];
    if (storeId != null) {
      where.add('store_id = ?');
      args.add(storeId);
    }
    final maps = await db.query(
      'expenses',
      where: where.isNotEmpty ? where.join(' AND ') : null,
      whereArgs: args.isNotEmpty ? args : null,
      orderBy: 'created_at DESC',
    );
    return maps.map(Expense.fromMap).toList();
  }

  Future<int> deleteExpense(int id) async {
    final db = await database;
    final result = await db.delete(
      'expenses',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (result > 0) _notifyDataChanged();
    return result;
  }

  // ===== SERVICE TRANSACTIONS (local mode) =====

  Future<int> upsertServiceTransaction(ServiceTransaction service) async {
    final db = await database;
    final payload = Map<String, Object?>.from(service.toMap());
    int result;
    if (service.id == null) {
      result = await db.insert('service_transactions', payload);
    } else {
      result = await db.update(
        'service_transactions',
        payload,
        where: 'id = ?',
        whereArgs: [service.id],
      );
    }
    _notifyDataChanged();
    return result;
  }

  Future<List<ServiceTransaction>> getServiceTransactions({int? storeId}) async {
    final db = await database;
    final where = <String>[];
    final args = <Object?>[];
    if (storeId != null) {
      where.add('store_id = ?');
      args.add(storeId);
    }
    final maps = await db.query(
      'service_transactions',
      where: where.isNotEmpty ? where.join(' AND ') : null,
      whereArgs: args.isNotEmpty ? args : null,
      orderBy: 'created_at DESC',
    );
    return maps
        .map((m) => ServiceTransaction.fromMap(Map<String, dynamic>.from(m)))
        .toList();
  }

  Future<int> deleteServiceTransaction(int id) async {
    final db = await database;
    final result = await db.delete(
      'service_transactions',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (result > 0) _notifyDataChanged();
    return result;
  }

  // ===== ASSETS =====

  Future<int> upsertAsset(Asset asset) async {
    final db = await database;
    final payload = Map<String, Object?>.from(asset.toMap());
    payload['updated_at'] = DateTime.now().toIso8601String();
    int result;
    if (asset.id == null) {
      payload['created_at'] = DateTime.now().toIso8601String();
      result = await db.insert('assets', payload);
    } else {
      result = await db.update(
        'assets',
        payload,
        where: 'id = ?',
        whereArgs: [asset.id],
      );
    }
    _notifyDataChanged();
    return result;
  }

  Future<List<Asset>> getAssets({int? storeId}) async {
    final db = await database;
    final where = <String>[];
    final args = <Object?>[];
    if (storeId != null) {
      where.add('store_id = ?');
      args.add(storeId);
    }
    final maps = await db.query(
      'assets',
      where: where.isNotEmpty ? where.join(' AND ') : null,
      whereArgs: args.isNotEmpty ? args : null,
      orderBy: 'created_at DESC',
    );
    return maps.map(Asset.fromMap).toList();
  }

  Future<int> deleteAsset(int id) async {
    final db = await database;
    final result = await db.transaction<int>((txn) async {
      await txn.delete(
        'asset_depreciations',
        where: 'asset_id = ?',
        whereArgs: [id],
      );
      return txn.delete('assets', where: 'id = ?', whereArgs: [id]);
    });
    if (result > 0) _notifyDataChanged();
    return result;
  }

  Future<int> addAssetDepreciation({
    required int assetId,
    required double amount,
    String? note,
  }) async {
    final db = await database;
    final result = await db.transaction<int>((txn) async {
      final rows = await txn.query(
        'assets',
        columns: ['current_value'],
        where: 'id = ?',
        whereArgs: [assetId],
        limit: 1,
      );
      if (rows.isEmpty) return 0;
      final current = (rows.first['current_value'] as num?)?.toDouble() ?? 0;
      final next = (current - amount).clamp(0, double.infinity);
      await txn.update(
        'assets',
        {
          'current_value': next,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [assetId],
      );
      return txn.insert('asset_depreciations', {
        'asset_id': assetId,
        'amount': amount,
        'note': note,
        'created_at': DateTime.now().toIso8601String(),
      });
    });
    _notifyDataChanged();
    return result;
  }

  Future<List<Map<String, Object?>>> getAssetDepreciations(int assetId) async {
    final db = await database;
    return db.query(
      'asset_depreciations',
      where: 'asset_id = ?',
      whereArgs: [assetId],
      orderBy: 'created_at DESC',
    );
  }

  Future<double> getTotalExpenses({int? storeId}) async {
    final db = await database;
    final where = <String>[];
    final args = <Object?>[];
    if (storeId != null) {
      where.add('store_id = ?');
      args.add(storeId);
    }
    final whereClause =
        where.isNotEmpty ? 'WHERE ${where.join(' AND ')}' : '';
    final result = await db.rawQuery(
      '''
      SELECT SUM(amount) as total
      FROM expenses
      $whereClause
      ''',
      args,
    );
    final value = result.first['total'] as num?;
    return value?.toDouble() ?? 0;
  }

  // ===== REMOTE SNAPSHOT SYNC =====

  Future<void> replaceStoresFromRemote(List<Map<String, dynamic>> rows) async {
    MotherDataCache.instance.applyStoresFromRemote(rows);
    _notifyDataChanged();
  }

  Future<void> replaceClientsFromRemote(List<Map<String, dynamic>> rows) async {
    MotherDataCache.instance.applyClientsFromRemote(rows);
    _notifyDataChanged();
  }

  Future<void> replaceItemsFromRemote(List<Map<String, dynamic>> rows) async {
    MotherDataCache.instance.applyItemsFromRemote(rows);
    _notifyDataChanged();
  }

  Future<int> insertCartDraft({
    required String title,
    required String payloadJson,
  }) async {
    final db = await database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cart_drafts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        payload TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    final now = DateTime.now().toIso8601String();
    final safeTitle = title.trim().isEmpty ? 'Draft' : title.trim();
    final safePayload = payloadJson.trim();
    if (safePayload.isEmpty) {
      throw ArgumentError('Draft payload is empty.');
    }
    return db.insert('cart_drafts', {
      'title': safeTitle,
      'payload': safePayload,
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<List<CartDraft>> getCartDrafts() async {
    final db = await database;
    final rows = await db.query(
      'cart_drafts',
      orderBy: 'updated_at DESC',
    );
    return rows.map(CartDraft.fromMap).toList();
  }

  Future<CartDraft?> getCartDraftById(int id) async {
    final db = await database;
    final rows = await db.query(
      'cart_drafts',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return CartDraft.fromMap(rows.first);
  }

  Future<void> deleteCartDraft(int id) async {
    final db = await database;
    await db.delete(
      'cart_drafts',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteAllCartDrafts() async {
    final db = await database;
    await db.delete('cart_drafts');
  }
}
