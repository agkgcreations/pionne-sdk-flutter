# pionne_flutter

Error monitoring SDK for Flutter — by [Pionne](https://pionne.agkgcreations.fr).

Auto-captures Flutter framework errors and unhandled async/zone errors, ships rich runtime context (Dart version, OS, locale, debug/release mode). Single dependency: `http`. Wire-format compatible with `@pionne/react-native`, `@pionne/web`, `@pionne/node`.

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

## License

MIT
