import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_assets.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/models/shop_item.dart';
import '../../../data/providers/user_provider.dart';
import '../../../data/services/haptic_service.dart';
import '../../../data/services/shop_service.dart';
import '../../../data/services/sound_service.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/purchase_celebration.dart';
import 'purchase_history_screen.dart';
import '../../widgets/cached_avatar.dart';
import '../../../l10n/app_strings.dart';

/// Maps shop item IDs to their avatar asset paths.
String? _avatarPathForItem(String itemId) {
  switch (itemId) {
    case ShopItemIds.vipAvatar:
      return AppAssets.vipAvatar;
    case ShopItemIds.goldenAvatar:
      return AppAssets.goldenKnightAvatar;
    case ShopItemIds.neonAvatar:
      return AppAssets.neonCyberAvatar;
    case ShopItemIds.royalAvatar:
      return AppAssets.royalCrownAvatar;
    default:
      return null;
  }
}

class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  String _selectedCategory = 'all';
  List<Map<String, dynamic>> _cloudItems = [];
  bool _isLoadingCloud = false;

  @override
  void initState() {
    super.initState();
    _loadCloudItems();
  }

  Future<void> _loadCloudItems() async {
    setState(() => _isLoadingCloud = true);
    try {
      final items = await ShopService.getShopItems();
      if (mounted) {
        setState(() {
          _cloudItems = items;
          _isLoadingCloud = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingCloud = false);
    }
  }

  IconData _iconFor(String itemId) {
    switch (itemId) {
      // Power-ups
      case ShopItemIds.fiftyFifty:
        return Icons.filter_2;
      case ShopItemIds.freezeTime:
        return Icons.ac_unit;
      case ShopItemIds.skipQuestion:
        return Icons.skip_next_rounded;
      case ShopItemIds.doublePoints:
        return Icons.double_arrow_rounded;
      case ShopItemIds.extraLife:
        return Icons.favorite_rounded;
      case ShopItemIds.hintReveal:
        return Icons.lightbulb_rounded;
      case ShopItemIds.audiencePoll:
        return Icons.people_rounded;

      // Shields
      case ShopItemIds.streakShield:
        return Icons.shield_moon;
      case ShopItemIds.scoreShield:
        return Icons.security_rounded;

      // Boosters
      case ShopItemIds.coinBooster:
        return Icons.monetization_on_rounded;
      case ShopItemIds.xpBooster:
        return Icons.trending_up_rounded;

      // Avatars
      case ShopItemIds.vipAvatar:
        return Icons.workspace_premium;
      case ShopItemIds.goldenAvatar:
        return Icons.military_tech_rounded;
      case ShopItemIds.neonAvatar:
        return Icons.auto_awesome_rounded;
      case ShopItemIds.royalAvatar:
        return Icons.diamond_rounded;

      // Badges
      case ShopItemIds.championBadge:
        return Icons.emoji_events_rounded;
      case ShopItemIds.scholarBadge:
        return Icons.school_rounded;
      case ShopItemIds.legendBadge:
        return Icons.stars_rounded;

      // Effects
      case ShopItemIds.fireName:
        return Icons.local_fire_department_rounded;
      case ShopItemIds.rainbowName:
        return Icons.palette_rounded;
      case ShopItemIds.goldName:
        return Icons.auto_fix_high_rounded;

      // Packs
      case ShopItemIds.starterPack:
        return Icons.card_giftcard_rounded;
      case ShopItemIds.megaPack:
        return Icons.inventory_2_rounded;
      case ShopItemIds.legendPack:
        return Icons.workspace_premium_rounded;

      default:
        return Icons.card_giftcard;
    }
  }

  Color _accentFor(String itemId) {
    switch (itemId) {
      // Power-ups - Cyan
      case ShopItemIds.fiftyFifty:
      case ShopItemIds.freezeTime:
      case ShopItemIds.skipQuestion:
      case ShopItemIds.doublePoints:
      case ShopItemIds.extraLife:
      case ShopItemIds.hintReveal:
      case ShopItemIds.audiencePoll:
        return AppColors.neonCyan;

      // Shields - Green
      case ShopItemIds.streakShield:
      case ShopItemIds.scoreShield:
        return AppColors.neonGreen;

      // Boosters - Pink
      case ShopItemIds.coinBooster:
      case ShopItemIds.xpBooster:
        return AppColors.neonPink;

      // Avatars - Purple
      case ShopItemIds.vipAvatar:
      case ShopItemIds.goldenAvatar:
      case ShopItemIds.neonAvatar:
      case ShopItemIds.royalAvatar:
        return AppColors.neonPurple;

      // Badges - Gold
      case ShopItemIds.championBadge:
      case ShopItemIds.scholarBadge:
      case ShopItemIds.legendBadge:
        return AppColors.neonGold;

      // Effects - Rainbow/Red
      case ShopItemIds.fireName:
        return AppColors.neonRed;
      case ShopItemIds.rainbowName:
        return AppColors.neonPink;
      case ShopItemIds.goldName:
        return AppColors.neonGold;

      // Packs - Gold
      case ShopItemIds.starterPack:
      case ShopItemIds.megaPack:
      case ShopItemIds.legendPack:
        return AppColors.neonGold;

      default:
        return AppColors.neonCyan;
    }
  }

  List<ShopItem> get _filteredItems {
    if (_selectedCategory == 'all') {
      return ShopCatalog.items;
    }
    return ShopCatalog.itemsByCategory(_selectedCategory);
  }

  List<Map<String, dynamic>> get _filteredCloudItems {
    if (_selectedCategory == 'all') {
      return _cloudItems;
    }
    return _cloudItems
        .where((item) => item['category'] == _selectedCategory)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<UserProvider>();
    final user = userProvider.user;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(
          S.shopTitle,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.history_rounded, color: AppColors.neonGold),
            tooltip: S.purchaseTitle,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const PurchaseHistoryScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Balance Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
            child: GlassCard(
              borderRadius: 20,
              borderColor: AppColors.neonCyan.withValues(alpha: 0.4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.monetization_on,
                        color: AppColors.neonGold,
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        S.shopCoinsLabel(n: user.coins),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.neonGold,
                        ),
                      ),
                    ],
                  ),
                  Container(height: 30, width: 1, color: Colors.white24),
                  Row(
                    children: [
                      const Icon(
                        Icons.diamond,
                        color: AppColors.neonPurple,
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        S.shopGemsLabel(n: user.gems),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.neonPurple,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Category Filter
          _buildCategoryFilter(),

          // Items List
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 100),
              children: [
                // Section Header
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Text(
                        _selectedCategory == 'all'
                            ? S.shopAllItems
                            : ShopCatalog.categoryName(_selectedCategory),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textSecondary,
                          letterSpacing: 1.1,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        S.shopItemCount(n: _filteredItems.length),
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),

                // Local Items
                ..._filteredItems.map((item) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: _ShopItemCard(
                      item: item,
                      icon: _iconFor(item.id),
                      accent: _accentFor(item.id),
                      owned: userProvider.inventoryCount(item.id),
                      affordable: userProvider.canAfford(item),
                      onBuy: () => _handleBuy(context, userProvider, item),
                    ),
                  );
                }),

                // Cloud Items (from Firestore)
                if (_filteredCloudItems.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 16, bottom: 12),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.neonCyan.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.cloud_rounded,
                                color: AppColors.neonCyan,
                                size: 14,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                S.shopCloudItems,
                                style: const TextStyle(
                                  color: AppColors.neonCyan,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  ..._filteredCloudItems.map((cloudItem) {
                    final shopItem = ShopItem(
                      id: cloudItem['id'] ?? '',
                      name: cloudItem['name'] ?? S.item,
                      description: cloudItem['description'] ?? '',
                      cost: cloudItem['price'] ?? 0,
                      currency:
                          cloudItem['currency'] == 'gems'
                              ? ShopCurrency.gems
                              : ShopCurrency.coins,
                      quantity: cloudItem['quantity'] ?? 1,
                      isCosmetic: cloudItem['is_cosmetic'] ?? false,
                      category: cloudItem['category'] ?? 'power_ups',
                    );
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: _ShopItemCard(
                        item: shopItem,
                        icon: Icons.inventory_2_rounded,
                        accent: AppColors.neonCyan,
                        owned: 0,
                        affordable: userProvider.canAfford(shopItem),
                        onBuy:
                            () => _handleBuy(context, userProvider, shopItem),
                        cloudImageUrl: cloudItem['icon_url'],
                      ),
                    );
                  }),
                ],

                // Loading indicator
                if (_isLoadingCloud)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(
                      child: CircularProgressIndicator(
                        color: AppColors.neonCyan,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryFilter() {
    final categories = ['all', ...ShopCatalog.categories];

    return SizedBox(
      height: 45,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final cat = categories[index];
          final isSelected = _selectedCategory == cat;
          final label =
              cat == 'all'
                  ? S.shopCatAll
                  : ShopCatalog.categoryName(cat).split(' ').skip(1).join(' ');

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: GestureDetector(
              onTap: () => setState(() => _selectedCategory = cat),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color:
                      isSelected
                          ? AppColors.neonGold.withValues(alpha: 0.2)
                          : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color:
                        isSelected
                            ? AppColors.neonGold.withValues(alpha: 0.5)
                            : Colors.white.withValues(alpha: 0.1),
                  ),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    color:
                        isSelected
                            ? AppColors.neonGold
                            : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _handleBuy(
    BuildContext context,
    UserProvider userProvider,
    ShopItem item,
  ) {
    final result = userProvider.purchaseItem(item);

    switch (result) {
      case PurchaseStatus.success:
        SoundService.instance.play('purchase');
        Haptics.medium();
        PurchaseCelebration.show(
          context,
          itemName: item.name,
          subtitle:
              item.isCosmetic
                  ? S.shopUnlockedForever
                  : S.shopAdded(n: item.quantity),
          characterAsset: AppAssets.quizChampion,
          itemIcon: _iconFor(item.id),
          accent: item.costsCoins ? AppColors.neonGold : AppColors.neonPurple,
        );
        break;
      case PurchaseStatus.alreadyOwned:
        SoundService.instance.play('ui_deny');
        Haptics.error();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(milliseconds: 1200),
            content: Text(S.shopAlreadyOwn),
          ),
        );
        break;
      case PurchaseStatus.insufficientFunds:
        SoundService.instance.play('ui_deny');
        Haptics.error();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(milliseconds: 1200),
            content: Text(S.shopNotEnough(currency: item.currencyLabel)),
            backgroundColor: Colors.red.shade800,
          ),
        );
        break;
    }
  }
}

