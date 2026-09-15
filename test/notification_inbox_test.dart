import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:quizbaaz/data/models/notification_item.dart';
import 'package:quizbaaz/data/services/hive_service.dart';
import 'package:quizbaaz/data/services/notification_inbox.dart';

void main() {
  NotificationItem item({
    String id = 'a',
    String kind = NotificationItem.kindPush,
    String title = 'Hello',
    String body = 'World',
    String? open,
    DateTime? receivedAt,
    bool read = false,
  }) {
    return NotificationItem(
      id: id,
      kind: kind,
      title: title,
      body: body,
      open: open,
      receivedAt: receivedAt ?? DateTime(2026, 9, 6, 19),
      read: read,
    );
  }

  group('NotificationInbox.insert', () {
    test('prepends a new row', () {
      final first = item(id: '1', title: 'One');
      final second = item(id: '2', title: 'Two');
      final list = NotificationInbox.insert(
        NotificationInbox.insert(const [], first),
        second,
      );
      expect(list.map((e) => e.id), ['2', '1']);
    });

    test('same id does not duplicate; keeps original receivedAt and read', () {
      final original = item(id: 'os_1', title: 'A', body: 'old', read: true);
      final again = item(id: 'os_1', title: 'A', body: 'new', read: false);
      final list = NotificationInbox.insert([original], again);
      expect(list, hasLength(1));
      expect(list.first.body, 'new');
      expect(list.first.read, isTrue);
      expect(list.first.receivedAt, original.receivedAt);
    });

    test('empty title+body is still inserted by insert(); inbox.add filters it',
        () {
      final list = NotificationInbox.insert(
        const [],
        item(id: 'blank', title: '', body: ''),
      );
      expect(list, hasLength(1));
    });

    test('caps at maxEntries, dropping the oldest', () {
      var list = <NotificationItem>[];
      for (var i = 0; i < NotificationInbox.maxEntries + 5; i++) {
        list = NotificationInbox.insert(list, item(id: '$i', title: '$i'));
      }
      expect(list, hasLength(NotificationInbox.maxEntries));
      expect(list.first.id, '${NotificationInbox.maxEntries + 4}');
      expect(list.last.id, '5');
    });
  });

  group('NotificationInbox.unreadIn', () {
    test('counts only unread rows', () {
      expect(
        NotificationInbox.unreadIn([
          item(id: '1', read: false),
          item(id: '2', read: true),
          item(id: '3', read: false),
        ]),
        2,
      );
    });
  });

  group('NotificationItem json', () {
    test('round-trips', () {
      final original = item(
        id: 'os_abc',
        kind: NotificationItem.kindPush,
        title: 'You won',
        body: 'Claim your gift',
        open: 'shop',
        read: true,
      );
      final restored = NotificationItem.fromJson(original.toJson());
      expect(restored.id, original.id);
      expect(restored.kind, original.kind);
      expect(restored.title, original.title);
      expect(restored.body, original.body);
      expect(restored.open, original.open);
      expect(restored.read, original.read);
      expect(restored.receivedAt, original.receivedAt);
    });

    test('unknown kind falls back to reminder', () {
      final restored = NotificationItem.fromJson({
        'id': 'x',
        'kind': 'nope',
        'title': 't',
        'body': 'b',
        'received_at': '2026-09-06T19:00:00.000',
      });
      expect(restored.kind, NotificationItem.kindReminder);
      expect(restored.read, isFalse);
    });
  });

  group('NotificationInbox Hive', () {
    late Directory tempDir;

    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      tempDir = await Directory.systemTemp.createTemp('qb_notif_');
      Hive.init(tempDir.path);
      await HiveService.initialize();
    });

    tearDownAll(() async {
      await Hive.close();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    setUp(() async {
      NotificationInbox.instance.debugReset();
      await HiveService.clearNotificationHistory();
    });

    test('add persists and reload restores', () async {
      await NotificationInbox.instance.add(item(
        id: 'os_1',
        title: 'Live',
        body: 'Play now',
        open: 'daily_quiz',
      ));
      expect(NotificationInbox.instance.unreadCount, 1);

      NotificationInbox.instance.debugReset();
      NotificationInbox.instance.reload();
      expect(NotificationInbox.instance.items, hasLength(1));
      expect(NotificationInbox.instance.items.first.open, 'daily_quiz');
    });

    test('add skips blank title and body', () async {
      await NotificationInbox.instance
          .add(item(id: 'blank', title: '  ', body: ''));
      expect(NotificationInbox.instance.items, isEmpty);
    });

    test('markAllRead then clear', () async {
      await NotificationInbox.instance.add(item(id: '1'));
      await NotificationInbox.instance.add(item(id: '2'));
      expect(NotificationInbox.instance.unreadCount, 2);
      await NotificationInbox.instance.markAllRead();
      expect(NotificationInbox.instance.unreadCount, 0);
      await NotificationInbox.instance.clear();
      expect(NotificationInbox.instance.isEmpty, isTrue);
    });
  });
}
