# AGENTS.md

Guidance for AI coding agents working in this repository.

## Project Overview

`petfr` is a Flutter app (Android + iOS + macOS) that controls a **PET plastic filament recycler machine** over Bluetooth Low Energy (BLE). The companion hardware is an Arduino-based device advertising with the name prefix `PET-Recycle`. The app can:

- Scan for and connect to the recycler (BLE service/characteristic UUIDs in `lib/models/ble_constants.dart` must match the Arduino firmware).
- Send commands (`START`, `STOP`, `SET_TEMP:<n>`, `SET_SPEED:<n>`, `GET_STATUS`) as UTF-8 strings terminated with `\n`.
- Receive status notifications in the format `TEMP:50,SPEED:1000,STATUS:ON` (parsed by `StatusParser` in `lib/services/ble_service.dart`).
- Persist all BLE traffic (direction `IN`/`OUT`) **and app/UI events** to a local SQLite log, pruned to the newest 1000 entries. Entries carry a `level` (`INFO`/`WARN`/`ERROR`) and `category` (`BLE`/`UI`/`APP`); events are written via `AppLogger` in `lib/services/app_logger.dart` (developer-facing English messages, not localized).
- Switch UI language between English and Traditional Chinese (no ARB files — a hand-rolled `AppStrings` class).

Key facts:

- Package name: `petfr`; app title: "PET Filament Recycler"; Android `applicationId`/`namespace`: `com.example.petfr` (placeholder, not yet customized).
- Dart SDK constraint: `^3.12.2`; version `1.0.0+1`; `publish_to: none` (private app).
- Material 3, teal seed color, light + dark themes.

## Tech Stack and Key Dependencies

Declared in `pubspec.yaml`:

| Package | Purpose |
|---|---|
| `flutter_blue_plus` | BLE scanning, connection, characteristic read/write/notify (Android/iOS/macOS; no web) |
| `provider` | State management (`ChangeNotifierProvider` for `LocaleService`) |
| `sqflite`, `path`, `path_provider` | Local SQLite log database |
| `sqflite_common_ffi` | Desktop SQLite backend; `DatabaseService` switches to it on macOS |
| `permission_handler` | Runtime BLE/location permission requests on Android (pinned `^12.0.0`; 13.x needs compileSdk 37, unavailable locally) |
| `share_plus` | Exporting/sharing log files |
| `shared_preferences` | Persisting the selected language |
| `intl` | (declared; date/number formatting) |
| `cupertino_icons` | iOS-style icons |

Dev dependency: `flutter_lints` ^6.0.0.

## Architecture and Code Layout

All app code lives in `lib/`:

- `main.dart` — entry point; wraps `PetFrApp` (a `MaterialApp`) in a `ChangeNotifierProvider<LocaleService>`. Only the locale service is app-global; `BleService` is instantiated per `ControlScreen`, not provided globally.
- `screens/` — UI screens, one widget class per file:
  - `home_screen.dart` — landing screen with language toggle and navigation to the control panel.
  - `control_screen.dart` — main screen: device scan/selector, connection bar, status display (temperature/speed/ON-OFF), and Start/Stop/Save buttons. Owns a `BleService` instance and wires its callbacks (`onConnectionChanged`, `onError`, `onStatusUpdate`).
  - `log_screen.dart` — live-updating list of persisted logs (subscribes to `DatabaseService.changes`), All/IN/OUT/Events filter, long-press to copy an entry, export-all via share sheet, clear-all (confirmation dialog). BLE rows show an IN/OUT badge; event rows show a level badge.
  - `app_logger.dart` — `AppLogger.info/warn/error` fire-and-forget event logging into the DB (never throws; used by screens and `BleService`).
