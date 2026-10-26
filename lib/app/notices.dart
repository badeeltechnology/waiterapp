import 'package:flutter/foundation.dart';

enum NoticeKind { sent, accepted, ready, rejected }

/// A short in-app message shown on top of every screen.
class Notice {
  Notice({required this.kind, required this.title, this.order, this.detail});
  final NoticeKind kind;
  final String title;
  final String? order;
  final String? detail;
  final DateTime at = DateTime.now();
}

/// Queue of in-app notices (order accepted / ready at the till, background sends).
class Notices extends ChangeNotifier {
  final List<Notice> _queue = [];
  Notice? get current => _queue.firstOrNull;
  int get length => _queue.length;

  void show(Notice n) {
    _queue.add(n);
    if (_queue.length > 5) _queue.removeAt(0);
    notifyListeners();
  }

  void dismiss(Notice n) {
    if (_queue.remove(n)) notifyListeners();
  }

  void clear() {
    _queue.clear();
    notifyListeners();
  }
}
