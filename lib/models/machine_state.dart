/// Holds the parsed machine status received via BLE.
class MachineState {
  static const String statusOff = 'OFF';
  static const String statusOn = 'ON';
  static const String statusUnknown = 'UNKNOWN';

  double temperature;
  int speed;
  String status;

  MachineState({
    this.temperature = double.nan,
    this.speed = -1,
    this.status = statusUnknown,
  });

  bool get isOn => status == statusOn;
  bool get hasTemperature => !temperature.isNaN;
  bool get hasSpeed => speed >= 0;
  bool get hasStatus => status != statusUnknown;

  void reset() {
    temperature = double.nan;
    speed = -1;
    status = statusUnknown;
  }
  /// 只把新狀態裡「有值」的欄位合併進來，保留其餘舊值。
  void applyFrom(MachineState other) {
    if (other.hasTemperature) {
      temperature = other.temperature;
    }
    if (other.hasSpeed) {
      speed = other.speed;
    }
    if (other.hasStatus) {
      status = other.status;
    }
  }
}
