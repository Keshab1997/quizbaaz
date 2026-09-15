import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Firestore-backed online presence system.
///
/// ## Collection
///
/// ```text
/// online_users/{uid}  — presence doc
/// {
///   name: String,
///   avatar: String,
///   avatar_url: String?,
///   level: int,
///   is_available: bool,     // false when in a match or busy
///   current_activity: String, // 'idle', 'battling', 'quiz', etc.
///   last_seen: int (ms),
///   updated_at: Timestamp
/// }
/// ```
///
/// ## How it works
///
/// 1. When app opens (or comes to foreground) → `goOnline()` writes presence.
/// 2. A periodic heartbeat (every 20s) refreshes `last_seen`.
/// 3. When app closes / goes background → `goOffline()` deletes the doc.
/// 4. Entries older than 60s without heartbeat are considered stale and
///    cleaned up on next query.
/// 5. Firestore real-time listener provides live updates of who's online.
class OnlinePresenceService {
  OnlinePresenceService({FirebaseFirestore? firestore})
      : _firestoreOverride = firestore;

  final FirebaseFirestore? _firestoreOverride;

  /// Resolved lazily so constructing the service never touches Firebase.
  FirebaseFirestore get _db =>
      _firestoreOverride ?? FirebaseFirestore.instance;

  static const String collection = 'online_users';
  static const Duration staleAfter = Duration(seconds: 60);
  static const Duration heartbeatInterval = Duration(seconds: 20);

  String? _myUid;
  bool _isOnline = false;

  // ------------------------------------------- Go Online / Offline --------

