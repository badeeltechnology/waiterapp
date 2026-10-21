import 'package:intl/intl.dart';

/// One money formatter for the whole app, driven by the profile currency.
class Money {
  Money({this.currency = 'QAR', this.precision = 2})
      : _f = NumberFormat.currency(locale: 'en', symbol: '', decimalDigits: precision);
  final String currency;
  final int precision;
  final NumberFormat _f;

  /// "28.00"
  String amount(num v) => _f.format(v).trim();

  /// "QAR 28.00"
  String withCode(num v) => '$currency ${amount(v)}';
}

/// Lowercases and folds Arabic letter variants and diacritics so "اسبريسو"
/// matches "إسبريسو" and tashkeel never blocks a search.
String normalizeForSearch(String s) {
  var out = s.toLowerCase();
  out = out.replaceAll(RegExp('[ً-ٰٟـ]'), ''); // tashkeel + tatweel
  out = out.replaceAll(RegExp('[آأإٱ]'), 'ا'); // alef forms -> ا
  out = out.replaceAll('ى', 'ي'); // ى -> ي
  out = out.replaceAll('ة', 'ه'); // ة -> ه
  out = out.replaceAll('ؤ', 'و'); // ؤ -> و
  out = out.replaceAll('ئ', 'ي'); // ئ -> ي
  return out.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Whole minutes between [since] and [now], never negative.
int minutesSince(DateTime? since, DateTime now) {
  if (since == null) return 0;
  final m = now.difference(since).inMinutes;
  return m < 0 ? 0 : m;
}

String hhmm(DateTime t) => DateFormat('HH:mm').format(t);

/// Phone clock corrected by the offset seen at login / me.
class ServerClock {
  ServerClock._();
  static Duration offset = Duration.zero;
  static DateTime now() => DateTime.now().add(offset);

  static void syncFrom(DateTime? serverTime) {
    if (serverTime == null) return;
    final o = serverTime.difference(DateTime.now());
    // Ignore absurd values (bad server clock); trust the phone then.
    offset = o.abs() < const Duration(hours: 12) ? o : Duration.zero;
  }
}
