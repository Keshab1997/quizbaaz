/// One row in the on-device notification inbox.
///
/// Device-local only (Hive). Not mirrored to Firestore — a reinstall starts
/// empty, which is the honest empty state.
class NotificationItem {
  static const kindReminder = 'reminder';
  static const kindPush = 'push';

  final String id;
  final String kind;
  final String title;
  final String body;
  final String? open;
  final DateTime receivedAt;
  final bool read;

  const NotificationItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    this.open,
    required this.receivedAt,
    this.read = false,
  });

  bool get isReminder => kind == kindReminder;

  NotificationItem copyWith({
    String? title,
    String? body,
    String? open,
    bool? read,
  }) {
    return NotificationItem(
      id: id,
      kind: kind,
      title: title ?? this.title,
      body: body ?? this.body,
      open: open ?? this.open,
      receivedAt: receivedAt,
      read: read ?? this.read,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'title': title,
        'body': body,
        'open': open,
        'received_at': receivedAt.toIso8601String(),
        'read': read,
      };

  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    return NotificationItem(
      id: json['id']?.toString() ?? '',
      kind: json['kind']?.toString() == kindPush ? kindPush : kindReminder,
      title: json['title']?.toString() ?? '',
      body: json['body']?.toString() ?? '',
      open: json['open']?.toString(),
      receivedAt: DateTime.tryParse(json['received_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      read: json['read'] == true,
    );
  }
}
