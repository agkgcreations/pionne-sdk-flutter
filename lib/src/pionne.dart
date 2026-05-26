import 'dart:async' as async;
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io' show Platform;
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'native_crash.dart';
import 'security.dart' as security;
import 'sessions.dart' as sessions;
import 'types.dart';

const String _sdkName = 'pionne.flutter';
const String _sdkVersion = '0.4.0';

/// Pionne SDK entrypoint. Stateless namespace — call [Pionne.init] once at
/// app boot, then use [Pionne.captureException] / [Pionne.captureMessage]
/// from anywhere.
class Pionne {
  Pionne._();

  static PionneOptions? _options;
  static Map<String, dynamic> _staticContext = {};
  static String? _userIdAnon;
  static Map<String, String>? _tags;
  static bool _enabled = true;
  static FlutterExceptionHandler? _previousFlutterHandler;
  static bool Function(Object, StackTrace)? _previousPlatformHandler;
  static security.RateLimiter? _rateLimiter;
  static int _droppedByRateLimit = 0;

  /// Initialise the SDK. Call this once, at the very top of `main()`,
  /// **before** `runApp(...)`. Safe to call multiple times — subsequent
  /// calls replace the previous configuration.
  ///
  /// Returns synchronously. Static context (OS, device) is gathered
  /// best-effort from Dart's `dart:io Platform`.
  static void init(PionneOptions options) {
    try {
      if (!security.validateToken(options.token)) {
        if (kDebugMode) {
          // ignore: avoid_print
          print('[Pionne] Missing or invalid token (expected pio_live_<≥16 chars>, no placeholders).');
        }
        return;
      }
      if (!security.validateEndpoint(options.endpoint, isDev: kDebugMode)) {
        // ignore: avoid_print
        print('[Pionne] Refusing non-HTTPS endpoint in production: ${options.endpoint}');
        return;
      }
      final rps = options.maxEventsPerSecond;
      _rateLimiter = rps > 0 ? security.RateLimiter(rps, rps.toDouble()) : null;

    _options = options;
    _userIdAnon = options.userIdAnon;
    _tags = options.tags;
    _enabled = options.enabled;
    _staticContext = options.autoContext ? _gatherStaticContext() : {};

    if (options.captureFlutterErrors) _installFlutterHandler();
    if (options.capturePlatformErrors) _installPlatformHandler();
    if (options.sendGeography) _fetchGeography(options.geographyEndpoint);

    // Native crashes from previous run(s) (MetricKit / ApplicationExitInfo).
    // Silently no-ops on web or when the native plugin isn't linked.
    if (options.captureNativeCrashes) {
      _replayNativeCrashes();
      // MetricKit delivers ~a few seconds after the launch that follows the
      // crash, so a second pass catches a payload surfaced during *this*
      // session. The native side clears on read → no double-report.
      Future.delayed(const Duration(seconds: 5), _replayNativeCrashes);
    }

    // Release Health — open a session unless the host opted out.
    if (options.releaseHealth) {
      sessions.startSession(sessions.SessionContext(
        endpoint: options.endpoint,
        token: options.token,
        release: options.release,
        environment: options.environment,
        appVersion: _staticContext['app_version'] as String?,
        osName: _staticContext['os_name'] as String?,
        userIdAnon: options.userIdAnon,
      ));
    }
    } catch (e) {
      // ignore: avoid_print
      print('[Pionne] init failed silently — monitoring disabled. $e');
      _options = null;
    }
  }

  /// Manually end the current release session (`status='exited'`).
  static void endSession() => sessions.endSession();

  /// UUID of the current open session (for diagnostics).
  static String? getSessionId() => sessions.getCurrentSessionId();

  /// Manually capture an exception. Safe to call before [init] (no-op).
  static void captureException(
    Object error, {
    StackTrace? stackTrace,
    Level? level,
    Map<String, String>? tags,
    String? userIdAnon,
  }) {
    final ev = _buildEvent(
      error,
      stackTrace,
      level ?? Level.error,
      MechanismType.manual,
      true,
      tags: tags,
      userIdAnon: userIdAnon,
    );
    if (ev != null) _send(ev);
  }