- `services/` — non-UI logic:
  - `ble_service.dart` — all BLE operations (scan, connect, notify, command writes, 3 s status polling) plus `StatusParser`, which parses the device's status string into a `MachineState`. Emits stable error keys (`errBluetoothOff`, `errConnectionLost`, `errNotConnected`, `errPermissionDenied`) via `onError`; `ControlScreen` maps them to localized strings. Only the status characteristic triggers `onStatusUpdate`; the log characteristic only writes to the DB. Tracks `isConnecting` and listens for remote disconnects.
  - `database_service.dart` — singleton wrapper around the `bluetooth_logs` SQLite table (insert with auto-prune, query newest-first, clear). Broadcasts a `changes` stream on every mutation so UI can refresh live. Uses `sqflite_common_ffi` on macOS.
  - `locale_service.dart` — `ChangeNotifier` holding the current language (`en`/`zh`), persisted via `shared_preferences`.
- `models/` — plain data classes and constants:
  - `ble_constants.dart` — BLE UUIDs, device name prefix, value limits (temp 0–300, speed 0–4096), timeouts, and command strings. **Change here must stay in sync with the Arduino firmware.**
  - `machine_state.dart` — parsed machine status; uses sentinels (`double.nan`, `-1`, `'UNKNOWN'`) for "no value yet".
  - `log_entry.dart` — one log row with `toMap`/`fromMap`.
- `l10n/app_strings.dart` — `AppStrings(bool isZh)` returning every UI string in English or Traditional Chinese. **Any new user-facing string must be added here in both languages**, not hardcoded in widgets.

Platform folders `android/` (Gradle Kotlin DSL, Java 17), `ios/`, and `macos/` are standard Flutter scaffolding; `build/`, `.dart_tool/`, `pubspec.lock` are generated. BLE permissions are declared: Android manifest has `BLUETOOTH_SCAN`/`BLUETOOTH_CONNECT` (+ legacy permissions for API ≤ 30) and runtime requests happen in `BleService.startScan()`; iOS and macOS have `NSBluetoothAlwaysUsageDescription` in their `Info.plist`.

## Build and Test Commands

Standard Flutter workflow from the repo root:

```bash
flutter pub get        # install dependencies
flutter analyze        # static analysis (flutter_lints)
flutter test           # run tests (currently only test/widget_test.dart)
flutter run            # run on a connected device/emulator (debug)
flutter build apk      # Android release APK (signed with debug keys for now)
flutter build ios      # iOS build (requires macOS/Xcode)
flutter run -d macos   # macOS desktop build — can connect to the real machine via the Mac's Bluetooth
```

BLE works on physical devices with Bluetooth (including a Mac for the macOS build); simulators/emulators cannot exercise the core feature.

## Testing Strategy

Minimal: a single widget test (`test/widget_test.dart`) pumps `HomeScreen` inside a `ChangeNotifierProvider<LocaleService>` (with mocked `SharedPreferences`) and asserts the app title renders. There are no unit tests for `StatusParser`, services, or the database. When adding tests, follow the existing pattern: `flutter_test` in `test/`, mirroring the `lib/` structure. Widget tests must not depend on real BLE hardware or the platform SQLite database — `BleService` and `DatabaseService` currently hit plugins directly, so test them via seams/mocks if you extend coverage.

## Conventions

- Linting: `analysis_options.yaml` includes `package:flutter_lints/flutter.yaml` with no rule overrides; keep `flutter analyze` clean.
- Imports are relative within `lib/` (`../services/...`), not `package:petfr/...`.
- State management: `ChangeNotifier` + `provider` (`context.watch`/`context.read`); `ListenableBuilder` is used to rebuild on `BleService` changes.
- Services use callback typedefs (`onError`, `onStatusUpdate`, ...) in addition to `notifyListeners()`; wire both when consuming them.
- `DatabaseService` is a singleton via a factory constructor; `BleService` is not.
- Comments are sparse `///` doc comments in English; match that style and don't add noise comments.
- UI text is bilingual — see `l10n/app_strings.dart` above.

## Known Gaps / Cautions

- Android release builds currently use the debug signing key (`android/app/build.gradle.kts` has a `TODO` for a real signing config); `applicationId` is still the `com.example` placeholder.
- `permission_handler` is pinned to `^12.0.0` (see table above); revisit the pin when the local Android SDK / AGP supports API 37.
- There is no CI: `.github/` contains only unrelated Copilot "modernize" helper scripts, no workflows.
- `README.md` is the default Flutter template and carries no project-specific information.