class _ShopItemCard extends StatelessWidget {
  final ShopItem item;
  final IconData icon;
  final Color accent;
  final int owned;
  final bool affordable;
  final VoidCallback onBuy;
  final String? cloudImageUrl;

  const _ShopItemCard({
    required this.item,
    required this.icon,
    required this.accent,
    required this.owned,
    required this.affordable,
    required this.onBuy,
    this.cloudImageUrl,
  });

  @override
  Widget build(BuildContext context) {
    final avatarPath = _avatarPathForItem(item.id);
    final hasCloudImage = cloudImageUrl != null && cloudImageUrl!.isNotEmpty;

    return GlassCard(
      borderRadius: 18,
      borderColor: accent.withValues(alpha: 0.3),
      child: Row(
        children: [
          // Icon, Avatar Preview, or Cloud Image
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: accent.withValues(alpha: 0.4)),
            ),
            child:
                hasCloudImage
                    ? ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: CachedAvatar(
                        url: cloudImageUrl!,
                        fit: BoxFit.cover,
                        progressColor: accent,
                        fallbackIcon: icon,
                        fallbackIconColor: accent,
                        fallbackIconSize: 26,
                      ),
                    )
                    : avatarPath != null
                    ? ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.asset(
                        avatarPath,
                        fit: BoxFit.cover,
                        errorBuilder:
                            (_, __, ___) => Icon(icon, color: accent, size: 26),
                      ),
                    )
                    : Icon(icon, color: accent, size: 26),
          ),
          const SizedBox(width: 14),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    if (item.category == 'packs')
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.neonGold.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          S.shopBestValue,
                          style: const TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                            color: AppColors.neonGold,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  item.description,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _ownedLabel(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color:
                        owned > 0
                            ? AppColors.neonCyan
                            : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Buy Button
          _buildButton(),
        ],
      ),
    );
  }

  String _ownedLabel() {
    if (item.isCosmetic) {
      return owned > 0 ? S.shopOwnedCheck : S.shopNotOwned;
    }
    return S.shopOwnedTimes(n: owned);
  }

  Widget _buildButton() {
    if (item.isCosmetic && owned > 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.neonCyan.withValues(alpha: 0.5)),
        ),
        child: Text(
          S.shopOwnedCheck,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: AppColors.neonCyan,
          ),
        ),
      );
    }

    final Color bg = affordable ? accent : Colors.white.withValues(alpha: 0.08);
    final Color fg =
        affordable
            ? (item.costsCoins ? Colors.black : Colors.white)
            : AppColors.textSecondary;

    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: fg,
        disabledBackgroundColor: Colors.white.withValues(alpha: 0.08),
        disabledForegroundColor: AppColors.textSecondary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      ),
      onPressed: onBuy,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            item.costsCoins
                ? Icons.monetization_on_rounded
                : Icons.diamond_rounded,
            size: 14,
          ),
          const SizedBox(width: 4),
          Text(
            '${item.cost}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
