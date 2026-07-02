/// BLE constants matching the Arduino firmware configuration.
class BleConstants {
  BleConstants._();

  // ---- BLE UUIDs ----
  static const String serviceUuid = '94a9c8c1-9b2c-41e6-a662-e5728e07008a';
  static const String controlUuid = '94a9c8c1-9b2c-41e6-a662-e5728e07008b';
  static const String statusUuid = '94a9c8c1-9b2c-41e6-a662-e5728e07008c';
  static const String logUuid = '94a9c8c1-9b2c-41e6-a662-e5728e07008d';
  static const String clientConfigUuid = '00002902-0000-1000-8000-00805f9b34fb';

  // ---- Device filtering ----
  static const String deviceNamePrefix = 'PET-Recycle';

  // ---- Limits ----
  static const int tempMin = 0;
  static const int tempMax = 300;
  static const int speedMin = 0;
  static const int speedMax = 4096;

  // ---- Timing ----
  static const int scanTimeoutMs = 8000;
  static const int connectTimeoutMs = 15000;
  static const int requestedMtu = 517;

  // ---- Commands (sent to Arduino) ----
  static const String cmdStart = 'START';
  static const String cmdStop = 'STOP';
  static const String cmdGetStatus = 'GET_STATUS';
  static const String cmdSetTempPrefix = 'SET_TEMP:';
  static const String cmdSetSpeedPrefix = 'SET_SPEED:';
}
