import 'package:admin_api_key_manager/admin_api_key_manager.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/services/shop_service.dart';
import '../../widgets/glass_card.dart';
import 'user_list_screen.dart';
import 'shop_manager_screen.dart';
import 'avatar_manager_screen.dart';
import 'chapter_manager_screen.dart';
import '../../../l10n/app_strings.dart';

/// Admin Dashboard - Main admin panel with overview and navigation
class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

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
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.neonGold.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.shield_rounded,
                color: AppColors.neonGold,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              S.dashAdminPanel,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.neonGreen.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.circle, color: AppColors.neonGreen, size: 8),
                SizedBox(width: 6),
                Text(
                  'Online',
                  style: TextStyle(
                    color: AppColors.neonGreen,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Welcome
            const Text(
              'Welcome, Admin!',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Manage your app from here',
              style: TextStyle(
                color: AppColors.textMuted.withValues(alpha: 0.7),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 24),

            // Quick Stats
            _buildStatsGrid(),
            const SizedBox(height: 24),

            // Management Section
            const Text(
              'MANAGEMENT',
              style: TextStyle(
                color: AppColors.neonCyan,
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            _buildManagementGrid(context),
            const SizedBox(height: 24),

            // Quick Actions
            const Text(
              'QUICK ACTIONS',
              style: TextStyle(
                color: AppColors.neonCyan,
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            _buildQuickActions(context),
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsGrid() {
    return FutureBuilder<Map<String, int>>(
      future: ShopService.getAdminStats(),
      builder: (context, snapshot) {
        final stats = snapshot.data ?? const <String, int>{};
        final isLoading = snapshot.connectionState == ConnectionState.waiting;
        final hasError = snapshot.hasError;

        String statValue(String key) {
          if (isLoading) return '...';
          if (hasError) return '--';
          return '${stats[key] ?? 0}';
        }

        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.0,
          children: [
            _buildStatCard(
              icon: Icons.people_rounded,
              label: 'Total Users',
              value: statValue('total_users'),
              color: AppColors.neonCyan,
            ),
            _buildStatCard(
              icon: Icons.person_outline_rounded,
              label: 'Guest Users',
              value: statValue('guest_users'),
              color: AppColors.neonPurple,
            ),
            _buildStatCard(
              icon: Icons.quiz_rounded,
              label: 'Quizzes Today',
              value: statValue('players_today'),
              color: AppColors.neonGold,
            ),
            _buildStatCard(
              icon: Icons.shopping_bag_rounded,
              label: 'Shop Items',
              value: statValue('shop_items'),
              color: AppColors.neonGreen,
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return GlassCard(
      borderRadius: 16,
      borderColor: color.withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 18),
                ),
                const Spacer(),
                Icon(Icons.trending_up_rounded, color: color, size: 14),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: FittedBox(
                alignment: Alignment.centerLeft,
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildManagementGrid(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.0,
      children: [
        _buildManagementCard(
          icon: Icons.people_rounded,
          label: 'User List',
          description: 'View all registered users',
          color: AppColors.neonCyan,
          onTap:
              () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const UserListScreen()),
              ),
        ),
        _buildManagementCard(
          icon: Icons.person_outline_rounded,
          label: 'Guest List',
          description: 'View all guest users',
          color: AppColors.neonPurple,
          onTap:
              () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const UserListScreen(isGuestView: true),
                ),
              ),
        ),
        _buildManagementCard(
          icon: Icons.menu_book_rounded,
          label: 'Chapter Manager',
          description: 'Subjects, chapters & question banks',
          color: AppColors.neonGreen,
          onTap:
              () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ChapterManagerScreen()),
              ),
        ),
        _buildManagementCard(
          icon: Icons.vpn_key_rounded,
          label: 'API Keys',
          description: 'LLM keys for question generation',
          color: AppColors.neonRed,
          onTap:
              () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AdminApiKeysScreen()),
              ),
        ),
        _buildManagementCard(
          icon: Icons.store_rounded,
          label: 'Shop Manager',
          description: 'Manage shop items',
          color: AppColors.neonGold,
          onTap:
              () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ShopManagerScreen()),
              ),
        ),
        _buildManagementCard(
          icon: Icons.face_rounded,
          label: 'Avatar Manager',
          description: 'Manage avatars',
          color: AppColors.neonPink,
          onTap:
              () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AvatarManagerScreen()),
              ),
        ),
      ],
    );
  }

  Widget _buildManagementCard({
    required IconData icon,
    required String label,
    required String description,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: GlassCard(
        borderRadius: 16,
        borderColor: color.withValues(alpha: 0.3),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(height: 12),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Flexible(
                child: Text(
                  description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 10,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    return Column(
      children: [
        _buildQuickAction(
          icon: Icons.add_rounded,
          label: 'Add New Shop Item',
          color: AppColors.neonGreen,
          onTap:
              () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ShopManagerScreen(initialAction: 'add'),
                ),
              ),
        ),
        const SizedBox(height: 10),
        _buildQuickAction(
          icon: Icons.add_photo_alternate_rounded,
          label: 'Add New Avatar',
          color: AppColors.neonPink,
          onTap:
              () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder:
                      (_) => const AvatarManagerScreen(initialAction: 'add'),
                ),
              ),
        ),
        const SizedBox(height: 10),
        _buildQuickAction(
          icon: Icons.refresh_rounded,
          label: 'Refresh Data',
          color: AppColors.neonCyan,
          onTap: () {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('🔄 Data refreshed!')));
          },
        ),
      ],
    );
  }

  Widget _buildQuickAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: GlassCard(
        borderRadius: 14,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                color: AppColors.textMuted,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
