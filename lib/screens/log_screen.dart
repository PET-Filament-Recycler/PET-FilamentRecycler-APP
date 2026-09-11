import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../services/app_logger.dart';
import '../services/database_service.dart';
import '../services/locale_service.dart';
import '../models/log_entry.dart';
import '../l10n/app_strings.dart';

enum _LogFilter { all, incoming, outgoing, events }

class LogScreen extends StatefulWidget {
  const LogScreen({super.key});

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  final DatabaseService _db = DatabaseService();
  StreamSubscription<void>? _changesSub;
  List<LogEntry> _logs = [];
  bool _loading = true;
  _LogFilter _filter = _LogFilter.all;

  @override
  void initState() {
    super.initState();
    _loadLogs();
    _changesSub = _db.changes.listen((_) => _loadLogs());
  }

  @override
  void dispose() {
    AppLogger.info('Log screen closed', category: 'UI');
    _changesSub?.cancel();
    super.dispose();
  }

  Future<void> _loadLogs() async {
    final logs = await _db.getAllLogs();
    if (mounted) {
      setState(() {
        _logs = logs;
        _loading = false;
      });
    }
  }

  List<LogEntry> get _filteredLogs {
    switch (_filter) {
      case _LogFilter.incoming:
        return _logs.where((l) => l.isIncoming).toList();
      case _LogFilter.outgoing:
        return _logs.where((l) => l.direction == 'OUT').toList();
      case _LogFilter.events:
        return _logs.where((l) => !l.isBleTraffic).toList();
      case _LogFilter.all:
        return _logs;
    }
  }

  Future<void> _clearLogs() async {
    final locale = context.read<LocaleService>();
    final strings = AppStrings(locale.isZh);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(strings.clearLogs),
        content: Text(strings.clearLogsConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(strings.confirm),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _db.clearAllLogs();
      AppLogger.info('Logs cleared', category: 'UI');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(strings.logsCleared)));
      }
    } else {
      AppLogger.info('Clear logs cancelled', category: 'UI');
    }
  }

  Future<void> _exportLogs() async {
    final strings = AppStrings(context.read<LocaleService>().isZh);
    // Export oldest-first so the file reads chronologically.
    final lines = _logs.reversed.map((l) {
      final kind = l.isBleTraffic ? l.direction : l.category;
      return '[${l.timestamp}] ${l.level} $kind ${l.message}';
    });
    AppLogger.info('Logs exported (${_logs.length} entries)', category: 'UI');

    final dir = await getTemporaryDirectory();
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final file = File(
      '${dir.path}/petfr_logs_${now.year}${two(now.month)}${two(now.day)}_'
      '${two(now.hour)}${two(now.minute)}${two(now.second)}.txt',
    );
    await file.writeAsString(lines.join('\n'));

    final result = await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], subject: strings.exportLogs),
    );
    AppLogger.info('Share sheet result: ${result.status.name}', category: 'UI');
  }

  void _copyLog(LogEntry log) {
    final strings = AppStrings(context.read<LocaleService>().isZh);
    Clipboard.setData(
      ClipboardData(text: '[${log.timestamp}] ${log.message}'),
    );
    AppLogger.info('Log entry copied', category: 'UI');
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(strings.copiedToClipboard)));
  }

  @override
  Widget build(BuildContext context) {
    final locale = context.watch<LocaleService>();
    final strings = AppStrings(locale.isZh);
    final logs = _filteredLogs;

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.logs),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share),
            onPressed: _logs.isEmpty ? null : _exportLogs,
            tooltip: strings.exportLogs,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _logs.isEmpty ? null : _clearLogs,
            tooltip: strings.clearLogs,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SegmentedButton<_LogFilter>(
              segments: [
                ButtonSegment(
                  value: _LogFilter.all,
                  label: Text(strings.filterAll),
                ),
                ButtonSegment(
                  value: _LogFilter.incoming,
                  label: Text(strings.logDirectionIn),
                ),
                ButtonSegment(
                  value: _LogFilter.outgoing,
                  label: Text(strings.logDirectionOut),
                ),
                ButtonSegment(
                  value: _LogFilter.events,
                  label: Text(strings.filterEvents),
                ),
              ],
              selected: {_filter},
              onSelectionChanged: (sel) {
                AppLogger.info(
                  'Log filter changed: ${sel.first.name}',
                  category: 'UI',
                );
                setState(() => _filter = sel.first);
              },
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : logs.isEmpty
                ? Center(
                    child: Text(
                      strings.noLogs,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  )
                : ListView.separated(
                    itemCount: logs.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final log = logs[index];
                      return _LogTile(
                        log: log,
                        strings: strings,
                        onLongPress: () => _copyLog(log),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _LogTile extends StatelessWidget {
  final LogEntry log;
  final AppStrings strings;
  final VoidCallback onLongPress;

  const _LogTile({
    required this.log,
    required this.strings,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final isIn = log.isIncoming;

    // BLE traffic keeps the IN/OUT badge; events show their level instead.
    final String badgeText;
    final Color badgeBg;
    final Color badgeFg;
    if (log.isBleTraffic) {
      badgeText = isIn ? strings.logDirectionIn : strings.logDirectionOut;
      badgeBg = isIn ? Colors.blue.shade100 : Colors.orange.shade100;
      badgeFg = isIn ? Colors.blue.shade800 : Colors.orange.shade800;
    } else {
      badgeText = log.level;
      switch (log.level) {
        case LogEntry.levelError:
          badgeBg = Colors.red.shade100;
          badgeFg = Colors.red.shade800;
        case LogEntry.levelWarn:
          badgeBg = Colors.amber.shade100;
          badgeFg = Colors.amber.shade900;
        default:
          badgeBg = Colors.grey.shade200;
          badgeFg = Colors.grey.shade800;
      }
    }

    return ListTile(
      dense: true,
      onLongPress: onLongPress,
      leading: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: badgeBg,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          badgeText,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12,
            color: badgeFg,
          ),
        ),
      ),
      title: Text(log.message, style: const TextStyle(fontSize: 14)),
      subtitle: Text(
        log.isBleTraffic ? log.timestamp : '${log.timestamp} · ${log.category}',
        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
      ),
    );
  }
}
