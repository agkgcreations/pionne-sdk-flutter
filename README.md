# pionne_flutter

Error monitoring SDK for Flutter — by [Pionne](https://pionne.agkgcreations.fr).

Auto-captures Flutter framework errors and unhandled async/zone errors, ships rich runtime context (Dart version, OS, locale, debug/release mode). Single dependency: `http`. Wire-format compatible with `@pionne/react-native`, `@pionne/web`, `@pionne/node`.

## 🎫 Get your token

Pionne is **mobile-first**: you sign up, create projects, and watch your error feed **from the Pionne mobile app**, not a web dashboard.

1. **Download the app**:
   - 🍎 [App Store](https://apps.apple.com/app/pionne) *(coming soon)*
   - 🤖 [Google Play](https://play.google.com/store/apps/details?id=fr.agkgcreations.pionne) *(coming soon)*
2. Create your account (30 days free, no card required)
3. **+ New project** → pick **Flutter** → copy the token displayed (`pio_live_…`)
4. Paste it into `Pionne.init(PionneOptions(token: ...))` below

⚠️ The token is only shown **once** at project creation — load it from `--dart-define=PIONNE_TOKEN=…` at build time, never hard-code it in source.

## Install

```yaml
dependencies:
  pionne_flutter: ^0.1.0
```

```bash
flutter pub get
```

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

### User identity, tags, opt-out

```dart
Pionne.setUser('u_42');
Pionne.setTags({'tier': 'pro'});
Pionne.setEnabled(false);
```

### Geography (opt-in)

Approximate user location (city, region, country) attached to every event,
just like Sentry. Off by default for privacy — flip `sendGeography` to enable:

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

Indépendamment de `maxEventsPerSecond`, l'API Pionne cap **600 req/min/token** (= 10/sec) sur tous les endpoints publics (`/ingest`, `/sessions`, `/feedback`). Au-delà → `HTTP 429` avec un header `Retry-After`. Le SDK fait silencieusement échouer (try/catch interne). Empêche un token leaké de drainer ton infra ou ton quota mensuel. Voir [doc rate limits](https://pionne.agkgcreations.fr/security/rate-limits).

## License

MIT
