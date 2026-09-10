# AGENTS.md

Guidance for AI coding agents working in this repository.

## Project Overview

`petfr` is a Flutter mobile app (Android + iOS) that controls a **PET plastic filament recycler machine** over Bluetooth Low Energy (BLE). The companion hardware is an Arduino-based device advertising with the name prefix `PET-Recycle`. The app can:

- Scan for and connect to the recycler (BLE service/characteristic UUIDs in `lib/models/ble_constants.dart` must match the Arduino firmware).
- Send commands (`START`, `STOP`, `SET_TEMP:<n>`, `SET_SPEED:<n>`, `GET_STATUS`) as UTF-8 strings terminated with `\n`.
- Receive status notifications in the format `TEMP:50,SPEED:1000,STATUS:ON` (parsed by `StatusParser` in `lib/services/ble_service.dart`).
- Persist all BLE traffic (direction `IN`/`OUT`) to a local SQLite log, pruned to the newest 1000 entries.
- Switch UI language between English and Traditional Chinese (no ARB files — a hand-rolled `AppStrings` class).

Key facts:

- Package name: `petfr`; app title: "PET Filament Recycler"; Android `applicationId`/`namespace`: `com.example.petfr` (placeholder, not yet customized).
- Dart SDK constraint: `^3.12.2`; version `1.0.0+1`; `publish_to: none` (private app).
- Material 3, teal seed color, light + dark themes.

## Tech Stack and Key Dependencies

Declared in `pubspec.yaml`:

| Package | Purpose |
|---|---|
| `flutter_blue_plus` | BLE scanning, connection, characteristic read/write/notify |
| `provider` | State management (`ChangeNotifierProvider` for `LocaleService`) |
| `sqflite`, `path`, `path_provider` | Local SQLite log database |
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
  - `log_screen.dart` — read-only list of persisted BLE logs with clear-all (confirmation dialog).
- `services/` — non-UI logic:
  - `ble_service.dart` — all BLE operations (scan, connect, notify, command writes, 3 s status polling) plus `StatusParser`, which parses the device's status string into a `MachineState`.
  - `database_service.dart` — singleton wrapper around the `bluetooth_logs` SQLite table (insert with auto-prune, query newest-first, clear).
  - `locale_service.dart` — `ChangeNotifier` holding the current language (`en`/`zh`), persisted via `shared_preferences`.
- `models/` — plain data classes and constants:
  - `ble_constants.dart` — BLE UUIDs, device name prefix, value limits (temp 0–300, speed 0–4096), timeouts, and command strings. **Change here must stay in sync with the Arduino firmware.**
  - `machine_state.dart` — parsed machine status; uses sentinels (`double.nan`, `-1`, `'UNKNOWN'`) for "no value yet".
  - `log_entry.dart` — one log row with `toMap`/`fromMap`.
- `l10n/app_strings.dart` — `AppStrings(bool isZh)` returning every UI string in English or Traditional Chinese. **Any new user-facing string must be added here in both languages**, not hardcoded in widgets.

Platform folders `android/` (Gradle Kotlin DSL, Java 17) and `ios/` are standard Flutter scaffolding; `build/`, `.dart_tool/`, `pubspec.lock` are generated.

## Build and Test Commands

Standard Flutter workflow from the repo root:

```bash
flutter pub get        # install dependencies
flutter analyze        # static analysis (flutter_lints)
flutter test           # run tests (currently only test/widget_test.dart)
flutter run            # run on a connected device/emulator (debug)
flutter build apk      # Android release APK (signed with debug keys for now)
flutter build ios      # iOS build (requires macOS/Xcode)
```

BLE only works on a physical device with Bluetooth; simulators/emulators cannot exercise the core feature.

## Testing Strategy

Minimal: a single widget test (`test/widget_test.dart`) pumps `HomeScreen` and asserts the app title renders. There are no unit tests for `StatusParser`, services, or the database. When adding tests, follow the existing pattern: `flutter_test` in `test/`, mirroring the `lib/` structure. Widget tests must not depend on real BLE hardware or the platform SQLite database — `BleService` and `DatabaseService` currently hit plugins directly, so test them via seams/mocks if you extend coverage.

## Conventions

- Linting: `analysis_options.yaml` includes `package:flutter_lints/flutter.yaml` with no rule overrides; keep `flutter analyze` clean.
- Imports are relative within `lib/` (`../services/...`), not `package:petfr/...`.
- State management: `ChangeNotifier` + `provider` (`context.watch`/`context.read`); `ListenableBuilder` is used to rebuild on `BleService` changes.
- Services use callback typedefs (`onError`, `onStatusUpdate`, ...) in addition to `notifyListeners()`; wire both when consuming them.
- `DatabaseService` is a singleton via a factory constructor; `BleService` is not.
- Comments are sparse `///` doc comments in English; match that style and don't add noise comments.
- UI text is bilingual — see `l10n/app_strings.dart` above.

## Known Gaps / Cautions

- **Missing BLE permissions in native config:** `android/app/src/main/AndroidManifest.xml` declares no `BLUETOOTH_SCAN`/`BLUETOOTH_CONNECT`/location permissions, and `ios/Runner/Info.plist` has no `NSBluetoothAlwaysUsageDescription`. Real-device BLE scanning will fail until these are added.
- Android release builds currently use the debug signing key (`android/app/build.gradle.kts` has a `TODO` for a real signing config); `applicationId` is still the `com.example` placeholder.
- There is no CI: `.github/` contains only unrelated Copilot "modernize" helper scripts, no workflows.
- `README.md` is the default Flutter template and carries no project-specific information.
