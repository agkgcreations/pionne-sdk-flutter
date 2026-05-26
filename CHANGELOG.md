## 0.4.0

### Added

- **Native crash capture** via MetricKit (iOS 14+) and `ApplicationExitInfo`
  (Android 11+). The Dart isolate can't see a crash that takes down the whole
  process (Objective-C `NSException`, signals like `SIGSEGV`/`SIGABRT`, OOM,
  NDK crashes, ANRs), so the OS records them and `pionne_flutter` replays them
  as `fatal` events (`mechanism.type=native`) on the next launch — tagged
  `native.source` (`metrickit` on iOS, `app_exit` on Android).
- New option `captureNativeCrashes` (defaults to `true`).
- New `MechanismType.native`.

### Changed

- Package converted from a pure Dart package to a **Flutter Plugin**. It now
  ships native iOS (Swift / MetricKit) and Android (Kotlin / ApplicationExitInfo)
  code. Consumers need to rebuild their app after upgrading (`flutter clean
  && flutter pub get && flutter run`) so the plugin is linked.
- Aligned `_sdkVersion` (reported in `contexts.sdk.version`) with the package
  version — it had been stuck at `0.1.0`.

### Notes

- iOS deployment target floor stays at 12 — MetricKit calls are gated by
  `@available(iOS 14.0, *)`, so older targets install the plugin without
  activating crash capture.
- Android crash capture only fires on API 30+; on older devices the plugin
  silently returns no records.
- App-level native frames aren't symbolicated (no dSYM pipeline) — system
  frames carry symbol info supplied by the OS.

## 0.3.3

### Fixed

- **Actionable error message on permanent ingest rejection.** `_send()`
  now reads the HTTP response (previously thrown away), parses the
  JSON error envelope on 401/403/422, distinguishes the failure modes
  (Bundle ID mismatch / Token rejected / 422 validation), and emits a
  `developer.log()` line (once per isolate, in release builds too)
  that includes the `app_id` actually sent and the masked
  `expected_format` returned by the server. Fixes the silent rejection
  footgun where a misconfigured token or stale bundle pinning would
  drop events without any visible signal in the Flutter console.

## 0.3.2

### Documentation

- README enrichi : nouvelles sections "Release Health" et "Rate limit client"
  (les options existaient déjà dans le code mais n'étaient pas documentées
  dans le README). Bloc "Rate limit serveur" qui documente le cap
  600 req/min/token côté API Pionne. Aucun changement de code SDK.

## 0.3.0

- **Release Health.** `Pionne.init()` now opens a release session (status='ok')
  at boot and auto-flips it to 'crashed' / 'errored' if the FlutterError or
  PlatformDispatcher handler captures a fatal/error. The dashboard derives
  the crash-free user rate per release from these sessions.
  - New API: `Pionne.endSession()`, `Pionne.getSessionId()`.
  - New option: `releaseHealth: false` to disable.
  - New endpoint: `POST /api/sessions` (idempotent on `session_id`).

## 0.2.0

Pionne backend got a major security hardening pass. The SDK API is unchanged
but now talks to a stricter, more observable server:

- **2FA TOTP** — users can now protect their dashboard account with a 6-digit
  code from any authenticator app (Google Authenticator, 1Password, Authy…).
- **Audit log** — every sensitive action (login, password/email change, token
  regenerate, project delete) is recorded for 1 year and visible from the
  mobile app.
- **Anomaly detection** — projects whose hourly volume crosses 10× the 7-day
  baseline trigger an email alert; 50× also auto-pauses the project for 1h
  to neutralise leaked tokens.
- **Server-side PII scrub** (defense-in-depth) — emails, JWTs and card numbers
  are re-redacted on ingest even if the SDK was misconfigured.
- **Token grace period** — when regenerating a token you can keep the old one
  valid 24h for zero-downtime rotation.

## 0.1.2

- README: add a "Get your token" section pointing to the Pionne mobile app.

## 0.1.1

- Fix: undefined `ErrorCallback` type → use `bool Function(Object, StackTrace)`.
- Fix: prefix `dart:async` import to call `runZonedGuarded` without recursion.
- Add explicit `dart:ui` import for `PlatformDispatcher`.

## 0.1.0

- Initial release.
- Auto-capture via `FlutterError.onError` and `PlatformDispatcher.instance.onError`.
- Zone wrapper helper `Pionne.runZonedGuarded`.
- Manual API: `Pionne.captureException`, `Pionne.captureMessage`, `Pionne.setUser`, `Pionne.setTags`, `Pionne.setEnabled`.
- Static context: OS, runtime, locale, debug/release mode.