  /// Capture a string message (useful for non-error events).
  static void captureMessage(
    String message, {
    Level? level,
    Map<String, String>? tags,
    String? userIdAnon,
  }) {
    final ev = _buildEvent(
      Exception(message),
      StackTrace.current,
      level ?? Level.info,
      MechanismType.manual,
      true,
      exceptionType: 'Message',
      tags: tags,
      userIdAnon: userIdAnon,
    );
    if (ev != null) _send(ev);
  }

  /// Set / update the anonymous user id sent with every event.
  static void setUser(String? userIdAnon) {
    _userIdAnon = userIdAnon;
  }

  /// Merge tags applied to every event. Pass null to clear.
  static void setTags(Map<String, String>? tags) {
    _tags = tags;
  }

  /// Toggle reporting at runtime (e.g. after user opts out).
  static void setEnabled(bool enabled) {
    _enabled = enabled;
  }

  /// Detach all auto handlers and reset state. Useful in tests / hot reload.
  static void uninstall() {
    if (_previousFlutterHandler != null) {
      FlutterError.onError = _previousFlutterHandler;
      _previousFlutterHandler = null;
    }
    if (_previousPlatformHandler != null) {
      PlatformDispatcher.instance.onError = _previousPlatformHandler;
      _previousPlatformHandler = null;
    }
    _options = null;
    _staticContext = {};
    _userIdAnon = null;
    _tags = null;
    _enabled = false;
    _warnedPermFailure = false;
  }

  /// Wrap a callable so any uncaught synchronous OR asynchronous error
  /// inside it is reported. Use this at the top of `main()` if you want
  /// a 100 % capture rate including isolate-level zone errors.
  ///
  ///   void main() {
  ///     Pionne.init(PionneOptions(token: '...'));
  ///     Pionne.runZonedGuarded(() => runApp(const MyApp()));
  ///   }
  static void runZonedGuarded(void Function() body) {
    async.runZonedGuarded(body, (error, stack) {
      final ev = _buildEvent(
        error,
        stack,
        Level.fatal,
        MechanismType.runZonedGuarded,
        false,
      );
      if (ev != null) {
        _send(ev);
        sessions.flipFromLevel(ev['level'] as String?, MechanismType.runZonedGuarded.wireValue);
      }
    });
  }

  // ─── internals ───────────────────────────────────────────────────────────

  static Map<String, dynamic> _gatherStaticContext() {
    String? timezone;
    try {
      timezone = DateTime.now().timeZoneName;
    } catch (_) {
      // ignore
    }

    final os = <String, dynamic>{
      'name': Platform.operatingSystem,
      'version': Platform.operatingSystemVersion,
    };
    final runtime = <String, dynamic>{
      'name': 'dart',
      'version': Platform.version,
      'js_engine': kIsWeb ? 'web' : 'dart_vm',
    };
    final device = <String, dynamic>{
      'locale': Platform.localeName,
      'timezone': timezone,
      'cpu_count': Platform.numberOfProcessors,
    };
    final app = <String, dynamic>{
      'in_foreground': true,
      'debug': kDebugMode,
      'profile': kProfileMode,
      'release': kReleaseMode,
    };

    return {
      'os_name': Platform.operatingSystem,
      'os_version': Platform.operatingSystemVersion,
      'locale': Platform.localeName,
      'timezone': timezone,
      'contexts': {
        'sdk': {'name': _sdkName, 'version': _sdkVersion},
        'os': os,
        'device': device,
        'runtime': runtime,
        'app': app,
      },
    };
  }

  static List<String> _parseStack(Object? error, StackTrace? stack, int max) {
    final raw = (stack ?? (error is Error ? error.stackTrace : null) ?? StackTrace.current).toString();
    final lines = raw.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    return lines.take(max).toList();
  }

  static String _exceptionType(Object error) {
    if (error is Error) return error.runtimeType.toString();
    return error.runtimeType.toString();
  }

