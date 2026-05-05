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
enum MechanismType { flutterError, platformError, runZonedGuarded, manual }

extension MechanismTypeString on MechanismType {
  String get wireValue => switch (this) {
        MechanismType.flutterError => 'flutter_error',
        MechanismType.platformError => 'platform_error',
        MechanismType.runZonedGuarded => 'run_zoned_guarded',
        MechanismType.manual => 'manual',
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
    this.autoContext = true,
    this.userIdAnon,
    this.tags,
    this.maxStackFrames = 50,
    this.beforeSend,
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
}

/// Convenience type alias — events are just JSON-serialisable maps so the
/// payload stays exactly compatible with the other Pionne SDKs (RN, web,
/// node). Manipulate them as plain `Map<String, dynamic>`.
typedef PionneEvent = Map<String, dynamic>;
