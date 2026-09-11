import 'package:flutter/foundation.dart';

import '../models/log_entry.dart';
import 'database_service.dart';

/// Writes app/UI events to the log database.
///
/// Messages are plain English debug text (developer-facing, not localized).
/// Fire-and-forget: logging never throws and never blocks the caller.
class AppLogger {
  AppLogger._();

  /// When false, log writes are skipped entirely (widget tests).
  @visibleForTesting
  static bool enabled = true;

  static final DatabaseService _db = DatabaseService();

  static void info(String message, {String category = LogEntry.categoryApp}) =>
      _write(message, LogEntry.levelInfo, category);

  static void warn(String message, {String category = LogEntry.categoryApp}) =>
      _write(message, LogEntry.levelWarn, category);

  static void error(String message, {String category = LogEntry.categoryApp}) =>
      _write(message, LogEntry.levelError, category);

  static void _write(String message, String level, String category) {
    if (!enabled) return;
    _db
        .insertLog(
          direction: '',
          message: message,
          level: level,
          category: category,
        )
        .catchError((_) {});
  }
}
