import 'package:flutter/foundation.dart';

import '../models/notification_item.dart';
import 'hive_service.dart';

/// On-device notification inbox. Hive is the source of truth.
///
/// Captures OneSignal pushes (foreground display + tap) and local Daily Quiz
/// reminder taps. Does **not** invent rows — a fresh install is empty.
///
/// Safe to call before the first frame: [add] no-ops until Hive is open,
/// then [reload] picks up anything written after.
class NotificationInbox extends ChangeNotifier {
  NotificationInbox._();
  static final NotificationInbox instance = NotificationInbox._();

  static const maxEntries = 100;

  List<NotificationItem> _items = const [];
  bool _loaded = false;

  List<NotificationItem> get items {
    _ensureLoaded();
    return List<NotificationItem>.unmodifiable(_items);
  }

  int get unreadCount {
    _ensureLoaded();
    return unreadIn(_items);
  }

  bool get isEmpty => items.isEmpty;

  /// Re-read Hive (dashboard start, history screen).
  void reload() {
    _loaded = false;
    _ensureLoaded();
    notifyListeners();
  }

  /// Insert or merge by [NotificationItem.id]. Newest first. Caps at
  /// [maxEntries]. Empty title+body is ignored so a malformed push does
  /// not create a blank card.
  Future<void> add(NotificationItem item) async {
    if (item.id.isEmpty) return;
    if (item.title.trim().isEmpty && item.body.trim().isEmpty) return;
    _ensureLoaded();
    final next = insert(_items, item);
    if (_same(next, _items)) return;
    _items = next;
    notifyListeners();
    await _persist();
  }

  Future<void> markRead(String id) async {
    _ensureLoaded();
    final next = [
      for (final item in _items)
        if (item.id == id && !item.read) item.copyWith(read: true) else item,
    ];
    if (_same(next, _items)) return;
    _items = next;
    notifyListeners();
    await _persist();
  }

  Future<void> markAllRead() async {
    _ensureLoaded();
    if (unreadIn(_items) == 0) return;
    _items = [
      for (final item in _items)
        if (item.read) item else item.copyWith(read: true),
    ];
    notifyListeners();
    await _persist();
  }

  /// Test-only: drop in-memory state so a later [reload] re-reads Hive.
  @visibleForTesting
  void debugReset() {
    _items = const [];
    _loaded = false;
  }

  Future<void> clear() async {
    _ensureLoaded();
    if (_items.isEmpty) return;
    _items = const [];
    notifyListeners();
    if (HiveService.isInitialized) {
      await HiveService.clearNotificationHistory();
    }
  }

  // ---------------------------------------------------------- pure logic --

  /// Merge [incoming] into [items]. Exposed for unit tests (no Hive).
  static List<NotificationItem> insert(
    List<NotificationItem> items,
    NotificationItem incoming,
  ) {
    final index = items.indexWhere((e) => e.id == incoming.id);
    if (index >= 0) {
      final old = items[index];
      final updated = old.copyWith(
        title: incoming.title.trim().isNotEmpty ? incoming.title : old.title,
        body: incoming.body.trim().isNotEmpty ? incoming.body : old.body,
        open: (incoming.open != null && incoming.open!.isNotEmpty)
            ? incoming.open
            : old.open,
        // Once read, a second delivery of the same id stays read.
        read: old.read,
      );
      if (updated.title == old.title &&
          updated.body == old.body &&
          updated.open == old.open &&
          updated.read == old.read) {
        return items;
      }
      final next = [...items];
      next[index] = updated;
      return next;
    }
    final next = [incoming, ...items];
    if (next.length > maxEntries) {
      return next.sublist(0, maxEntries);
    }
    return next;
  }

  static int unreadIn(List<NotificationItem> items) {
    var n = 0;
    for (final item in items) {
      if (!item.read) n++;
    }
    return n;
  }

  // -------------------------------------------------------------- intern --

  void _ensureLoaded() {
    if (_loaded) return;
    _loaded = true;
    if (!HiveService.isInitialized) {
      _items = const [];
      return;
    }
    _items = HiveService.loadNotificationHistory();
  }

  Future<void> _persist() async {
    if (!HiveService.isInitialized) return;
    try {
      await HiveService.saveNotificationHistory(_items);
    } catch (e) {
      debugPrint('NotificationInbox: persist failed – $e');
    }
  }

  static bool _same(List<NotificationItem> a, List<NotificationItem> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id ||
          a[i].read != b[i].read ||
          a[i].title != b[i].title ||
          a[i].body != b[i].body ||
          a[i].open != b[i].open) {
        return false;
      }
    }
    return true;
  }
}
