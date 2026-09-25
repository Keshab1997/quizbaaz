import '../../l10n/app_strings.dart';

/// Currency used to buy a shop item.
enum ShopCurrency { coins, gems }

/// A purchasable item in the Power-Up Shop.
///
/// - Consumables (lifelines, shields) grant [quantity] units per purchase and
///   can be bought repeatedly.
/// - Cosmetics ([isCosmetic] = true) are unlocked once and can't be bought again.
class ShopItem {
  final String id;
  final String name;
  final String description;
  final int cost;
  final ShopCurrency currency;

  /// How many units one purchase grants (e.g. 3 x 50-50 lifelines).
  final int quantity;

  /// Cosmetics are one-time unlocks (owned = 1) instead of stackable items.
  final bool isCosmetic;

  /// Category for grouping in the shop UI.
  final String category;

  const ShopItem({
    required this.id,
    required this.name,
    required this.description,
    required this.cost,
    required this.currency,
    this.quantity = 1,
    this.isCosmetic = false,
    this.category = 'power_ups',
  });

  String get currencyLabel => currency == ShopCurrency.coins ? S.coins : S.gems;

  bool get costsCoins => currency == ShopCurrency.coins;
}

/// Central, stable ids for every item sold in the shop.
/// Used to key the user's inventory so purchases survive restarts.
class ShopItemIds {
  // Power-ups & Lifelines
  static const String fiftyFifty = 'fifty_fifty';
  static const String freezeTime = 'freeze_time';
  static const String skipQuestion = 'skip_question';
  static const String doublePoints = 'double_points';
  static const String extraLife = 'extra_life';
  static const String hintReveal = 'hint_reveal';
  static const String audiencePoll = 'audience_poll';

  // Shields & Protection
  static const String streakShield = 'streak_shield';
  static const String scoreShield = 'score_shield';

  // Boosters
  static const String coinBooster = 'coin_booster';
  static const String xpBooster = 'xp_booster';

  // Cosmetics - Avatars
  static const String vipAvatar = 'vip_avatar';
  static const String goldenAvatar = 'golden_avatar';
  static const String neonAvatar = 'neon_avatar';
  static const String royalAvatar = 'royal_avatar';

  // Cosmetics - Badges
  static const String championBadge = 'champion_badge';
  static const String scholarBadge = 'scholar_badge';
  static const String legendBadge = 'legend_badge';

  // Cosmetics - Name Effects
  static const String fireName = 'fire_name';
  static const String rainbowName = 'rainbow_name';
  static const String goldName = 'gold_name';

  // Special Packs
  static const String starterPack = 'starter_pack';
  static const String megaPack = 'mega_pack';
  static const String legendPack = 'legend_pack';
}

