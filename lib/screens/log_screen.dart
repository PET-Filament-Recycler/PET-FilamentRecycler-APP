import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/ble_service.dart';
import '../services/database_service.dart';
import '../services/locale_service.dart';
import '../models/log_entry.dart';
import '../l10n/app_strings.dart';

class LogScreen extends StatefulWidget {
  const LogScreen({super.key});

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  final DatabaseService _db = DatabaseService();
  BleService? _ble;
  List<LogEntry> _logs = [];
  bool _loading = true;
  bool _logListenerAttached = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_logListenerAttached) return;

    _ble = context.read<BleService>();
    _ble!.onLogInserted = _onLogInserted;
    _logListenerAttached = true;
  }

  void _onLogInserted() {
    if (!mounted) return;
    _loadLogs();
  }

  @override
  void initState() {
    super.initState();
    _loadLogs();
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
      _loadLogs();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(strings.logsCleared)));
      }
    }
  }

  @override
  void dispose() {
    if (_logListenerAttached && _ble?.onLogInserted == _onLogInserted) {
      _ble!.onLogInserted = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locale = context.watch<LocaleService>();
    final strings = AppStrings(locale.isZh);

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.logs),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadLogs,
            tooltip: strings.refresh,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _logs.isEmpty ? null : _clearLogs,
            tooltip: strings.clearLogs,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _logs.isEmpty
          ? Center(
              child: Text(
                strings.noLogs,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            )
          : ListView.separated(
              itemCount: _logs.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final log = _logs[index];
                return _LogTile(log: log, strings: strings);
              },
            ),
    );
  }
}

class _LogTile extends StatelessWidget {
  final LogEntry log;
  final AppStrings strings;

  const _LogTile({required this.log, required this.strings});

  @override
  Widget build(BuildContext context) {
    final isIn = log.isIncoming;

    return ListTile(
      dense: true,
      leading: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isIn ? Colors.blue.shade100 : Colors.orange.shade100,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          isIn ? strings.logDirectionIn : strings.logDirectionOut,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12,
            color: isIn ? Colors.blue.shade800 : Colors.orange.shade800,
          ),
        ),
      ),
      title: Text(log.message, style: const TextStyle(fontSize: 14)),
      subtitle: Text(
        log.hasDevice ? '${log.timestamp} · ${log.device}' : log.timestamp,
        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
      ),
    );
  }
}
