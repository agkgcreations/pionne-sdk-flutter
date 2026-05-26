/// Severity of an event. Mirrors the API enum.
enum Level { fatal, error, warning, info }

extension LevelString on Level {
  String get wireValue => switch (this) {
        Level.fatal => 'fatal',
        Level.error => 'error',
        Level.warning => 'warning',
        Level.info => 'info',
      };
}

/// How the event was captured. Used by the dashboard to group manual reports
/// vs auto-captured crashes.
enum MechanismType {
  flutterError,
  platformError,
  runZonedGuarded,
  manual,

  /// Native crash (Objective-C/Swift `NSException`, signal, OOM, NDK, ANR…)
  /// captured by the OS and replayed on the next launch via MetricKit (iOS) /
  /// ApplicationExitInfo (Android). The Dart isolate never sees the original
  /// crash — the process was already dead.
  native,
}

extension MechanismTypeString on MechanismType {
  String get wireValue => switch (this) {
        MechanismType.flutterError => 'flutter_error',
        MechanismType.platformError => 'platform_error',
        MechanismType.runZonedGuarded => 'run_zoned_guarded',
        MechanismType.manual => 'manual',
        MechanismType.native => 'native',
      };
}

/// SDK options. Pass to [Pionne.init].
class PionneOptions {
  PionneOptions({
    required this.token,
    this.endpoint = 'https://pionne.agkgcreations.fr/api/ingest',
    this.release,
    this.environment,
    this.enabled = true,
    this.captureFlutterErrors = true,
    this.capturePlatformErrors = true,
    this.captureNativeCrashes = true,
    this.autoContext = true,
    this.userIdAnon,
    this.tags,
    this.maxStackFrames = 50,
    this.beforeSend,
    this.releaseHealth = true,
    this.maxEventsPerSecond = 10,
    this.sendGeography = false,
    this.geographyEndpoint = 'https://ipapi.co/json/',
  });

  /// Project token (starts with `pio_live_`). Required.
  final String token;

  /// Override the ingest endpoint. Default: production Pionne.
  final String endpoint;

  /// App release / version (e.g. semver or git SHA).
  final String? release;

  /// Environment label. Default: "debug" in debug mode, "production" otherwise.
  final String? environment;

  /// Disable all reporting if false. Default: true.
  final bool enabled;

  /// Auto-capture errors via [FlutterError.onError]. Default: true.
  final bool captureFlutterErrors;

  /// Auto-capture errors via [PlatformDispatcher.instance.onError]. Default: true.
  final bool capturePlatformErrors;

  /// Capture **native** crashes (Objective-C/Swift exceptions, signals like
  /// `SIGSEGV`/`SIGABRT`, OOM kills, ANRs, NDK crashes) that take down the
  /// whole process before any Dart can run. The OS records them — MetricKit
  /// on iOS 14+, `ApplicationExitInfo` on Android 11+ — and the SDK replays
  /// them as `fatal` events on the **next launch**.
  ///
  /// Requires a real device build (the native plugin must be compiled in).
  /// Silently no-ops if the native side is missing or platform unsupported.
  /// Default: true.
  final bool captureNativeCrashes;

  /// Auto-detect OS / device / locale context. Default: true.
  final bool autoContext;

  /// Anonymous user id, included in every event for grouping by user.
  final String? userIdAnon;

  /// Static tags merged into every event.
  final Map<String, String>? tags;

  /// Maximum stack frames sent. Default: 50.
  final int maxStackFrames;

  /// Last hook before sending — return null to drop the event.
  final Map<String, dynamic>? Function(Map<String, dynamic> event)? beforeSend;

  /// Release Health — opens a session at [Pionne.init] with status='ok' and
  /// flips it to 'crashed'/'errored' if a fatal/error fires through the
  /// global handlers. The dashboard derives crash-free user rate per
  /// release. Default: true.
  final bool releaseHealth;

  /// Token-bucket rate limit (events/sec). Default 10, set 0 to disable.
  /// Drops silently when exceeded — protège l'app d'un runaway loop et
  /// plafonne l'impact sur ton quota Pionne mensuel.
  final int maxEventsPerSecond;

  /// Opt-in: resolve approximate user geography (city, region, country) once
  /// at startup via a free IP→location lookup, and attach it to every event
  /// under `contexts.geo`. Off by default for privacy.
  final bool sendGeography;

  /// Override the IP→geography endpoint. Must return JSON with at least
  /// `city`, `region`, `country` (or `country_name`), and `country_code`
  /// fields. Default: `https://ipapi.co/json/`.
  final String geographyEndpoint;
}

/// Convenience type alias — events are just JSON-serialisable maps so the
/// payload stays exactly compatible with the other Pionne SDKs (RN, web,
/// node). Manipulate them as plain `Map<String, dynamic>`.
typedef PionneEvent = Map<String, dynamic>;
