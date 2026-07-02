/// A single Bluetooth communication log entry.
class LogEntry {
  final int? id;
  final String timestamp;
  final String direction; // "IN" or "OUT"
  final String message;
  final String device;

  LogEntry({
    this.id,
    required this.timestamp,
    required this.direction,
    required this.message,
    this.device = '',
  });

  bool get isIncoming => direction == 'IN';
  bool get hasDevice => device.isNotEmpty;

  Map<String, dynamic> toMap() => {
    'id': id,
    'timestamp': timestamp,
    'direction': direction,
    'message': message,
    'device': device,
  };

  factory LogEntry.fromMap(Map<String, dynamic> map) => LogEntry(
    id: map['id'] as int?,
    timestamp: map['timestamp'] as String,
    direction: map['direction'] as String,
    message: map['message'] as String,
    device: (map['device'] as String?) ?? '',
  );
}
