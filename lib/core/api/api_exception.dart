import 'dart:convert';

/// Everything the API layer throws. Screens show [message]; they never show raw
/// exception text.
sealed class ApiException implements Exception {
  const ApiException(this.message);
  final String message;
  @override
  String toString() => message;

  /// True when retrying the same request later may succeed (offline queue).
  bool get isTransient => false;
}

/// 401 / AuthenticationError on an authenticated call: the device session is gone.
class SessionExpiredException extends ApiException {
  const SessionExpiredException([super.message = 'Your session ended. Please sign in again.']);
}

/// Login rejected (wrong password, disabled user, no waiter record...).
class LoginRejectedException extends ApiException {
  const LoginRejectedException(super.message);
}

/// No connection, DNS failure, TLS failure, connection reset.
class NetworkException extends ApiException {
  const NetworkException([super.message = 'No connection to the server.']);
  @override
  bool get isTransient => true;
}

class TimeoutApiException extends ApiException {
  const TimeoutApiException([super.message = 'The server took too long to answer.']);
  @override
  bool get isTransient => true;
}

/// Server answered with an error. [statusCode] >= 500 or 429 is transient.
class ServerException extends ApiException {
  const ServerException(super.message, {required this.statusCode, this.excType});
  final int statusCode;
  final String? excType;
  @override
  bool get isTransient => statusCode >= 500 || statusCode == 429 || statusCode == 408;
}

/// The response was not the JSON we expected.
class BadResponseException extends ApiException {
  const BadResponseException([super.message = 'Unexpected answer from the server.']);
}

/// Pulls a human message out of a Frappe error body.
///
/// Frappe sends `_server_messages` as a JSON-encoded list of JSON-encoded
/// objects with a `message` field; sometimes `message` or `exception` instead.
({String? message, String? excType}) parseFrappeError(String body) {
  Object? decoded;
  try {
    decoded = jsonDecode(body);
  } catch (_) {
    return (message: null, excType: null);
  }
  if (decoded is! Map) return (message: null, excType: null);
  final excType = decoded['exc_type']?.toString();
  String? msg;
  final sm = decoded['_server_messages'];
  if (sm is String && sm.isNotEmpty) {
    try {
      final list = jsonDecode(sm);
      if (list is List && list.isNotEmpty) {
        final first = list.first;
        if (first is String) {
          try {
            final inner = jsonDecode(first);
            msg = inner is Map ? inner['message']?.toString() : first;
          } catch (_) {
            msg = first;
          }
        } else if (first is Map) {
          msg = first['message']?.toString();
        }
      }
    } catch (_) {}
  }
  if (msg == null && decoded['message'] is String) msg = decoded['message'] as String;
  if (msg == null && decoded['exception'] is String) {
    // "frappe.exceptions.ValidationError: Item X is not available"
    final e = decoded['exception'] as String;
    final i = e.indexOf(': ');
    msg = i > 0 ? e.substring(i + 2) : e;
  }
  return (message: msg == null ? null : stripHtml(msg), excType: excType);
}

String stripHtml(String s) => s
    .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
    .replaceAll(RegExp(r'<[^>]+>'), '')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .trim();

/// Maps an HTTP error response to an [ApiException].
///
/// [isLogin] marks the login call itself: a 401 there means bad credentials,
/// not an expired session.
ApiException mapHttpError(int status, String body, {bool isLogin = false}) {
  final parsed = parseFrappeError(body);
  final excType = parsed.excType;
  final serverMsg = parsed.message;
  final isAuth = status == 401 || excType == 'AuthenticationError' || excType == 'SessionExpired';
  if (isLogin) {
    if (status == 429 || excType == 'TooManyRequestsError') {
      return LoginRejectedException(serverMsg ?? 'Too many attempts. Wait a few minutes and try again.');
    }
    if (isAuth || status == 403 || status == 417) {
      return LoginRejectedException(serverMsg ?? 'Wrong username or password.');
    }
  } else if (isAuth) {
    return const SessionExpiredException();
  }
  final fallback = switch (status) {
    403 => 'You are not allowed to do this.',
    404 => 'Not found on the server. Is the ServePOS app up to date?',
    408 => 'The server took too long to answer.',
    429 => 'Too many requests. Wait a moment.',
    >= 500 => 'The server had a problem (HTTP $status). Try again.',
    _ => 'Request failed (HTTP $status).',
  };
  return ServerException(serverMsg ?? fallback, statusCode: status, excType: excType);
}
