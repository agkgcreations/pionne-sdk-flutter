# pionne_flutter

Error monitoring SDK for Flutter — by [Pionne](https://pionne.agkgcreations.fr).

Auto-captures Flutter framework errors, unhandled async/zone errors, **AND native crashes** (Objective-C `NSException`, signals, OOM, NDK, ANR) via MetricKit (iOS 14+) and `ApplicationExitInfo` (Android 11+). Ships rich runtime context (Dart version, OS, locale, debug/release mode). Wire-format compatible with `@pionne/react-native`, `@pionne/web`, `@pionne/node`.

## 🎫 Get your token

Sign up, create projects, and watch your error feed from the **[web dashboard](https://app.pionne.agkgcreations.fr)** or the **Pionne mobile app**.

1. **Open the [web dashboard](https://app.pionne.agkgcreations.fr)** — or download the app:
   - 🍎 [App Store](https://apps.apple.com/app/id6766753270) *(coming soon)*
   - [<img src="https://play.google.com/intl/en_us/badges/static/images/badges/en_badge_web_generic.png" alt="Get it on Google Play" height="40"/>](https://play.google.com/store/apps/details?id=fr.agkgcreations.pionne)
2. Create your account (30 days free, no card required)
3. **+ New project** → pick **Flutter** → copy the token displayed (`pio_live_…`)
4. Paste it into `Pionne.init(PionneOptions(token: ...))` below

⚠️ The token is only shown **once** at project creation — load it from `--dart-define=PIONNE_TOKEN=…` at build time, never hard-code it in source.

## Install

```yaml
dependencies:
  pionne_flutter: ^0.4.1
```

```bash
flutter pub get
```

> ℹ️ Starting with **0.4.0**, the package is a **Flutter Plugin** (ships native iOS + Android code for native-crash capture). When upgrading from 0.3.x, run `flutter clean && flutter pub get` then rebuild the app (`flutter run` / `flutter build`) so the native module is linked.

## Usage

```dart
import 'package:flutter/material.dart';
import 'package:pionne_flutter/pionne_flutter.dart';

void main() {
  Pionne.init(PionneOptions(
    token: 'pio_live_xxx',
    release: '1.0.0',
  ));

  // Wrap the app to also catch zone errors:
  Pionne.runZonedGuarded(() => runApp(const MyApp()));
}
```

That's it. Flutter framework errors and unhandled async errors are now reported.

### Manual capture

```dart
try {
  await processOrder();
} catch (e, stack) {
  Pionne.captureException(e,
    stackTrace: stack,
    tags: {'feature': 'checkout'},
  );
  rethrow;
}

Pionne.captureMessage('user reached empty state', level: Level.info);
```

### Native crashes (iOS + Android)

Dart handlers (`FlutterError.onError`, `PlatformDispatcher.onError`, `runZonedGuarded`) **never** see a native crash: the whole process dies before any Dart runs. The SDK leans on the OS to record them and replays each as a `fatal` event (`mechanism.type = "native"`) on the **next launch**.

```dart
Pionne.init(PionneOptions(
  token: 'pio_live_xxx',
  captureNativeCrashes: true, // default: true
));
```

**What's captured on iOS 14+** via MetricKit:

- `NSException` Obj-C/Swift (name + composed message on iOS 17+, e.g. `NSInvalidArgumentException`)
- Signals: `SIGSEGV`, `SIGABRT`, `SIGBUS`, `SIGILL`, `SIGFPE`, `SIGTRAP`
- Out-of-memory kills and watchdog terminations (`0x8badf00d`)
- Call stack tree (system frames symbolicated by the OS; app frames as `binaryName 0xADDR`)

**What's captured on Android 11+** via `ApplicationExitInfo`:

- `REASON_CRASH` — unhandled JVM exception
- `REASON_CRASH_NATIVE` — NDK / native (C/C++) crash
- `REASON_ANR` — Application Not Responding (with the ANR trace)
- `REASON_LOW_MEMORY` — OOM kill

> ⚠️ Native capture needs the plugin **compiled into the binary** (a Flutter Plugin with iOS/Android native code). On **web** — or any build where the native module isn't compiled in — the option silently no-ops. Crashes arrive **on the launch following the crash** (delivered post-mortem by the OS), tagged `native.source` (`metrickit` on iOS, `app_exit` on Android).

### User identity, tags, opt-out

```dart
Pionne.setUser('u_42');
Pionne.setTags({'tier': 'pro'});
Pionne.setEnabled(false);
```

### Profiling — preview (coming soon)

Continuous-ish CPU profiling is **shipped on `@pionne/react-native@0.8.0`** (Hermes sampler). The Dart/Flutter implementation is on the roadmap and will use the Dart VM Service Protocol (`dart:developer`).

The API will mirror RN exactly:

```dart
// Coming in a future pionne_flutter release
await Pionne.profile('CheckoutFlow', () async {
  await fetchCart();
  await submitOrder();
}, route: '/checkout');
```

Same backend (`POST /api/profiles`), same retention (raw 7 d, aggregates 90 d), same flame graph view + cross-release regression chart in the mobile dashboard. If you want profiling **today** in Flutter, you can collect samples manually via `dart:developer` and POST them to the endpoint as collapsed-stack JSON — format documented at [pionne.agkgcreations.fr/profiling/intro](https://pionne.agkgcreations.fr/profiling/intro).

### Geography (opt-in)

Approximate user location (city, region, country) attached to every event. Off by default for privacy — flip `sendGeography` to enable:

```dart
Pionne.init(PionneOptions(
  token: 'pio_live_xxx',
  sendGeography: true,
));
```

Resolved once at startup via a free IP→geo lookup (`https://ipapi.co/json/` by default), with a 4 s timeout. If the lookup fails the SDK silently keeps shipping events without geo. Override the endpoint via `geographyEndpoint` if you have your own.

### Release Health

```dart
Pionne.init(PionneOptions(
  token: 'pio_live_xxx',
  releaseHealth: true, // default
));
```

Opens a session at boot and flips it to `crashed` / `errored` when a fatal exception is captured. The dashboard derives the crash-free user rate per release. Set to `false` to disable.

### Client-side rate limit (anti-runaway)

```dart
Pionne.init(PionneOptions(
  token: 'pio_live_xxx',
  maxEventsPerSecond: 10, // default
));
```

Process-wide token bucket. Anything above the limit is silently dropped. Protects against a runaway error loop in a throwing `Timer.periodic`. Set to `0` to disable (not recommended).

## Server-side rate limit

Independent of `maxEventsPerSecond`, the Pionne API enforces a per-token rate limit on every public endpoint. Excess requests get `HTTP 429` with a `Retry-After` header. The SDK silently swallows the failure (internal try/catch). Prevents a leaked token from draining your monthly quota. See the [rate-limit docs](https://pionne.agkgcreations.fr/security/rate-limits).

## License

MIT
