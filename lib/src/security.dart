// Mirror of @pionne/react-native security guards, ported to Dart.
// Same rules : HTTPS only in production, token format check, token-bucket
// rate limit. Kept in lock-step with the JS sibling.

const String _tokenPrefix = 'pio_live_';
const int _minTokenLength = _tokenPrefix.length + 16;

bool validateEndpoint(String endpoint, {required bool isDev}) {
  Uri uri;
  try {
    uri = Uri.parse(endpoint);
  } catch (_) {
    return false;
  }
  if (uri.scheme == 'https') return true;
  if (uri.scheme != 'http') return false;
  if (!isDev) return false;
  final h = uri.host.toLowerCase();
  return h == 'localhost' ||
      h == '127.0.0.1' ||
      h == '0.0.0.0' ||
      h == '[::1]' ||
      h.endsWith('.local');
}

bool validateToken(String? token) {
  if (token == null) return false;
  if (!token.startsWith(_tokenPrefix)) return false;
  if (token.length < _minTokenLength) return false;
  final lower = token.toLowerCase();
  for (final bad in const ['xxx', 'yyy', 'todo', 'fixme', 'replace', 'changeme']) {
    if (lower.contains(bad)) return false;
  }
  return true;
}

class RateLimiter {
  final int capacity;
  final double refillPerSecond;
  double _tokens;
  DateTime _lastRefill;

  RateLimiter(this.capacity, this.refillPerSecond)
      : _tokens = capacity.toDouble(),
        _lastRefill = DateTime.now();

  bool allow() {
    if (refillPerSecond <= 0) return true;
    final now = DateTime.now();
    final elapsedMs = now.difference(_lastRefill).inMilliseconds;
    if (elapsedMs > 0) {
      final refill = (elapsedMs / 1000.0) * refillPerSecond;
      _tokens = (_tokens + refill).clamp(0, capacity.toDouble());
      _lastRefill = now;
    }
    if (_tokens >= 1) {
      _tokens -= 1;
      return true;
    }
    return false;
  }
}
