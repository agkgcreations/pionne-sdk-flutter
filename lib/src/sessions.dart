import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

/// Release Health — session manager for the Flutter SDK.
/// Same protocol as the JS/RN SDKs: open with status='ok' at init(), flip to
/// 'crashed'/'errored' from the global handlers, fire 'exited' on shutdown.

enum SessionStatus { ok, crashed, errored, abnormal, exited }

extension on SessionStatus {
  String get wire {
    switch (this) {
      case SessionStatus.ok:
        return 'ok';
      case SessionStatus.crashed:
        return 'crashed';
      case SessionStatus.errored:
        return 'errored';
      case SessionStatus.abnormal:
        return 'abnormal';
      case SessionStatus.exited:
        return 'exited';
    }
  }

  int get rank {
    switch (this) {
      case SessionStatus.ok:
        return 0;
      case SessionStatus.exited:
        return 1;
      case SessionStatus.errored:
        return 2;
      case SessionStatus.abnormal:
        return 3;
      case SessionStatus.crashed:
        return 4;
    }
  }
}

class SessionContext {
  final String endpoint;
  final String token;
  final String? release;
  final String? environment;
  final String? appVersion;
  final String? osName;
  final String? userIdAnon;

  const SessionContext({
    required this.endpoint,
    required this.token,
    this.release,
    this.environment,
    this.appVersion,
    this.osName,
    this.userIdAnon,
  });
}

class _SessionState {
  final String id;
  final DateTime startedAt;
  SessionStatus status;
  final SessionContext ctx;

  _SessionState(this.id, this.startedAt, this.status, this.ctx);
}

_SessionState? _current;

String _uuid() {
  // RFC 4122 v4 with `dart:math.Random`. Not cryptographically secure but
  // collision-safe for our session-id usage (idempotent backend upsert).
  final rnd = Random();
  final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  String hex(int n) => n.toRadixString(16).padLeft(2, '0');
  final h = bytes.map(hex).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

String _sessionsUrl(String ingestEndpoint) {
  if (ingestEndpoint.endsWith('/ingest')) {
    final base = ingestEndpoint.substring(0, ingestEndpoint.length - '/ingest'.length);
    return '$base/sessions';
  }
  final base = ingestEndpoint.replaceAll(RegExp(r'/+$'), '');
  return '$base/sessions';
}

Future<void> _post(_SessionState state, SessionStatus status, {int? durationMs}) async {
  final body = <String, dynamic>{
    'session_id': state.id,
    'status': status.wire,
    if (state.ctx.release != null) 'release': state.ctx.release,
    if (state.ctx.environment != null) 'environment': state.ctx.environment,
    if (state.ctx.appVersion != null) 'app_version': state.ctx.appVersion,
    if (state.ctx.osName != null) 'os_name': state.ctx.osName,
    if (state.ctx.userIdAnon != null) 'user_id_anon': state.ctx.userIdAnon,
    if (durationMs != null) 'duration_ms': durationMs,
  };
  try {
    await http.post(
      Uri.parse(_sessionsUrl(state.ctx.endpoint)),
      headers: {
        'Content-Type': 'application/json',
        'X-Pionne-Token': state.ctx.token,
      },
      body: jsonEncode(body),
    );
  } catch (_) {
    // Best-effort: a monitoring SDK must never crash the host app.
  }
}

String startSession(SessionContext ctx) {
  _current = _SessionState(_uuid(), DateTime.now(), SessionStatus.ok, ctx);
  // Fire-and-forget — sessions are observability data, not critical.
  // ignore: discarded_futures
  _post(_current!, SessionStatus.ok);
  return _current!.id;
}

void flipSession(SessionStatus status) {
  final s = _current;
  if (s == null) return;
  if (status.rank <= s.status.rank) return;
  s.status = status;
  final dur = DateTime.now().difference(s.startedAt).inMilliseconds;
  // ignore: discarded_futures
  _post(s, status, durationMs: dur);
}

void endSession([SessionStatus status = SessionStatus.exited]) {
  if (_current == null) return;
  flipSession(status);
  _current = null;
}

String? getCurrentSessionId() => _current?.id;

void flipFromLevel(String? level, String mechanismType) {
  if (mechanismType == 'manual') return;
  if (level == 'fatal') {
    flipSession(SessionStatus.crashed);
  } else if (level == 'error') {
    flipSession(SessionStatus.errored);
  }
}
