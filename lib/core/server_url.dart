/// Normalises and classifies the server URL a waiter pastes on first run.
library;

enum UrlSecurity {
  /// https: always allowed.
  secure,

  /// http to a private/local address: allowed in debug builds, or after the
  /// user explicitly confirms "insecure local server".
  insecureLocal,

  /// http to a public host: never allowed.
  insecurePublic,
}

class NormalizedUrl {
  const NormalizedUrl(this.url, this.security);
  final String url;
  final UrlSecurity security;

  @override
  String toString() => '$url ($security)';
}

class ServerUrlException implements Exception {
  ServerUrlException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Paths a waiter might paste from the browser that are not part of the site root.
const _strippedSegments = {'app', 'desk', 'login', 'pos', 'api'};

NormalizedUrl normalizeServerUrl(String input) {
  var s = input.trim();
  if (s.isEmpty) throw ServerUrlException('empty');
  // Remove whitespace inside (copied from chat apps) and surrounding quotes.
  s = s.replaceAll(RegExp(r'\s+'), '').replaceAll(RegExp('^["\']|["\']\$'), '');

  if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(s)) {
    s = 'https://$s';
  }
  final Uri uri;
  try {
    uri = Uri.parse(s);
  } on FormatException {
    throw ServerUrlException('invalid');
  }
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') throw ServerUrlException('invalid');
  if (uri.host.isEmpty || !_validHost(uri.host)) throw ServerUrlException('invalid');

  // Keep path segments up to the first known Desk/API segment (/app, /desk, ...).
  final kept = <String>[];
  for (final seg in uri.pathSegments) {
    if (seg.isEmpty) continue;
    if (_strippedSegments.contains(seg.toLowerCase())) break;
    kept.add(seg);
  }
  final path = kept.isEmpty ? '' : '/${kept.join('/')}';

  final host = uri.host.toLowerCase();
  final port = uri.hasPort ? ':${uri.port}' : '';
  final url = '$scheme://$host$port$path';

  final UrlSecurity security;
  if (scheme == 'https') {
    security = UrlSecurity.secure;
  } else if (isLocalHost(host)) {
    security = UrlSecurity.insecureLocal;
  } else {
    security = UrlSecurity.insecurePublic;
  }
  return NormalizedUrl(url, security);
}

bool _validHost(String host) {
  if (host.contains('..')) return false;
  return RegExp(r'^[a-zA-Z0-9.\-\[\]:]+$').hasMatch(host);
}

/// localhost, 127.x, 10.x, 192.168.x, 172.16-31.x
bool isLocalHost(String host) {
  if (host == 'localhost' || host.endsWith('.local')) return true;
  final m = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$').firstMatch(host);
  if (m == null) return false;
  final a = int.parse(m.group(1)!);
  final b = int.parse(m.group(2)!);
  if (a == 127 || a == 10) return true;
  if (a == 192 && b == 168) return true;
  if (a == 172 && b >= 16 && b <= 31) return true;
  return false;
}