  /// Marks the user as online. Call when app starts or resumes.
  Future<void> goOnline({
    required String uid,
    required String name,
    required String avatar,
    String? avatarUrl,
    int level = 1,
    bool isAvailable = true,
    String activity = 'idle',
  }) async {
    _myUid = uid;
    _isOnline = true;
    try {
      await _db.collection(collection).doc(uid).set({
        'name': name,
        'avatar': avatar,
        'avatar_url': avatarUrl ?? '',
        'level': level,
        'is_available': isAvailable,
        'current_activity': activity,
        'last_seen': DateTime.now().millisecondsSinceEpoch,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('OnlinePresenceService: goOnline failed – $e');
    }
  }

  /// Removes the user from the online list. Call when app closes or pauses.
  Future<void> goOffline() async {
    if (_myUid == null) return;
    _isOnline = false;
    try {
      await _db.collection(collection).doc(_myUid!).delete();
    } catch (e) {
      debugPrint('OnlinePresenceService: goOffline failed – $e');
    }
    _myUid = null;
  }

  /// Updates the heartbeat timestamp. Call every 20s.
  Future<void> heartbeat({bool isAvailable = true, String activity = 'idle'}) async {
    if (_myUid == null || !_isOnline) return;
    try {
      await _db.collection(collection).doc(_myUid!).update({
        'last_seen': DateTime.now().millisecondsSinceEpoch,
        'is_available': isAvailable,
        'current_activity': activity,
        'updated_at': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('OnlinePresenceService: heartbeat failed – $e');
    }
  }

  /// Updates availability status (e.g., when entering a battle).
  Future<void> setAvailability({
    required bool isAvailable,
    String activity = 'idle',
  }) async {
    if (_myUid == null) return;
    try {
      await _db.collection(collection).doc(_myUid!).update({
        'is_available': isAvailable,
        'current_activity': activity,
        'last_seen': DateTime.now().millisecondsSinceEpoch,
        'updated_at': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('OnlinePresenceService: setAvailability failed – $e');
    }
  }

  // ----------------------------------------- Query Online Users -----------

  /// Returns a real-time stream of online users (excluding stale entries).
  /// Only shows users who are available (not in a battle/quiz).
  Stream<List<OnlineUser>> watchOnlineUsers({String? excludeUid}) {
    final cutoff = DateTime.now()
        .subtract(staleAfter)
        .millisecondsSinceEpoch;

    return _db
        .collection(collection)
        .where('last_seen', isGreaterThan: cutoff)
        .where('is_available', isEqualTo: true)
        .orderBy('last_seen', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .where((doc) => doc.id != excludeUid)
          .map((doc) => OnlineUser.fromDoc(doc))
          .toList();
    }).handleError((e) {
      debugPrint('OnlinePresenceService: watchOnlineUsers – $e');
      return <OnlineUser>[];
    });
  }

  /// One-shot fetch of currently online users.
  Future<List<OnlineUser>> getOnlineUsers({String? excludeUid}) async {
    try {
      final cutoff = DateTime.now()
          .subtract(staleAfter)
          .millisecondsSinceEpoch;

      final snapshot = await _db
          .collection(collection)
          .where('last_seen', isGreaterThan: cutoff)
          .where('is_available', isEqualTo: true)
          .orderBy('last_seen', descending: true)
          .limit(50)
          .get();

      return snapshot.docs
          .where((doc) => doc.id != excludeUid)
          .map((doc) => OnlineUser.fromDoc(doc))
          .toList();
    } catch (e) {
      debugPrint('OnlinePresenceService: getOnlineUsers failed – $e');
      return [];
    }
  }

  /// Check if a specific user is online.
  Future<bool> isUserOnline(String uid) async {
    try {
      final doc = await _db.collection(collection).doc(uid).get();
      if (!doc.exists) return false;
      final data = doc.data()!;
      final lastSeen = (data['last_seen'] as num?)?.toInt() ?? 0;
      final cutoff = DateTime.now()
          .subtract(staleAfter)
          .millisecondsSinceEpoch;
      return lastSeen > cutoff;
    } catch (e) {
      return false;
    }
  }

  /// Clean up stale entries (called periodically or on app start).
  Future<void> cleanupStaleEntries() async {
    try {
      final cutoff = DateTime.now()
          .subtract(staleAfter * 3) // 3x stale threshold
          .millisecondsSinceEpoch;

      final snapshot = await _db
          .collection(collection)
          .where('last_seen', isLessThan: cutoff)
          .get();

      final batch = _db.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      if (snapshot.docs.isNotEmpty) {
        await batch.commit();
      }
    } catch (e) {
      debugPrint('OnlinePresenceService: cleanup failed – $e');
    }
  }

  bool get isOnline => _isOnline;
}

/// Model for an online user.
class OnlineUser {
  final String uid;
  final String name;
  final String avatar;
  final String? avatarUrl;
  final int level;
  final bool isAvailable;
  final String currentActivity;
  final int lastSeenMs;

  const OnlineUser({
    required this.uid,
    required this.name,
    required this.avatar,
    this.avatarUrl,
    this.level = 1,
    this.isAvailable = true,
    this.currentActivity = 'idle',
    this.lastSeenMs = 0,
  });

  /// How long ago this user was seen.
  Duration get seenAgo {
    final now = DateTime.now().millisecondsSinceEpoch;
    return Duration(milliseconds: now - lastSeenMs);
  }

  String get activityLabel {
    switch (currentActivity) {
      case 'idle':
        return 'Idle';
      case 'battling':
        return 'In Battle';
      case 'quiz':
        return 'In Quiz';
      case 'shop':
        return 'Browsing Shop';
      default:
        return currentActivity;
    }
  }

  /// Best avatar URL: remote > local.
  String get effectiveAvatar => (avatarUrl != null && avatarUrl!.isNotEmpty)
      ? avatarUrl!
      : avatar;

  factory OnlineUser.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return OnlineUser(
      uid: doc.id,
      name: data['name']?.toString() ?? 'Player',
      avatar: data['avatar']?.toString() ?? '',
      avatarUrl: data['avatar_url']?.toString(),
      level: (data['level'] as num?)?.toInt() ?? 1,
      isAvailable: data['is_available'] as bool? ?? true,
      currentActivity: data['current_activity']?.toString() ?? 'idle',
      lastSeenMs: (data['last_seen'] as num?)?.toInt() ?? 0,
    );
  }

  factory OnlineUser.fromJson(String uid, Map<String, dynamic> json) {
    return OnlineUser(
      uid: uid,
      name: json['name']?.toString() ?? 'Player',
      avatar: json['avatar']?.toString() ?? '',
      avatarUrl: json['avatar_url']?.toString(),
      level: (json['level'] as num?)?.toInt() ?? 1,
      isAvailable: json['is_available'] as bool? ?? true,
      currentActivity: json['current_activity']?.toString() ?? 'idle',
      lastSeenMs: (json['last_seen'] as num?)?.toInt() ?? 0,
    );
  }
}
