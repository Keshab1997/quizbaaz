import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/purchase_history.dart';
import '../../../data/models/shop_item.dart';
import '../../../data/providers/user_provider.dart';
import '../../widgets/glass_card.dart';
import '../../../l10n/app_strings.dart';

/// Shows the player's complete purchase history with category filtering.
class PurchaseHistoryScreen extends StatefulWidget {
  const PurchaseHistoryScreen({super.key});

  @override
  State<PurchaseHistoryScreen> createState() => _PurchaseHistoryScreenState();
}

class _PurchaseHistoryScreenState extends State<PurchaseHistoryScreen> {
  List<PurchaseHistory> _allHistory = [];
  List<PurchaseHistory> _filteredHistory = [];
  bool _isLoading = true;
  String _filter = 'all';

  // All available categories
  final List<Map<String, String>> _categories = [
    {'id': 'all', 'label': '🏪 All'},
    {'id': 'power_ups', 'label': '🎮 Power-Ups'},
    {'id': 'shields', 'label': '🛡️ Shields'},
    {'id': 'boosters', 'label': '⚡ Boosters'},
    {'id': 'avatars', 'label': '🎨 Avatars'},
    {'id': 'badges', 'label': '🏆 Badges'},
    {'id': 'effects', 'label': '✨ Effects'},
    {'id': 'packs', 'label': '🎁 Packs'},
    {'id': 'coins', 'label': '💰 Coins'},
    {'id': 'gems', 'label': '💎 Gems'},
  ];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    final userProvider = context.read<UserProvider>();
    final history = await userProvider.loadPurchaseHistory(limit: 100);
    if (mounted) {
      setState(() {
        _allHistory = history;
        _applyFilter();
        _isLoading = false;
      });
    }
  }

  void _applyFilter() {
    if (_filter == 'all') {
      _filteredHistory = _allHistory;
    } else if (_filter == 'coins') {
      _filteredHistory =
          _allHistory.where((h) => h.currency == 'coins').toList();
    } else if (_filter == 'gems') {
      _filteredHistory =
          _allHistory.where((h) => h.currency == 'gems').toList();
    } else {
      _filteredHistory =
          _allHistory.where((h) => h.category == _filter).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: AppColors.textPrimary,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          S.purchaseTitle,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.neonGold),
            onPressed: _loadHistory,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildStatsSummary(),
          _buildCategoryFilter(),
          Expanded(
            child:
                _isLoading
                    ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.neonGold,
                      ),
                    )
                    : _filteredHistory.isEmpty
                    ? _buildEmptyState()
                    : _buildHistoryList(),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsSummary() {
    final totalPurchases = _allHistory.length;
    final totalCoinsSpent = _allHistory
        .where((h) => h.currency == 'coins')
        .fold<int>(0, (sum, h) => sum + h.cost);
    final totalGemsSpent = _allHistory
        .where((h) => h.currency == 'gems')
        .fold<int>(0, (sum, h) => sum + h.cost);
    final totalItems = _allHistory.fold<int>(0, (sum, h) => sum + h.quantity);

    // Category counts
    final categoryCounts = <String, int>{};
    for (final h in _allHistory) {
      categoryCounts[h.category] = (categoryCounts[h.category] ?? 0) + 1;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: GlassCard(
        borderRadius: 20,
        borderColor: AppColors.neonGold.withValues(alpha: 0.3),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Main stats
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatItem(
                    icon: Icons.shopping_bag_rounded,
                    value: '$totalPurchases',
                    label: S.purchaseOrders,
                    color: AppColors.neonCyan,
                  ),
                  _buildStatItem(
                    icon: Icons.monetization_on_rounded,
                    value: _formatNumber(totalCoinsSpent),
                    label: S.purchaseCoinsSpent,
                    color: AppColors.neonGold,
                  ),
                  _buildStatItem(
                    icon: Icons.diamond_rounded,
                    value: _formatNumber(totalGemsSpent),
                    label: S.purchaseGemsSpent,
                    color: AppColors.neonPurple,
                  ),
                  _buildStatItem(
                    icon: Icons.inventory_2_rounded,
                    value: '$totalItems',
                    label: S.items,
                    color: AppColors.neonGreen,
                  ),
                ],
              ),
              // Category breakdown
              if (categoryCounts.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Divider(color: Colors.white12),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children:
                      categoryCounts.entries.map((entry) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _categoryColor(
                              entry.key,
                            ).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _categoryColor(
                                entry.key,
                              ).withValues(alpha: 0.3),
                            ),
                          ),
                          child: Text(
                            '${_categoryEmoji(entry.key)} ${entry.value}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: _categoryColor(entry.key),
                            ),
                          ),
                        );
                      }).toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryFilter() {
    return SizedBox(
      height: 45,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final cat = _categories[index];
          final isSelected = _filter == cat['id'];

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _filter = cat['id']!;
                  _applyFilter();
                });
              },
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
                  cat['label']!,
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

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.shopping_bag_outlined,
            size: 80,
            color: AppColors.textMuted.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            _filter == 'all'
                ? S.purchaseNone
                : S.purchaseNoneFiltered(filter: _getFilterName()),
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _filter == 'all' ? S.purchaseEmptyBody : S.shopEmptyCategory,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  String _getFilterName() {
    final cat = _categories.firstWhere(
      (c) => c['id'] == _filter,
      orElse: () => {'label': _filter},
    );
    return cat['label']!.split(' ').skip(1).join(' ');
  }

  Widget _buildHistoryList() {
    return RefreshIndicator(
      color: AppColors.neonGold,
      onRefresh: _loadHistory,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        itemCount: _filteredHistory.length,
        itemBuilder: (context, index) {
          final history = _filteredHistory[index];
          return _buildHistoryCard(history);
        },
      ),
    );
  }

  Widget _buildHistoryCard(PurchaseHistory history) {
    final isCoins = history.currency == 'coins';
    final accent = isCoins ? AppColors.neonGold : AppColors.neonPurple;
    final icon = _iconForItem(history.itemId);
    final catColor = _categoryColor(history.category);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        borderRadius: 18,
        borderColor: catColor.withValues(alpha: 0.3),
        onTap: () => _showDetailSheet(history),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // Item icon with category badge
              Stack(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: catColor.withValues(alpha: 0.15),
                      border: Border.all(
                        color: catColor.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Icon(icon, color: catColor, size: 26),
                  ),
                  // Category badge
                  Positioned(
                    bottom: -2,
                    right: -2,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1B2646),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: catColor.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Text(
                        _categoryEmoji(history.category),
                        style: const TextStyle(fontSize: 8),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 14),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      history.itemName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Flexible(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Category tag
                              Flexible(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: catColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    history.categoryDisplayName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: catColor,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Quantity
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'x${history.quantity}',
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Date
                        Flexible(
                          child: Text(
                            _formatDate(history.purchasedAt),
                            textAlign: TextAlign.end,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // Cost
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isCoins
                            ? Icons.monetization_on_rounded
                            : Icons.diamond_rounded,
                        color: accent,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${history.cost}',
                        style: TextStyle(
                          color: accent,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    history.currency.toUpperCase(),
                    style: TextStyle(
                      color: accent.withValues(alpha: 0.7),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDetailSheet(PurchaseHistory history) {
    final isCoins = history.currency == 'coins';
    final accent = isCoins ? AppColors.neonGold : AppColors.neonPurple;
    final icon = _iconForItem(history.itemId);
    final catColor = _categoryColor(history.category);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder:
          (context) => Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1B2646),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: catColor.withValues(alpha: 0.3)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Handle bar
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Item icon
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: catColor.withValues(alpha: 0.15),
                      border: Border.all(
                        color: catColor.withValues(alpha: 0.4),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: catColor.withValues(alpha: 0.3),
                          blurRadius: 20,
                        ),
                      ],
                    ),
                    child: Icon(icon, color: catColor, size: 40),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    history.itemName,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Category badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: catColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: catColor.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      history.categoryDisplayName,
                      style: TextStyle(
                        color: catColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Stats
                  Row(
                    children: [
                      Expanded(
                        child: _buildDetailStat(
                          S.quantity,
                          'x${history.quantity}',
                          AppColors.neonCyan,
                          Icons.inventory_2_rounded,
                        ),
                      ),
                      Expanded(
                        child: _buildDetailStat(
                          S.cost,
                          '${history.cost}',
                          accent,
                          isCoins
                              ? Icons.monetization_on_rounded
                              : Icons.diamond_rounded,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildDetailStat(
                          S.currency,
                          history.currency.toUpperCase(),
                          accent,
                          Icons.attach_money_rounded,
                        ),
                      ),
                      Expanded(
                        child: _buildDetailStat(
                          S.purchaseTotalSpent,
                          '${history.cost * history.quantity}',
                          AppColors.neonPink,
                          Icons.account_balance_wallet_rounded,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    S.purchasedOn(date: _formatFullDate(history.purchasedAt)),
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.2),
                          ),
                        ),
                      ),
                      child: Text(
                        S.close,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  Widget _buildDetailStat(
    String label,
    String value,
    Color color,
    IconData icon,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
          ),
        ],
      ),
    );
  }

  IconData _iconForItem(String itemId) {
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

  Color _categoryColor(String category) {
    switch (category) {
      case 'power_ups':
        return AppColors.neonCyan;
      case 'shields':
        return AppColors.neonGreen;
      case 'boosters':
        return AppColors.neonPink;
      case 'avatars':
        return AppColors.neonPurple;
      case 'badges':
        return AppColors.neonGold;
      case 'effects':
        return AppColors.neonRed;
      case 'packs':
        return AppColors.neonGold;
      default:
        return AppColors.neonCyan;
    }
  }

  String _categoryEmoji(String category) {
    switch (category) {
      case 'power_ups':
        return '🎮';
      case 'shields':
        return '🛡️';
      case 'boosters':
        return '⚡';
      case 'avatars':
        return '🎨';
      case 'badges':
        return '🏆';
      case 'effects':
        return '✨';
      case 'packs':
        return '🎁';
      default:
        return '📦';
    }
  }

  String _formatNumber(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) return S.today;
    if (diff.inDays == 1) return S.yesterday;
    if (diff.inDays < 7) return S.daysAgo(n: diff.inDays);
    return '${date.day}/${date.month}';
  }

  String _formatFullDate(DateTime date) {
    final months = S.monthsShort;
    return '${date.day} ${months[date.month - 1]} ${date.year}, ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}
