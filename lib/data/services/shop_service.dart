import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'hive_service.dart';

/// Firestore service for managing shop items and avatars
///
/// Collection Structure:
/// shop_items/{item_id} - Shop items
/// avatars/{avatar_id} - Avatars
class ShopService {
  static const _shopItems = 'shop_items';
  static const _avatars = 'avatars';

  static FirebaseFirestore get _db => FirebaseFirestore.instance;
  static bool get isReady => Firebase.apps.isNotEmpty;
  static String? lastError;

  static void _clearError() => lastError = null;

  static void _setError(String scope, Object error) {
    lastError = '$scope: $error';
    debugPrint('ShopService: $scope error - $error');
  }

  static Future<void> _logAdminAction({
    required String action,
    required String entity,
    required String entityId,
    Map<String, dynamic>? details,
  }) async {
    if (!isReady) return;
    try {
      final actor = FirebaseAuth.instance.currentUser;
      await _db.collection('admin_audit_logs').add({
        'action': action,
        'entity': entity,
        'entity_id': entityId,
        'actor_uid': actor?.uid,
        'actor_email': actor?.email,
        'details': details ?? const <String, dynamic>{},
        'created_at': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('ShopService: audit log error - $e');
    }
  }

  static bool _isAllowedShopCategory(String category) => const {
    'power_ups',
    'shields',
    'boosters',
    'avatars',
    'badges',
    'effects',
    'packs',
  }.contains(category);

  static bool _isAllowedAvatarCategory(String category) =>
      const {'male', 'female', 'premium'}.contains(category);

  static Future<bool> _hasDuplicateName({
    required String collection,
    required String name,
    required String currentId,
  }) async {
    final cleanName = name.trim().toLowerCase();
    if (cleanName.isEmpty) return false;
    final snapshot =
        await _db
            .collection(collection)
            .where('name_key', isEqualTo: cleanName)
            .limit(5)
            .get();
    return snapshot.docs.any(
      (doc) => doc.id != currentId && doc.data()['is_active'] == true,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 👥 USERS
  // ═══════════════════════════════════════════════════════════════════════

  /// Get users from Firestore for the admin panel.
  static Future<List<Map<String, dynamic>>> getUsers({
    bool guestsOnly = false,
  }) async {
    if (!isReady) {
      lastError = 'Firebase is not ready or offline';
      return [];
    }
    try {
      Query<Map<String, dynamic>> query = _db.collection('users');
      if (guestsOnly) {
        query = query.where('is_guest', isEqualTo: true);
      }
      final snapshot = await query.limit(200).get();
      final users =
          snapshot.docs.map((doc) => {...doc.data(), 'id': doc.id}).toList();
      users.sort((a, b) {
        final aName =
            (a['username'] ?? a['full_name'] ?? '').toString().toLowerCase();
        final bName =
            (b['username'] ?? b['full_name'] ?? '').toString().toLowerCase();
        return aName.compareTo(bName);
      });
      _clearError();
      return users;
    } catch (e) {
      _setError('getUsers', e);
      return [];
    }
  }

  /// Update admin-editable user fields.
  static Future<bool> updateUser(
    String userId,
    Map<String, dynamic> fields,
  ) async {
    if (!isReady || userId.isEmpty) {
      lastError = 'Firebase is not ready or user id is empty';
      return false;
    }
    try {
      await _db.collection('users').doc(userId).set({
        ...fields,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await _logAdminAction(
        action: 'update',
        entity: 'user',
        entityId: userId,
        details: fields,
      );
      _clearError();
      return true;
    } catch (e) {
      _setError('updateUser', e);
      return false;
    }
  }

  /// Delete a user document from Firestore.
  static Future<bool> deleteUser(String userId) async {
    if (!isReady || userId.isEmpty) {
      lastError = 'Firebase is not ready or user id is empty';
      return false;
    }
    try {
      await _db.collection('users').doc(userId).delete();
      await _logAdminAction(action: 'delete', entity: 'user', entityId: userId);
      _clearError();
      return true;
    } catch (e) {
      _setError('deleteUser', e);
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 🛒 SHOP ITEMS
  // ═══════════════════════════════════════════════════════════════════════

  /// Save a shop item to Firestore
  static Future<bool> saveShopItem(Map<String, dynamic> item) async {
    if (!isReady) {
      lastError = 'Firebase is not ready or offline';
      return false;
    }
    try {
      final id =
          item['id'] as String? ??
          DateTime.now().millisecondsSinceEpoch.toString();
      final name = (item['name'] ?? '').toString().trim();
      final category = (item['category'] ?? '').toString();
      final price = (item['price'] as num?)?.toInt() ?? 0;
      if (name.isEmpty) {
        lastError = 'Item name is required';
        return false;
      }
      if (!_isAllowedShopCategory(category)) {
        lastError = 'Invalid shop category';
        return false;
      }
      if (price < 0) {
        lastError = 'Price cannot be negative';
        return false;
      }
      if (await _hasDuplicateName(
        collection: _shopItems,
        name: name,
        currentId: id,
      )) {
        lastError = 'Duplicate item name: $name';
        return false;
      }
      await _db.collection(_shopItems).doc(id).set({
        ...item,
        'name': name,
        'name_key': name.toLowerCase(),
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // If category is avatars, mirror to avatars collection as well
      if (category == 'avatars' || category == 'avatar') {
        final imageUrl =
            (item['icon_url'] ?? item['image_url'] ?? '').toString();
        if (imageUrl.isNotEmpty) {
          await _db.collection(_avatars).doc(id).set({
            'id': id,
            'name': name,
            'category': 'premium',
            'image_url': imageUrl,
            'is_premium': item['is_cosmetic'] == true || price > 0,
            'price': price,
            'currency': item['currency'] ?? 'gems',
            'is_active': item['is_active'] ?? true,
            'name_key': name.toLowerCase(),
            'updated_at': FieldValue.serverTimestamp(),
            'created_at':
                item['created_at'] ?? DateTime.now().toIso8601String(),
          }, SetOptions(merge: true));
        }
        unawaited(refreshAvatarCache());
      }

      await _logAdminAction(
        action: 'save',
        entity: 'shop_item',
        entityId: id,
        details: {'name': name, 'category': category},
      );
      _clearError();
      return true;
    } catch (e) {
      _setError('saveShopItem', e);
      return false;
    }
  }

  /// Get all shop items from Firestore
  static Future<List<Map<String, dynamic>>> getShopItems() async {
    if (!isReady) {
      lastError = 'Firebase is not ready or offline';
      return [];
    }
    try {
      final snapshot =
          await _db
              .collection(_shopItems)
              .where('is_active', isEqualTo: true)
              .get();
      final items =
          snapshot.docs.map((doc) => {...doc.data(), 'id': doc.id}).toList();

      // Also merge active avatars from the avatars collection
      try {
        final avatarsSnapshot =
            await _db
                .collection(_avatars)
                .where('is_active', isEqualTo: true)
                .get();
        final existingIds =
            items.map((e) => (e['id'] ?? '').toString()).toSet();
        final existingUrls =
            items
                .map((e) => (e['icon_url'] ?? e['image_url'] ?? '').toString())
                .toSet();

        for (final doc in avatarsSnapshot.docs) {
          final data = doc.data();
          final id = doc.id;
          final imageUrl =
              (data['image_url'] ?? data['avatar_url'] ?? '').toString();
          if (!existingIds.contains(id) &&
              !existingUrls.contains(imageUrl) &&
              imageUrl.isNotEmpty) {
            final isPremium =
                data['is_premium'] == true ||
                data['category'] == 'premium' ||
                ((data['price'] as num?) ?? 0) > 0;
            items.add({
              'id': id,
              'name': (data['name'] ?? 'Avatar').toString(),
              'description': 'Unlock ${(data['name'] ?? 'Avatar')} Avatar',
              'category': 'avatars',
              'price': (data['price'] as num?)?.toInt() ?? 0,
              'currency': 'gems',
              'quantity': 1,
              'is_cosmetic': isPremium,
              'icon_url': imageUrl,
              'is_active': true,
              'created_at':
                  data['created_at'] ?? DateTime.now().toIso8601String(),
            });
          }
        }
      } catch (e) {
        debugPrint('ShopService: merge avatars into shop items skipped - $e');
      }

      items.sort(
        (a, b) => (b['created_at'] ?? '').toString().compareTo(
          (a['created_at'] ?? '').toString(),
        ),
      );
      _clearError();
      return items;
    } catch (e) {
      _setError('getShopItems', e);
      return [];
    }
  }

  /// Delete a shop item (soft delete - set is_active to false)
  static Future<bool> deleteShopItem(String itemId) async {
    if (!isReady) {
      lastError = 'Firebase is not ready or offline';
      return false;
    }
    try {
      await _db.collection(_shopItems).doc(itemId).update({
        'is_active': false,
        'updated_at': FieldValue.serverTimestamp(),
      });
      await _logAdminAction(
        action: 'delete',
        entity: 'shop_item',
        entityId: itemId,
      );
      _clearError();
      return true;
    } catch (e) {
      _setError('deleteShopItem', e);
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 🎨 AVATARS
  // ═══════════════════════════════════════════════════════════════════════

  /// Save an avatar to Firestore
  static Future<bool> saveAvatar(Map<String, dynamic> avatar) async {
    if (!isReady) {
      lastError = 'Firebase is not ready or offline';
      return false;
    }
    try {
      final id =
          avatar['id'] as String? ??
          DateTime.now().millisecondsSinceEpoch.toString();
      final name = (avatar['name'] ?? '').toString().trim();
      final category = (avatar['category'] ?? '').toString();
      final imageUrl = (avatar['image_url'] ?? '').toString().trim();
      final price = (avatar['price'] as num?)?.toInt() ?? 0;
      if (name.isEmpty) {
        lastError = 'Avatar name is required';
        return false;
      }
      if (imageUrl.isEmpty) {
        lastError = 'Avatar image is required';
        return false;
      }
      if (!_isAllowedAvatarCategory(category)) {
        lastError = 'Invalid avatar category';
        return false;
      }
      if (price < 0) {
        lastError = 'Price cannot be negative';
        return false;
      }
      if (await _hasDuplicateName(
        collection: _avatars,
        name: name,
        currentId: id,
      )) {
        lastError = 'Duplicate avatar name: $name';
        return false;
      }
      await _db.collection(_avatars).doc(id).set({
        ...avatar,
        'name': name,
        'image_url': imageUrl,
        'name_key': name.toLowerCase(),
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Also mirror to shop_items if premium
      if (avatar['is_premium'] == true || category == 'premium' || price > 0) {
        await _db.collection(_shopItems).doc(id).set({
          'id': id,
          'name': name,
          'description': 'Unlock $name Avatar',
          'category': 'avatars',
          'price': price,
          'currency': avatar['currency'] ?? 'gems',
          'quantity': 1,
          'is_cosmetic': true,
          'icon_url': imageUrl,
          'is_active': avatar['is_active'] ?? true,
          'name_key': name.toLowerCase(),
          'updated_at': FieldValue.serverTimestamp(),
          'created_at':
              avatar['created_at'] ?? DateTime.now().toIso8601String(),
        }, SetOptions(merge: true));
      }

      await _logAdminAction(
        action: 'save',
        entity: 'avatar',
        entityId: id,
        details: {'name': name, 'category': category},
      );
      _clearError();
      // Keep the local avatar cache in sync so users see the change quickly.
      unawaited(refreshAvatarCache());
      return true;
    } catch (e) {
      _setError('saveAvatar', e);
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // 🧊 CLOUD AVATAR CACHE (Hive TTL cache — cuts Firestore reads hard)
  //
  // Strategy: cache-first / stale-while-revalidate.
  //  * Fresh cache (< TTL)  → served instantly, zero Firestore reads.
  //  * Stale cache (> TTL)  → served instantly, refreshed in background.
  //  * No cache / offline-fail → fallback to whatever is cached.
  // Admin screens pass `forceRefresh: true` to always hit Firestore.
  // ─────────────────────────────────────────────────────────────────────
  static const _avatarsCacheKey = 'cloud_avatars_v1';
  static const _avatarsCacheTtl = Duration(hours: 6);

  /// Returns all active cloud avatars, served from the local Hive cache
  /// whenever possible so Firestore is not called on every screen open.
  static Future<List<Map<String, dynamic>>> getAvatars({
    String? category,
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      // 1) Fresh cache → instant, no network at all.
      final fresh = HiveService.cacheGetList(
        _avatarsCacheKey,
        maxAge: _avatarsCacheTtl,
      );
      if (fresh.isNotEmpty) return _filterAndSortAvatars(fresh, category);

      // 2) Stale cache → still serve instantly, refresh quietly in background.
      final stale = HiveService.cacheGetList(_avatarsCacheKey);
      if (stale.isNotEmpty) {
        unawaited(refreshAvatarCache());
        return _filterAndSortAvatars(stale, category);
      }
    }

    // 3) No cache at all → fetch from Firestore (and cache the result).
    return _fetchAndCacheAvatars(category: category);
  }

  /// Refetches avatars from Firestore into the local cache. Called in the
  /// background when the cache is stale, and after every admin mutation.
  static Future<List<Map<String, dynamic>>> refreshAvatarCache() =>
      _fetchAndCacheAvatars();

  static Future<List<Map<String, dynamic>>> _fetchAndCacheAvatars({
    String? category,
  }) async {
    if (!isReady) {
      lastError = 'Firebase is not ready or offline';
      // Offline with no cache: return whatever stale data we may have.
      return _filterAndSortAvatars(
        HiveService.cacheGetList(_avatarsCacheKey),
        category,
      );
    }
    try {
      final snapshot =
          await _db
              .collection(_avatars)
              .where('is_active', isEqualTo: true)
              .get();
      final avatars =
          snapshot.docs
              .map((doc) => {..._sanitizeForCache(doc.data()), 'id': doc.id})
              .toList();

      // Also merge items from shop_items collection where category is avatars
      try {
        final shopSnapshot =
            await _db
                .collection(_shopItems)
                .where('is_active', isEqualTo: true)
                .get();
        final existingIds =
            avatars.map((e) => (e['id'] ?? '').toString()).toSet();
        final existingUrls =
            avatars
                .map(
                  (e) => (e['image_url'] ?? e['avatar_url'] ?? '').toString(),
                )
                .toSet();

        for (final doc in shopSnapshot.docs) {
          final data = doc.data();
          final id = doc.id;
          final itemCategory =
              (data['category'] ?? '').toString().toLowerCase();
          final imageUrl =
              (data['icon_url'] ?? data['image_url'] ?? '').toString();

          if ((itemCategory == 'avatars' || itemCategory == 'avatar') &&
              !existingIds.contains(id) &&
              !existingUrls.contains(imageUrl) &&
              imageUrl.isNotEmpty) {
            final isPremium =
                data['is_cosmetic'] == true ||
                ((data['price'] as num?) ?? 0) > 0;
            avatars.add({
              ..._sanitizeForCache(data),
              'id': id,
              'name': (data['name'] ?? 'Avatar').toString(),
              'category': isPremium ? 'premium' : 'male',
              'image_url': imageUrl,
              'is_premium': isPremium,
              'price': (data['price'] as num?)?.toInt() ?? 0,
              'currency': data['currency'] ?? 'gems',
              'is_active': true,
              'created_at':
                  data['created_at'] ?? DateTime.now().toIso8601String(),
            });
          }
        }
      } catch (e) {
        debugPrint('ShopService: merge shop avatars error - $e');
      }

      // Cache the full unfiltered list so every category is served locally.
      if (isReady) {
        try {
          await HiveService.cachePut(_avatarsCacheKey, avatars);
        } catch (e) {
          debugPrint('ShopService: avatar cache write skipped - $e');
        }
      }
      _clearError();
      return _filterAndSortAvatars(avatars, category);
    } catch (e) {
      _setError('getAvatars', e);
      // Network failed → degrade gracefully to stale cache instead of an
      // empty screen.
      return _filterAndSortAvatars(
        HiveService.cacheGetList(_avatarsCacheKey),
        category,
      );
    }
  }

  /// Firestore `Timestamp`/`DateTime` values are not JSON-encodable, so they
  /// are normalised to ISO-8601 strings before the list is written to the
  /// Hive cache (otherwise `jsonEncode` inside HiveService would throw and
  /// the cache would silently never populate).
  static Map<String, dynamic> _sanitizeForCache(Map<String, dynamic> doc) {
    return doc.map((key, value) {
      if (value is Timestamp) {
        return MapEntry(key, value.toDate().toIso8601String());
      }
      if (value is DateTime) {
        return MapEntry(key, value.toIso8601String());
      }
      return MapEntry(key, value);
    });
  }

  static List<Map<String, dynamic>> _filterAndSortAvatars(
    List<Map<String, dynamic>> avatars,
    String? category,
  ) {
    var list = [...avatars];
    if (category != null && category != 'all') {
      list =
          list
              .where((a) => (a['category'] ?? '').toString() == category)
              .toList();
    }
    list.sort(
      (a, b) => (b['created_at'] ?? '').toString().compareTo(
        (a['created_at'] ?? '').toString(),
      ),
    );
    return list;
  }

  /// Delete an avatar (soft delete)
  static Future<bool> deleteAvatar(String avatarId) async {
    if (!isReady) {
      lastError = 'Firebase is not ready or offline';
      return false;
    }
    try {
      await _db.collection(_avatars).doc(avatarId).update({
        'is_active': false,
        'updated_at': FieldValue.serverTimestamp(),
      });
      await _logAdminAction(
        action: 'delete',
        entity: 'avatar',
        entityId: avatarId,
      );
      _clearError();
      // Keep the local avatar cache in sync after a delete.
      unawaited(refreshAvatarCache());
      return true;
    } catch (e) {
      _setError('deleteAvatar', e);
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 📊 ADMIN STATS
  // ═══════════════════════════════════════════════════════════════════════

  /// Get admin dashboard stats
  static Future<Map<String, int>> getAdminStats() async {
    if (!isReady) {
      lastError = 'Firebase is not ready or offline';
      return {};
    }
    final stats = <String, int>{};
    try {
      // Total users
      final users = await _db.collection('users').count().get();
      stats['total_users'] = users.count ?? 0;

      // Guest users
      final guests =
          await _db
              .collection('users')
              .where('is_guest', isEqualTo: true)
              .count()
              .get();
      stats['guest_users'] = guests.count ?? 0;

      // Today's players
      final today = DateTime.now();
      final dateKey =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      final players =
          await _db
              .collection('leaderboard')
              .doc(dateKey)
              .collection('scores')
              .count()
              .get();
      stats['players_today'] = players.count ?? 0;

      // Shop items
      final items =
          await _db
              .collection(_shopItems)
              .where('is_active', isEqualTo: true)
              .count()
              .get();
      stats['shop_items'] = items.count ?? 0;

      // Avatars
      final avatars =
          await _db
              .collection(_avatars)
              .where('is_active', isEqualTo: true)
              .count()
              .get();
      stats['avatars'] = avatars.count ?? 0;

      _clearError();
    } catch (e) {
      _setError('getAdminStats', e);
    }
    return stats;
  }
}
