# pionne_flutter

Error monitoring SDK for Flutter — by [Pionne](https://pionne.agkgcreations.fr).

Auto-captures Flutter framework errors, unhandled async/zone errors, **AND native crashes** (Objective-C `NSException`, signals, OOM, NDK, ANR) via MetricKit (iOS 14+) and `ApplicationExitInfo` (Android 11+). Ships rich runtime context (Dart version, OS, locale, debug/release mode). Wire-format compatible with `@pionne/react-native`, `@pionne/web`, `@pionne/node`.

## 🎫 Get your token

Pionne is **mobile-first**: you sign up, create projects, and watch your error feed **from the Pionne mobile app**, not a web dashboard.

1. **Download the app**:
   - 🍎 [App Store](https://apps.apple.com/app/id6766753270) *(coming soon)*
   - [<img src="https://play.google.com/intl/en_us/badges/static/images/badges/en_badge_web_generic.png" alt="Get it on Google Play" height="40"/>](https://play.google.com/store/apps/details?id=fr.agkgcreations.pionne)
2. Create your account (30 days free, no card required)
3. **+ New project** → pick **Flutter** → copy the token displayed (`pio_live_…`)
4. Paste it into `Pionne.init(PionneOptions(token: ...))` below

⚠️ The token is only shown **once** at project creation — load it from `--dart-define=PIONNE_TOKEN=…` at build time, never hard-code it in source.

## Install

```yaml
dependencies:
  pionne_flutter: ^0.4.0
```

```bash
flutter pub get
```

> ℹ️ Depuis **0.4.0** le package est un **Flutter Plugin** (avec code natif iOS + Android pour la capture des crashs natifs). À l'upgrade depuis 0.3.x, lance `flutter clean && flutter pub get` puis rebuild l'app (`flutter run` / `flutter build`) pour que le module natif soit lié.

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

### Crashs natifs (iOS + Android)

Les handlers Dart (`FlutterError.onError`, `PlatformDispatcher.onError`, `runZonedGuarded`) ne voient **jamais** un crash natif : le process entier meurt avant qu'aucun Dart ne tourne. Le SDK s'appuie sur l'OS pour les enregistrer et les rejoue en events `fatal` (`mechanism.type = "native"`) **au lancement suivant**.

```dart
Pionne.init(PionneOptions(
  token: 'pio_live_xxx',
  captureNativeCrashes: true, // défaut: true
));
```

**Ce qui est capturé sur iOS 14+** via MetricKit :
- `NSException` Obj-C/Swift (nom + message structuré sur iOS 17+, ex. `NSInvalidArgumentException`)
- Signaux : `SIGSEGV`, `SIGABRT`, `SIGBUS`, `SIGILL`, `SIGFPE`, `SIGTRAP`
- Kills mémoire (OOM) et terminations watchdog (`0x8badf00d`)
- Call stack tree (frames système symbolisées, frames app en `binaryName 0xADDR`)

**Ce qui est capturé sur Android 11+** via `ApplicationExitInfo` :
- `REASON_CRASH` — exception JVM non catchée
- `REASON_CRASH_NATIVE` — crash NDK (C/C++)
- `REASON_ANR` — Application Not Responding (avec trace)
- `REASON_LOW_MEMORY` — kill mémoire

> ⚠️ La capture native nécessite que le plugin soit **compilé dans le binaire** (plugin Flutter avec code natif iOS/Android). Sur le **web** ou un build sans le module natif, l'option est silencieusement ignorée (aucun crash). Les crashs arrivent **au lancement qui suit** (livrés post-mortem par l'OS), avec un tag `native.source` (`metrickit` sur iOS, `app_exit` sur Android).

### User identity, tags, opt-out

```dart
Pionne.setUser('u_42');
Pionne.setTags({'tier': 'pro'});
Pionne.setEnabled(false);
```

### Profiling — preview (coming soon)

Continuous-ish CPU profiling is **shipped on `@pionne/react-native@0.8.0`**
(Hermes sampler). The Dart/Flutter implementation is on the roadmap and
will use the Dart VM Service Protocol (`dart:developer`).

The API will mirror RN exactly:

```dart
// Coming in pionne_flutter ~v0.2.0
await Pionne.profile('CheckoutFlow', () async {
  await fetchCart();
  await submitOrder();
}, route: '/checkout');
```

Same backend (`POST /api/profiles`), same retention (raw 7 d, aggregates
90 d), same flame graph view + cross-release regression chart in the
mobile dashboard. If you want profiling **today** in Flutter, you can
collect samples manually via `dart:developer` and POST them to the
endpoint as collapsed-stack JSON — format documented at
[pionne.agkgcreations.fr/profiling/intro](https://pionne.agkgcreations.fr/profiling/intro).

### Geography (opt-in)

Approximate user location (city, region, country) attached to every event.
Off by default for privacy — flip `sendGeography` to enable:

```dart
Pionne.init(PionneOptions(
  token: 'pio_live_xxx',
  sendGeography: true,
));
```

Resolved once at startup via a free IP→geo lookup (`https://ipapi.co/json/`
by default), with a 4 s timeout. If the lookup fails the SDK silently keeps
shipping events without geo. Override the endpoint via `geographyEndpoint`
if you have your own.

### Release Health

```dart
Pionne.init(PionneOptions(
  token: 'pio_live_xxx',
  releaseHealth: true, // default
));
```

Ouvre une session au boot, la flippe à `crashed`/`errored` si une exception fatale est captée. Le dashboard dérive le crash-free user rate par release. Désactivable.

### Rate limit client (anti-runaway)

```dart
Pionne.init(PionneOptions(
  token: 'pio_live_xxx',
  maxEventsPerSecond: 10, // default
));
```

Token-bucket process-wide. Au-delà, les events sont droppés silencieusement. Protège contre une boucle d'erreur dans un `Timer.periodic` qui throw. Mettre à `0` désactive (déconseillé).

## Rate limit serveur

Indépendamment de `maxEventsPerSecond`, l'API Pionne applique un rate-limit par token sur tous les endpoints publics. Au-delà → `HTTP 429` avec un header `Retry-After`. Le SDK fait silencieusement échouer (try/catch interne). Empêche un token leaké de drainer ton quota mensuel. Voir [doc rate limits](https://pionne.agkgcreations.fr/security/rate-limits).

## License

MIT
