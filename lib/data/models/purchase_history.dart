import '../../l10n/app_strings.dart';

/// Represents a single shop purchase stored in the history.
///
/// Every purchase creates one of these records so the player can review
/// their spending on the Purchase History screen.
class PurchaseHistory {
  final String id;
  final String userId;
  final String itemId;
  final String itemName;
  final String
      category; // 'power_ups', 'shields', 'boosters', 'avatars', 'badges', 'effects', 'packs'
  final int quantity;
  final int cost;
  final String currency; // 'coins' or 'gems'
  final DateTime purchasedAt;

  PurchaseHistory({
    required this.id,
    required this.userId,
    required this.itemId,
    required this.itemName,
    this.category = 'power_ups',
    required this.quantity,
    required this.cost,
    required this.currency,
    required this.purchasedAt,
  });

  String get costLabel => '$cost $currency';

  /// Get category display name with emoji.
  String get categoryDisplayName {
    switch (category) {
      case 'power_ups':
        return S.shopCatPowerUps;
      case 'shields':
        return S.shopCatShields;
      case 'boosters':
        return S.shopCatBoosters;
      case 'avatars':
        return S.shopCatAvatars;
      case 'badges':
        return S.shopCatBadges;
      case 'effects':
        return S.shopCatEffects;
      case 'packs':
        return S.shopCatPacks;
      default:
        return category;
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'item_id': itemId,
        'item_name': itemName,
        'category': category,
        'quantity': quantity,
        'cost': cost,
        'currency': currency,
        'purchased_at': purchasedAt.toIso8601String(),
      };

  factory PurchaseHistory.fromJson(Map<String, dynamic> json) {
    return PurchaseHistory(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      itemId: json['item_id'] as String? ?? '',
      itemName: json['item_name'] as String? ?? '',
      category: json['category'] as String? ?? 'power_ups',
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      cost: (json['cost'] as num?)?.toInt() ?? 0,
      currency: json['currency'] as String? ?? 'coins',
      purchasedAt: DateTime.tryParse(json['purchased_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}
