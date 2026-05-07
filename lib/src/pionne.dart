import 'dart:async' as async;
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'sessions.dart' as sessions;
import 'types.dart';

const String _sdkName = 'pionne.flutter';
const String _sdkVersion = '0.1.0';

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

  /// Initialise the SDK. Call this once, at the very top of `main()`,
  /// **before** `runApp(...)`. Safe to call multiple times — subsequent
  /// calls replace the previous configuration.
  ///
  /// Returns synchronously. Static context (OS, device) is gathered
  /// best-effort from Dart's `dart:io Platform`.
  static void init(PionneOptions options) {
    if (!options.token.startsWith('pio_live_')) {
      if (kDebugMode) {
        // ignore: avoid_print
        print(
          '[Pionne] Missing or invalid token (must start with pio_live_).',
        );
      }
      return;
    }

    _options = options;
    _userIdAnon = options.userIdAnon;
    _tags = options.tags;
    _enabled = options.enabled;
    _staticContext = options.autoContext ? _gatherStaticContext() : {};

    if (options.captureFlutterErrors) _installFlutterHandler();
    if (options.capturePlatformErrors) _installPlatformHandler();

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
    try {
      await http.post(
        Uri.parse(opts.endpoint),
        headers: {
          'Content-Type': 'application/json',
          'X-Pionne-Token': opts.token,
        },
        body: jsonEncode(event),
      );
    } catch (_) {
      // Best-effort: a monitoring SDK must never crash the host app.
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
}
