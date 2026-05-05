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
