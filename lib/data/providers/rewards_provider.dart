import 'package:flutter/foundation.dart';

import '../models/gift_claim.dart';
import '../services/firestore_service.dart';
import '../services/hive_service.dart';
import '../services/sync_service.dart';

/// Manages the player's won prizes and their claim/delivery state.
///
/// Gifts are **never** invented locally: they are dispatched by the backend
/// into `users/{uid}/gifts` and cached in Hive. With no prizes won yet the
/// screen shows its empty state.
class RewardsProvider extends ChangeNotifier {
  static const _cacheKey = 'gift_claims';

  List<GiftClaim> _gifts = const [];
  bool _isLoading = false;
  String _userId = '';

  List<GiftClaim> get gifts => List.unmodifiable(_gifts);
  bool get isLoading => _isLoading;
  bool get hasGifts => _gifts.isNotEmpty;

  int get unclaimedCount => _gifts.where((g) => !g.isClaimed).length;

  /// Loads gifts from Hive first, then refreshes from Firestore.
  Future<void> initialize({String userId = ''}) async {
    if (userId.isNotEmpty) _userId = userId;

    _gifts = _loadFromHive();
    notifyListeners();

    await refresh();
  }

  /// Pulls the gift list from Firestore into the Hive cache.
  Future<void> refresh() async {
    if (_userId.isEmpty || !SyncService.isOnline) return;

    _isLoading = true;
    notifyListeners();

    try {
      final rows = await _fetchRemote();
      if (rows.isNotEmpty) {
        _gifts = rows.map(GiftClaim.fromJson).toList();
        await HiveService.cachePut(_cacheKey, rows);
      }
    } catch (e) {
      debugPrint('RewardsProvider: refresh failed – $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  List<GiftClaim> _loadFromHive() {
    try {
      return HiveService.cacheGetList(
        _cacheKey,
      ).map(GiftClaim.fromJson).toList();
    } catch (e) {
      debugPrint('RewardsProvider: bad cached gifts – $e');
      return const [];
    }
  }

  Future<List<Map<String, dynamic>>> _fetchRemote() =>
      FirestoreService.getGifts(_userId);

  /// Claims a physical gift with the supplied delivery address.
  bool claimPhysicalGift(
    String id, {
    required String name,
    required String phone,
    required String address,
    required String pincode,
  }) {
    final gift = _find(id);
    if (gift == null || gift.isClaimed) return false;

    gift.status = ClaimStatus.processing;
    gift.addressName = name;
    gift.addressPhone = phone;
    gift.addressLine = address;
    gift.addressPincode = pincode;
    notifyListeners();
    _persist(gift);
    return true;
  }

  /// Redeems a digital gift code (marks it claimed).
  bool redeemDigitalGift(String id) {
    final gift = _find(id);
    if (gift == null || gift.isClaimed) return false;

    gift.status = ClaimStatus.delivered; // digital = instant delivery
    notifyListeners();
    _persist(gift);
    return true;
  }

  GiftClaim? _find(String id) {
    for (final g in _gifts) {
      if (g.id == id) return g;
    }
    return null;
  }

  /// Hive first, Firestore second (queued when offline).
  Future<void> _persist(GiftClaim changed) async {
    await HiveService.cachePut(
      _cacheKey,
      _gifts.map((g) => g.toJson()).toList(),
    );
    if (_userId.isNotEmpty) {
      await SyncService.pushGift(_userId, changed.toJson());
    }
  }
}
