import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../models/log_entry.dart';

/// Singleton database service for Bluetooth communication logs.
class DatabaseService {
  static const String _dbName = 'bluetooth_logs.db';
  static const int _dbVersion = 1;
  static const int _maxLogEntries = 1000;

  static const String tableLogs = 'bluetooth_logs';
  static const String colId = '_id';
  static const String colTimestamp = 'timestamp';
  static const String colDirection = 'direction';
  static const String colMessage = 'message';
  static const String colDevice = 'device';

  static DatabaseService? _instance;
  Database? _db;

  DatabaseService._();

  factory DatabaseService() {
    _instance ??= DatabaseService._();
    return _instance!;
  }

  Future<Database> get database async {
    _db ??= await _initDatabase();
    return _db!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, _dbName);

    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, version) {
        return db.execute('''
          CREATE TABLE $tableLogs (
            $colId INTEGER PRIMARY KEY AUTOINCREMENT,
            $colTimestamp TEXT NOT NULL,
            $colDirection TEXT NOT NULL,
            $colMessage TEXT NOT NULL,
            $colDevice TEXT NOT NULL DEFAULT ''
          )
        ''');
      },
    );
  }

  /// Insert a log entry and prune old ones.
  Future<void> insertLog({
    required String direction,
    required String message,
    String device = '',
    String? timestamp,
  }) async {
    final db = await database;
    final now = DateTime.now();
    final ts =
        timestamp ??
        '${now.year}-${_pad(now.month)}-${_pad(now.day)} '
            '${_pad(now.hour)}:${_pad(now.minute)}:${_pad(now.second)}';

    await db.insert(tableLogs, {
      colTimestamp: ts,
      colDirection: direction,
      colMessage: message,
      colDevice: device,
    });

    await _pruneOldLogs(db);
  }

  Future<void> _pruneOldLogs(Database db) async {
    final count =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM $tableLogs'),
        ) ??
        0;
    if (count <= _maxLogEntries) return;

    final excess = count - _maxLogEntries;
    await db.execute('''
      DELETE FROM $tableLogs WHERE $colId IN (
        SELECT $colId FROM $tableLogs
        ORDER BY $colId ASC LIMIT $excess
      )
    ''');
  }

  /// Get all logs, newest first.
  Future<List<LogEntry>> getAllLogs() async {
    final db = await database;
    final rows = await db.query(tableLogs, orderBy: '$colId DESC');
    return rows.map((r) => LogEntry.fromMap(r)).toList();
  }

  /// Clear all logs.
  Future<void> clearAllLogs() async {
    final db = await database;
    await db.delete(tableLogs);
  }

  String _pad(int n) => n.toString().padLeft(2, '0');
}