  static Map<String, dynamic>? _buildEvent(
    Object error,
    StackTrace? stack,
    Level level,
    MechanismType mechanism,
    bool handled, {
    String? exceptionType,
    Map<String, String>? tags,
    String? userIdAnon,
  }) {
    final opts = _options;
    if (opts == null || !_enabled) return null;

    final maxStack = opts.maxStackFrames;
    final defaultEnv = kDebugMode ? 'debug' : 'production';

    final mergedTags = <String, String>{
      if (_tags != null) ..._tags!,
      if (tags != null) ...tags,
    };

    final event = <String, dynamic>{
      ..._staticContext,
      'exception_type': exceptionType ?? _exceptionType(error),
      'message': _messageOf(error),
      'stack': _parseStack(error, stack, maxStack),
      'level': level.wireValue,
      if (opts.release != null) 'release': opts.release,
      'environment': opts.environment ?? defaultEnv,
      if (userIdAnon != null || _userIdAnon != null)
        'user_id_anon': userIdAnon ?? _userIdAnon,
      if (mergedTags.isNotEmpty) 'tags': mergedTags,
      'mechanism': {
        'type': mechanism.wireValue,
        'handled': handled,
      },
    };

    final hook = opts.beforeSend;
    if (hook != null) {
      final out = hook(event);
      if (out == null) return null;
      return out;
    }
    return event;
  }

  static String _messageOf(Object error) {
    if (error is Exception || error is Error) return error.toString();
    return error.toString();
  }