/// The full shop catalogue. Add new items here and they automatically appear
/// in the Shop screen.
class ShopCatalog {
  static const List<ShopItem> items = [
    // ═══════════════════════════════════════════════════════════════════════
    // 🎮 POWER-UPS & LIFELINES
    // Daily Quiz max = 600 coins/day → cheap items ~1-2 days grind
    // ═══════════════════════════════════════════════════════════════════════
    ShopItem(
      id: ShopItemIds.fiftyFifty,
      name: '50-50 Lifeline',
      description: 'Removes 2 wrong options during a quiz',
      cost: 800,          // ~1.5 days grind
      currency: ShopCurrency.coins,
      quantity: 3,
      category: 'power_ups',
    ),
    ShopItem(
      id: ShopItemIds.freezeTime,
      name: '+10s Freeze Time',
      description: 'Adds 10 extra seconds to the quiz timer',
      cost: 1000,         // ~2 days
      currency: ShopCurrency.coins,
      quantity: 2,
      category: 'power_ups',
    ),
    ShopItem(
      id: ShopItemIds.skipQuestion,
      name: 'Skip Question',
      description: 'Skip a difficult question without penalty',
      cost: 1200,         // ~2 days
      currency: ShopCurrency.coins,
      quantity: 2,
      category: 'power_ups',
    ),
    ShopItem(
      id: ShopItemIds.doublePoints,
      name: '2x Points Booster',
      description: 'Double your score for the next quiz',
      cost: 2000,         // ~3-4 days
      currency: ShopCurrency.coins,
      quantity: 1,
      category: 'power_ups',
    ),
    ShopItem(
      id: ShopItemIds.extraLife,
      name: 'Extra Life',
      description: 'Continue after one wrong answer',
      cost: 1800,         // ~3 days
      currency: ShopCurrency.coins,
      quantity: 1,
      category: 'power_ups',
    ),
    ShopItem(
      id: ShopItemIds.hintReveal,
      name: 'Hint Reveal',
      description: 'Shows a hint for the correct answer',
      cost: 900,          // ~1.5 days
      currency: ShopCurrency.coins,
      quantity: 3,
      category: 'power_ups',
    ),
    ShopItem(
      id: ShopItemIds.audiencePoll,
      name: 'Audience Poll',
      description: 'See what others answered (percentage)',
      cost: 1500,         // ~2.5 days
      currency: ShopCurrency.coins,
      quantity: 1,
      category: 'power_ups',
    ),

    // ═══════════════════════════════════════════════════════════════════════
    // 🛡️ SHIELDS & PROTECTION
    // Gems: Daily perfect=10, Battle win=2 → rare currency
    // ═══════════════════════════════════════════════════════════════════════
    ShopItem(
      id: ShopItemIds.streakShield,
      name: 'Streak Freeze Shield',
      description: 'Protects your streak if you miss a day',
      cost: 8,            // ~1 perfect day
      currency: ShopCurrency.gems,
      quantity: 1,
      category: 'shields',
    ),
    ShopItem(
      id: ShopItemIds.scoreShield,
      name: 'Score Shield',
      description:
          'Re-opens today\'s daily score: your next attempt replaces it',
      cost: 12,           // ~1.5 perfect days
      currency: ShopCurrency.gems,
      quantity: 1,
      category: 'shields',
    ),

    // ═══════════════════════════════════════════════════════════════════════
    // ⚡ BOOSTERS
    // ═══════════════════════════════════════════════════════════════════════
    ShopItem(
      id: ShopItemIds.coinBooster,
      name: '2x Coin Booster',
      description: 'Earn double coins for one quiz session',
      cost: 10,           // ~1 perfect day
      currency: ShopCurrency.gems,
      quantity: 1,
      category: 'boosters',
    ),
    ShopItem(
      id: ShopItemIds.xpBooster,
      name: '2x XP Booster',
      description: 'Earn double XP for one quiz session',
      cost: 8,            // slightly cheaper
      currency: ShopCurrency.gems,
      quantity: 1,
      category: 'boosters',
    ),

    // ═══════════════════════════════════════════════════════════════════════
    // 🎨 COSMETICS - AVATARS
    // Rare/prestige items — needs weeks of play
    // ═══════════════════════════════════════════════════════════════════════
    ShopItem(
      id: ShopItemIds.vipAvatar,
      name: 'VIP Golden Avatar',
      description: 'Unlocks a glowing 3D VIP avatar',
      cost: 30,           // ~3 perfect days
      currency: ShopCurrency.gems,
      quantity: 1,
      isCosmetic: true,
      category: 'avatars',
    ),
    ShopItem(
      id: ShopItemIds.goldenAvatar,
      name: 'Golden Knight Avatar',
      description: 'Shining golden knight 3D avatar',
      cost: 50,           // ~5 perfect days
      currency: ShopCurrency.gems,
      quantity: 1,
      isCosmetic: true,
      category: 'avatars',
    ),
    ShopItem(
      id: ShopItemIds.neonAvatar,
      name: 'Neon Cyber Avatar',
      description: 'Futuristic neon glowing avatar',
      cost: 75,           // ~1 week
      currency: ShopCurrency.gems,
      quantity: 1,
      isCosmetic: true,
      category: 'avatars',
    ),
    ShopItem(
      id: ShopItemIds.royalAvatar,
      name: 'Royal Crown Avatar',
      description: 'Exclusive royal crown avatar',
      cost: 120,          // ~2 weeks — prestige
      currency: ShopCurrency.gems,
      quantity: 1,
      isCosmetic: true,
      category: 'avatars',
    ),

    // ═══════════════════════════════════════════════════════════════════════
    // 🏆 COSMETICS - BADGES
    // ═══════════════════════════════════════════════════════════════════════
    ShopItem(
      id: ShopItemIds.championBadge,
      name: 'Champion Badge',
      description: 'Show everyone you are a champion!',
      cost: 3000,         // ~5 days coins
      currency: ShopCurrency.coins,
      quantity: 1,
      isCosmetic: true,
      category: 'badges',
    ),
    ShopItem(
      id: ShopItemIds.scholarBadge,
      name: 'Scholar Badge',
      description: 'Display your knowledge and wisdom',
      cost: 5000,         // ~8 days coins
      currency: ShopCurrency.coins,
      quantity: 1,
      isCosmetic: true,
      category: 'badges',
    ),
    ShopItem(
      id: ShopItemIds.legendBadge,
      name: 'Legend Badge',
      description: 'The ultimate badge for legends only',
      cost: 100,          // ~10 perfect days — most prestigious
      currency: ShopCurrency.gems,
      quantity: 1,
      isCosmetic: true,
      category: 'badges',
    ),

    // ═══════════════════════════════════════════════════════════════════════
    // ✨ COSMETICS - NAME EFFECTS
    // ═══════════════════════════════════════════════════════════════════════
    ShopItem(
      id: ShopItemIds.fireName,
      name: '🔥 Fire Name Effect',
      description: 'Your name burns with fire effect',
      cost: 40,           // ~4 perfect days
      currency: ShopCurrency.gems,
      quantity: 1,
      isCosmetic: true,
      category: 'effects',
    ),
    ShopItem(
      id: ShopItemIds.rainbowName,
      name: '🌈 Rainbow Name Effect',
      description: 'Your name glows with rainbow colors',
      cost: 60,           // ~6 perfect days
      currency: ShopCurrency.gems,
      quantity: 1,
      isCosmetic: true,
      category: 'effects',
    ),
    ShopItem(
      id: ShopItemIds.goldName,
      name: '👑 Gold Name Effect',
      description: 'Your name shines in pure gold',
      cost: 90,           // ~9 perfect days
      currency: ShopCurrency.gems,
      quantity: 1,
      isCosmetic: true,
      category: 'effects',
    ),

    // ═══════════════════════════════════════════════════════════════════════
    // 🎁 SPECIAL PACKS (Best Value!)
    // ═══════════════════════════════════════════════════════════════════════
    ShopItem(
      id: ShopItemIds.starterPack,
      name: '🎁 Starter Pack',
      description: '5x 50-50 + 3x Freeze + Streak Shield',
      cost: 20,           // ~2 perfect days — entry level
      currency: ShopCurrency.gems,
      quantity: 1,
      category: 'packs',
    ),
    ShopItem(
      id: ShopItemIds.megaPack,
      name: '💎 Mega Pack',
      description: '10x 50-50 + 5x Freeze + 5x Skip + Coin Booster',
      cost: 55,           // ~6 perfect days
      currency: ShopCurrency.gems,
      quantity: 1,
      category: 'packs',
    ),
    ShopItem(
      id: ShopItemIds.legendPack,
      name: '👑 Legend Pack',
      description: 'All lifelines x10 + VIP Avatar + Legend Badge',
      cost: 130,          // ~2 weeks — ultimate pack
      currency: ShopCurrency.gems,
      quantity: 1,
      category: 'packs',
    ),
  ];

  /// Get items by category.
  static List<ShopItem> itemsByCategory(String category) {
    return items.where((item) => item.category == category).toList();
  }

  /// Get all unique categories.
  static List<String> get categories {
    return items.map((e) => e.category).toSet().toList();
  }

  /// Get category display name.
  static String categoryName(String category) {
    switch (category) {
      case 'power_ups':
        return '🎮 Power-Ups & Lifelines';
      case 'shields':
        return '🛡️ Shields & Protection';
      case 'boosters':
        return S.shopCatBoosters;
      case 'avatars':
        return S.shopCatAvatars;
      case 'badges':
        return S.shopCatBadges;
      case 'effects':
        return '✨ Name Effects';
      case 'packs':
        return '🎁 Special Packs';
      default:
        return category;
    }
  }
}
