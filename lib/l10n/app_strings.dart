/// App strings with English and Traditional Chinese support.
class AppStrings {
  final bool isZh;

  AppStrings(this.isZh);

  String get appTitle => isZh ? 'PET 回收機' : 'PET Recycler';
  String get homeTitle => isZh ? 'PET 回收機控制' : 'PET Recycler Control';
  String get navigateToControl => isZh ? '進入控制面板' : 'Enter Control Panel';
  String get controlTitle => isZh ? '控制面板' : 'Control Panel';
  String get connect => isZh ? '連線' : 'Connect';
  String get disconnect => isZh ? '斷線' : 'Disconnect';
  String get disconnecting => isZh ? '斷線中...' : 'Disconnecting...';
  String get refresh => isZh ? '掃描裝置' : 'Scan Devices';
  String get scanning => isZh ? '掃描中...' : 'Scanning...';
  String get selectDevice => isZh ? '請選擇裝置' : 'Select a device';
  String get noDevices => isZh ? '沒有發現裝置' : 'No devices found';
  String get connecting => isZh ? '連線中...' : 'Connecting...';
  String get connected => isZh ? '已連線' : 'Connected';
  String get notConnected => isZh ? '未連線' : 'Not Connected';
  String get connectionLost => isZh ? '連線中斷' : 'Connection lost';
  String connectionFailed(String detail) =>
      isZh ? '連線失敗：$detail' : 'Connection failed: $detail';
  String scanError(String detail) =>
      isZh ? '掃描錯誤：$detail' : 'Scan error: $detail';
  String fallbackScanError(String detail) =>
      isZh ? '備用掃描錯誤：$detail' : 'Fallback scan error: $detail';
  String sendFailed(String detail) =>
      isZh ? '送出失敗：$detail' : 'Send failed: $detail';
  String get bleConnected => isZh ? 'BLE 已連線' : 'BLE Connected';
  String get enableBluetooth => isZh ? '請啟用藍牙' : 'Please enable Bluetooth';
  String get permissionDenied => isZh ? '權限被拒，無法使用藍牙' : 'Permission denied';
  String get start => isZh ? '啟動' : 'Start';
  String get stop => isZh ? '停止' : 'Stop';
  String get save => isZh ? '儲存設定' : 'Save';
  String get temperature => isZh ? '溫度' : 'Temperature';
  String get speed => isZh ? '速度' : 'Speed';
  String get tempPlaceholder => isZh ? '°C' : '°C';
  String get speedPlaceholder => isZh ? 'mm/s' : 'mm/s';
  String get statusOn => isZh ? '運行中' : 'ON';
  String get statusOff => isZh ? '已停止' : 'OFF';
  String get statusUnknown => isZh ? '未知' : 'Unknown';
  String get settingsSent => isZh ? '設定已送出' : 'Settings sent';
  String get enterTempAndSpeed =>
      isZh ? '請輸入溫度和速度' : 'Enter temperature and speed';
  String tempRangeError(int min, int max) =>
      isZh ? '溫度需在 $min-$max 之間' : 'Temp must be $min-$max';
  String speedRangeError(int min, int max) =>
      isZh ? '速度需在 $min-$max 之間' : 'Speed must be $min-$max';
  String tempValue(double v) =>
      isZh ? '溫度: ${v.toInt()}°C' : 'Temp: ${v.toInt()}°C';
  String speedValue(int v) => isZh ? '速度: $v' : 'Speed: $v';
  String get logs => isZh ? '通訊日誌' : 'Logs';
  String get noLogs => isZh ? '尚無日誌' : 'No logs yet';
  String get clearLogs => isZh ? '清除日誌' : 'Clear Logs';
  String get clearLogsConfirm => isZh ? '確定要清除所有日誌？' : 'Clear all logs?';
  String get confirm => isZh ? '確定' : 'Confirm';
  String get cancel => isZh ? '取消' : 'Cancel';
  String get logsCleared => isZh ? '日誌已清除' : 'Logs cleared';
  String get logDirectionIn => isZh ? '接收' : 'IN';
  String get logDirectionOut => isZh ? '送出' : 'OUT';
  String get alreadyConnectedNoScan =>
      isZh ? '已連線，無法掃描' : 'Already connected, cannot scan';
  String get refreshingDevices => isZh ? '刷新裝置中...' : 'Refreshing...';
  String get selectDeviceFirst => isZh ? '請先選擇裝置' : 'Select a device first';
  String get invalidDeviceFormat => isZh ? '無效的裝置格式' : 'Invalid device format';
  String get invalidNumber => isZh ? '請輸入有效數字' : 'Enter a valid number';
}