  static Future<void> _send(Map<String, dynamic> event) async {
    final opts = _options;
    if (opts == null) return;
    if (_rateLimiter != null && !_rateLimiter!.allow()) {
      _droppedByRateLimit++;
      if (kDebugMode && _droppedByRateLimit % 50 == 1) {
        // ignore: avoid_print
        print('[Pionne] rate-limit reached ($_droppedByRateLimit events dropped). Bump maxEventsPerSecond if intentional.');
      }
      return;
    }
    try {
      final res = await http.post(
        Uri.parse(opts.endpoint),
        headers: {
          'Content-Type': 'application/json',
          'X-Pionne-Token': opts.token,
        },
        body: jsonEncode(event),
      );

      // 401/403/422 = permanent config issues that retries won't fix.
      // Surface once per process (even in release builds) via
      // developer.log so the dev sees a misconfigured token / bundle /
      // validation in their console without having to attach a
      // debugger. Network errors stay silent (transient).
      final code = res.statusCode;
      if (!_warnedPermFailure && (code == 401 || code == 403 || code == 422)) {
        _warnedPermFailure = true;
        final raw = res.body;
        Map<String, dynamic>? parsed;
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map<String, dynamic>) parsed = decoded;
        } catch (_) {
          // not JSON
        }
        final sentAppId = (event['app_id'] is String) ? event['app_id'] as String : '<unset>';
        final serverMsg = (parsed?['message'] is String)
            ? parsed!['message'] as String
            : raw.length > 200 ? raw.substring(0, 200) : raw;
        final expectedFormat = (parsed?['expected_format'] is String)
            ? parsed!['expected_format'] as String
            : 'unknown';

        String msg;
        if (code == 403 && RegExp(r'bundle\s*id', caseSensitive: false).hasMatch(serverMsg)) {
          msg =
              '[Pionne] Bundle ID mismatch — your project rejects events from app_id="$sentAppId". '
              'Server expected "$expectedFormat" (1st char masked for safety). '
              'Fix it in your Pionne project Settings → Bundle ID, or clear the field to disable the check. '
              'Subsequent rejections will be silent for this session.';
        } else if (code == 401) {
          msg =
              '[Pionne] Token rejected (401). Check that your project token (starts with "pio_live_…") matches. '
              'Server said: $serverMsg. Subsequent rejections will be silent for this session.';
        } else if (code == 422) {
          msg =
              '[Pionne] Event rejected (422 validation): $serverMsg. '
              'Sent app_id="$sentAppId". Subsequent rejections will be silent for this session.';
        } else {
          msg =
              '[Pionne] Event rejected (status=$code): $serverMsg. '
              'Sent app_id="$sentAppId". Subsequent rejections will be silent for this session.';
        }
        developer.log(msg, name: 'Pionne');
      }
    } catch (_) {
      // Best-effort: a monitoring SDK must never crash the host app.
    }
  }

  /// Module-level flag — gates the permanent-failure warning to one
  /// log per Dart isolate. Reset on `Pionne.uninstall()` so a re-init
  /// can re-warn if needed.
  static bool _warnedPermFailure = false;

  /// Fire-and-forget IP→geo lookup. Mutates `_staticContext['contexts']['geo']`
  /// once it resolves so subsequent events carry the location. Failures are
  /// silent — a monitoring SDK must never crash or stall the host app.
  static Future<void> _fetchGeography(String endpoint) async {
    try {
      final res = await http
          .get(
            Uri.parse(endpoint),
            headers: {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 4));
      if (res.statusCode < 200 || res.statusCode >= 300) return;
      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) return;
      final geo = <String, dynamic>{};
      final city = decoded['city'];
      if (city is String && city.isNotEmpty) geo['city'] = city;
      final region = decoded['region'];
      if (region is String && region.isNotEmpty) geo['region'] = region;
      final countryName = decoded['country_name'];
      final country = decoded['country'];
      if (countryName is String && countryName.isNotEmpty) {
        geo['country'] = countryName;
      } else if (country is String && country.isNotEmpty) {
        geo['country'] = country;
      }
      final cc = decoded['country_code'];
      if (cc is String && cc.isNotEmpty) geo['country_code'] = cc;
      if (geo.isEmpty) return;

      final contexts = Map<String, dynamic>.from(
        (_staticContext['contexts'] as Map?)?.cast<String, dynamic>() ?? {},
      );
      contexts['geo'] = geo;
      _staticContext = {..._staticContext, 'contexts': contexts};
    } catch (_) {
      // Best-effort: silently ignore lookup failures.
    }
  }

  static void _installFlutterHandler() {
    _previousFlutterHandler = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      final ev = _buildEvent(
        details.exception,
        details.stack,
        Level.error,
        MechanismType.flutterError,
        false,
      );
      if (ev != null) {
        _send(ev);
        sessions.flipFromLevel(ev['level'] as String?, MechanismType.flutterError.wireValue);
      }
      _previousFlutterHandler?.call(details);
    };
  }

  static void _installPlatformHandler() {
    _previousPlatformHandler = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      final ev = _buildEvent(
        error,
        stack,
        Level.fatal,
        MechanismType.platformError,
        false,
      );
      if (ev != null) {
        _send(ev);
        sessions.flipFromLevel(ev['level'] as String?, MechanismType.platformError.wireValue);
      }
      // Returning false lets Flutter's default handler also process the error.
      return _previousPlatformHandler?.call(error, stack) ?? false;
    };
  }

  /// Drain the native crashes the OS recorded on previous run(s) and replay each
  /// as a `fatal` event. These come from a *past* process, so we use plain
  /// [_send] — never [sessions.flipFromLevel], which would wrongly mark the
  /// *current* session as crashed.
  static Future<void> _replayNativeCrashes() async {
    final opts = _options;
    if (opts == null || !_enabled) return;
    final records = await getPendingNativeCrashes();
    if (records.isEmpty) return;
    final defaultEnv = kDebugMode ? 'debug' : 'production';
    for (final r in records) {
      final mergedTags = <String, String>{
        if (_tags != null) ..._tags!,
        'native.source': r.platform == 'ios' ? 'metrickit' : 'app_exit',
        'native.crashed_at': DateTime.fromMillisecondsSinceEpoch(
          r.timestamp,
          isUtc: true,
        ).toIso8601String(),
      };
      final event = <String, dynamic>{
        ..._staticContext,
        'exception_type': r.type,
        'message': r.message,
        if (r.stack.isNotEmpty) 'stack': r.stack,
        'level': Level.fatal.wireValue,
        if (opts.release != null) 'release': opts.release,
        'environment': opts.environment ?? defaultEnv,
        if (r.appVersion != null) 'app_version': r.appVersion,
        if (r.osVersion != null) 'os_version': r.osVersion,
        if (_userIdAnon != null) 'user_id_anon': _userIdAnon,
        if (mergedTags.isNotEmpty) 'tags': mergedTags,
        'mechanism': {
          'type': MechanismType.native.wireValue,
          'handled': false,
        },
      };
      final hook = opts.beforeSend;
      final out = hook != null ? hook(event) : event;
      if (out != null) {
        // ignore: unawaited_futures
        _send(out);
      }
    }
  }
}
