/// A single log entry (BLE traffic or app event).
class LogEntry {
  static const String levelInfo = 'INFO';
  static const String levelWarn = 'WARN';
  static const String levelError = 'ERROR';

  static const String categoryBle = 'BLE';
  static const String categoryUi = 'UI';
  static const String categoryApp = 'APP';

  final int? id;
  final String timestamp;
  final String direction; // "IN" or "OUT" (BLE only, '' for events)
  final String message;
  final String device;
  final String level;
  final String category;

  LogEntry({
    this.id,
    required this.timestamp,
    required this.direction,
    required this.message,
    this.device = '',
    this.level = levelInfo,
    this.category = categoryBle,
  });

  bool get isIncoming => direction == 'IN';
  bool get isBleTraffic => direction == 'IN' || direction == 'OUT';
  bool get hasDevice => device.isNotEmpty;

  Map<String, dynamic> toMap() => {
    '_id': id,
    'timestamp': timestamp,
    'direction': direction,
    'message': message,
    'device': device,
    'level': level,
    'category': category,
  };

  factory LogEntry.fromMap(Map<String, dynamic> map) => LogEntry(
    id: (map['_id'] ?? map['id']) as int?,
    timestamp: map['timestamp'] as String,
    direction: map['direction'] as String,
    message: map['message'] as String,
    device: (map['device'] as String?) ?? '',
    level: (map['level'] as String?) ?? levelInfo,
    category: (map['category'] as String?) ?? categoryBle,
  );
}
