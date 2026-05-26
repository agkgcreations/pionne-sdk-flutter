// Native crash bridge.
//
// Dart-side error handlers (`FlutterError.onError`, `PlatformDispatcher.onError`,
// `runZonedGuarded`) can NEVER see a native crash: when the Objective-C/Swift
// or JVM/NDK side dies, the whole process — including the Dart isolate — is
// gone before any Dart runs. So we lean on the OS:
//   - iOS 14+    : MetricKit (MXCrashDiagnostic), delivered on the next launch
//   - Android 11+: ActivityManager.getHistoricalProcessExitReasons()
//
// The native plugin persists these and we drain them here on init(), turning
// each into a `fatal` event with mechanism.type = 'native'.
//
// Best-effort and never blocking: the native side may be absent (web target,
// dart-only tests, package not registered yet because the host forgot to
// re-run `flutter pub get` + a build). In every such case the channel call
// throws MissingPluginException, which we swallow into an empty list.

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show MethodChannel, MissingPluginException;

const MethodChannel _channel = MethodChannel('fr.pionne.flutter/native_crash');

/// One past-process death the OS attributed to a crash/abnormal exit.
class NativeCrashRecord {
  NativeCrashRecord({
    required this.platform,
    required this.type,
    required this.message,
    required this.timestamp,
    required this.stack,
    this.appVersion,
    this.osVersion,
  });

  /// `'ios'` or `'android'`.
  final String platform;

  /// Short type label, e.g. `"SIGSEGV"`, `"NSInvalidArgumentException"`,
  /// `"REASON_CRASH_NATIVE"`.
  final String type;

  /// Human-readable reason / OS description.
  final String message;

  /// Epoch milliseconds of the crash (previous run).
  final int timestamp;

  /// Best-effort frames. Native app frames are unsymbolicated.
  final List<String> stack;

  /// App version that was running when it crashed (may differ from current).
  final String? appVersion;

  /// OS version at crash time.
  final String? osVersion;

  static NativeCrashRecord? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final type = raw['type'];
    final message = raw['message'];
    final timestamp = raw['timestamp'];
    if (type is! String || message is! String) return null;
    return NativeCrashRecord(
      platform: raw['platform'] is String ? raw['platform'] as String : 'unknown',
      type: type,
      message: message,
      timestamp: timestamp is int ? timestamp : (timestamp is num ? timestamp.toInt() : 0),
      stack: switch (raw['stack']) {
        final List l => l.whereType<String>().toList(),
        _ => const <String>[],
      },
      appVersion: raw['appVersion'] is String ? raw['appVersion'] as String : null,
      osVersion: raw['osVersion'] is String ? raw['osVersion'] as String : null,
    );
  }
}

/// Drain the OS-recorded native crashes from the previous run(s). Resolves to
/// an empty list (never throws) when the native plugin is unavailable or any
/// step fails — a monitoring SDK must never throw into the host's init path.
Future<List<NativeCrashRecord>> getPendingNativeCrashes() async {
  if (kIsWeb) return const <NativeCrashRecord>[];
  try {
    final raw = await _channel.invokeMethod<List<dynamic>>('getPendingNativeCrashes');
    if (raw == null) return const <NativeCrashRecord>[];
    return raw
        .map(NativeCrashRecord.fromMap)
        .whereType<NativeCrashRecord>()
        .toList(growable: false);
  } on MissingPluginException {
    return const <NativeCrashRecord>[];
  } catch (_) {
    return const <NativeCrashRecord>[];
  }
}
