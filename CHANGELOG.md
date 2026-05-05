## 0.1.0

- Initial release.
- Auto-capture via `FlutterError.onError` and `PlatformDispatcher.instance.onError`.
- Zone wrapper helper `Pionne.runZonedGuarded`.
- Manual API: `Pionne.captureException`, `Pionne.captureMessage`, `Pionne.setUser`, `Pionne.setTags`, `Pionne.setEnabled`.
- Static context: OS, runtime, locale, debug/release mode.
