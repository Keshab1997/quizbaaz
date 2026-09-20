import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_links.dart';
import '../../../data/models/user_model.dart';
import '../../../data/providers/auth_provider.dart';
import '../../../data/models/user_stats.dart';
import '../../../data/providers/locale_provider.dart';
import '../../../data/providers/user_provider.dart';
import '../../../data/services/account_deletion_service.dart';
import '../../../data/services/consent_service.dart';
import '../../../data/services/notification_service.dart';
import '../../screens/settings/language_screen.dart';
import '../../widgets/aura_avatar.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/name_effect_text.dart';
import 'avatar_selection_screen.dart';
import '../shop/purchase_history_screen.dart';
import '../../../data/models/shop_item.dart';
import '../../../l10n/app_strings.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<UserProvider>();
    final auth = context.watch<AuthProvider>();
    final user = userProvider.user;
    final stats = userProvider.stats;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(S.profileTitle,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_rounded, color: AppColors.neonCyan),
            onPressed: () => _showEditProfileSheet(context, userProvider, user),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            // Avatar & Info
            Center(
              child: Column(
                children: [
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const AvatarSelectionScreen()),
                      );
                    },
                    child: AuraAvatar(
                      url: user.effectiveAvatar,
                      size: 130,
                      fallbackAsset: user.avatarPath,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Change Avatar Button
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const AvatarSelectionScreen()),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.neonPurple.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.neonPurple.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.face_rounded, color: AppColors.neonPurple, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            S.profileChangeAvatar,
                            style: const TextStyle(
                              color: AppColors.neonPurple,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => _showEditProfileSheet(context, userProvider, user),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        NameEffectText(
                          user.fullName,
                          effectId: user.nameEffect,
                          style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white),
                        ),
                        const SizedBox(width: 6),
                        const Icon(Icons.edit_rounded,
                            size: 16, color: AppColors.neonCyan),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '@${user.username}',
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.neonCyan),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: (user.gender == UserGender.male
                                  ? AppColors.neonCyan
                                  : AppColors.neonPink)
                              .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          user.gender == UserGender.male ? S.profileMale : S.profileFemale,
                          style: TextStyle(
                            fontSize: 11,
                            color: user.gender == UserGender.male
                                ? AppColors.neonCyan
                                : AppColors.neonPink,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Stats Grid — every number comes from Hive-backed UserStats
            Row(
              children: [
                Expanded(
                  child: _buildStatTile(
                    icon: Icons.local_fire_department,
                    color: Colors.orangeAccent,
                    value: '${user.dailyStreak}',
                    label: S.profileDayStreak,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatTile(
                    icon: Icons.monetization_on_rounded,
                    color: AppColors.neonGold,
                    value: '${user.coins}',
                    label: S.coins,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildStatTile(
                    icon: Icons.track_changes_rounded,
                    color: AppColors.neonCyan,
                    value: stats.accuracyLabel,
                    label: S.accuracy,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatTile(
                    icon: Icons.quiz_rounded,
                    color: AppColors.neonPurple,
                    value: '${stats.totalQuizzes}',
                    label: S.profileQuizzesPlayed,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            GlassCard(
              borderRadius: 20,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(S.profilePerformance,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textSecondary)),
                  const SizedBox(height: 12),
                  _buildDetailRow(Icons.check_circle_rounded, S.profileCorrectAnswers,
                      '${stats.totalCorrect} / ${stats.totalAnswered}'),
                  const Divider(color: Colors.white12),
                  _buildDetailRow(Icons.emoji_events_rounded, S.profileBestDailyScore,
                      stats.bestDailyScore > 0
                          ? '${stats.bestDailyScore} pts'
                          : '--'),
                  const Divider(color: Colors.white12),
                  _buildDetailRow(Icons.bolt_rounded, S.profileBattlesWon,
                      '${stats.battlesWon} / ${stats.battlesPlayed}'),
                  const Divider(color: Colors.white12),
                  _buildDetailRow(Icons.timer_rounded, S.profileAvgTime,
                      stats.hasData
                          ? '${stats.averageSecondsPerQuestion.toStringAsFixed(1)}s'
                          : '--'),
                  const Divider(color: Colors.white12),
                  _buildDetailRow(Icons.whatshot_rounded, S.profileLongestStreak,
                      '${stats.longestStreak} days'),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Profile Details Card
            GlassCard(
              borderRadius: 20,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(S.profileDetails,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textSecondary)),
                  const SizedBox(height: 16),
                  _buildDetailRow(Icons.person_rounded, S.profileUsername,
                      '@${user.username}'),
                  const Divider(color: Colors.white12),
                  _buildDetailRow(
                      Icons.badge_rounded, S.profileFullName, user.fullName),
                  const Divider(color: Colors.white12),
                  _buildDetailRow(
                    Icons.wc_rounded,
                    S.profileGender,
                    user.gender == UserGender.male ? S.profileMale : S.profileFemale,
                    trailing: GestureDetector(
                      onTap: () => _showGenderPicker(context, userProvider),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          border: Border.all(
                              color: AppColors.neonCyan.withValues(alpha: 0.4)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(S.profileChange,
                            style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.neonCyan,
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
                  const Divider(color: Colors.white12),
                  _buildDetailRow(Icons.email_rounded, S.profileEmail,
                      auth.firebaseUser?.email ?? S.profileNotConnected),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Badges
            GlassCard(
              borderRadius: 20,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(S.profileBadges,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textSecondary)),
                  const SizedBox(height: 14),
                  Builder(builder: (context) {
                    final earned = _earnedBadges(stats, user.dailyStreak);
                    if (earned.isEmpty) {
                      return Text(
                        S.profileNoBadges,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary),
                      );
                    }
                    return Wrap(
                      spacing: 18,
                      runSpacing: 14,
                      children: earned
                          .map((b) => _buildBadge(b.title, b.icon, b.color))
                          .toList(),
                    );
                  }),
                  // Purchased badges from shop
                  Builder(builder: (context) {
                    final purchased = _purchasedBadges(userProvider);
                    if (purchased.isEmpty) return const SizedBox.shrink();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 16),
                        const Divider(color: Colors.white12),
                        const SizedBox(height: 14),
                        const Text('🏆 Shop Badges',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: AppColors.neonGold)),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 18,
                          runSpacing: 14,
                          children: purchased
                              .map((b) => _buildBadge(b.title, b.icon, b.color))
                              .toList(),
                        ),
                      ],
                    );
                  }),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Mode switcher
            ListTile(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              tileColor: Colors.white.withValues(alpha: 0.05),
              leading:
                  const Icon(Icons.swap_horiz, color: AppColors.neonCyan),
              title: Text(user.isGuest
                  ? S.profileGuestMode
                  : S.profileRegistered),
              subtitle: Text(user.isGuest
                  ? 'Tap to switch to Full User'
                  : 'Tap to test Guest Mode'),
              trailing: Switch(
                value: !user.isGuest,
                activeThumbColor: AppColors.neonCyan,
                onChanged: (val) {
                  userProvider.setGuestMode(!val);
                },
              ),
            ),
            const SizedBox(height: 16),

            // Google Account
            GlassCard(
              borderRadius: 16,
              child: Row(
                children: [
                  const Icon(Icons.g_mobiledata,
                      size: 34, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          auth.isSignedIn
                              ? (auth.firebaseUser?.displayName ??
                                  S.profileGoogleAccount)
                              : S.profileGoogleAccount,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.white),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          auth.isSignedIn
                              ? auth.firebaseUser?.email ?? S.profileConnected
                              : S.profileSignInPrompt,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: auth.isSignedIn
                                ? AppColors.neonGreen
                                : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (auth.isSignedIn)
                    TextButton(
                      onPressed: () => auth.signOut(),
                      child: Text(S.profileSignOut,
                          style: const TextStyle(
                              color: AppColors.neonRed,
                              fontWeight: FontWeight.bold)),
                    )
                  else
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed:
                           auth.isBusy ? null : () => _handleGoogleSignIn(context),
                      child: Text(
                        auth.isBusy ? S.pleaseWait : S.profileSignIn,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 24),

            // My Purchases
            _buildSectionTitle(Icons.shopping_bag_rounded, S.profileMyPurchases),
            const SizedBox(height: 12),
            GlassCard(
              borderRadius: 20,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const PurchaseHistoryScreen(),
                  ),
                );
              },
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          AppColors.neonGold.withValues(alpha: 0.28),
                          AppColors.neonGold.withValues(alpha: 0.08),
                        ],
                      ),
                      border: Border.all(
                          color: AppColors.neonGold.withValues(alpha: 0.4)),
                    ),
                    child: const Icon(Icons.receipt_long_rounded,
                        color: AppColors.neonGold, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          S.purchaseTitle,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          S.profileMyPurchasesHint,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded,
                      color: AppColors.textMuted, size: 22),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Name Effect
            _buildSectionTitle(Icons.auto_awesome_rounded, S.profileNameEffect),
            const SizedBox(height: 12),
            GlassCard(
              borderRadius: 20,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    S.profileNameEffectHint,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      _buildNameEffectOption(
                        context,
                        userProvider,
                        id: ShopItemIds.fireName,
                        label: 'Fire',
                        icon: Icons.local_fire_department_rounded,
                        color: AppColors.neonRed,
                      ),
                      const SizedBox(width: 10),
                      _buildNameEffectOption(
                        context,
                        userProvider,
                        id: ShopItemIds.rainbowName,
                        label: 'Rainbow',
                        icon: Icons.palette_rounded,
                        color: AppColors.neonPink,
                      ),
                      const SizedBox(width: 10),
                      _buildNameEffectOption(
                        context,
                        userProvider,
                        id: ShopItemIds.goldName,
                        label: 'Gold',
                        icon: Icons.auto_fix_high_rounded,
                        color: AppColors.neonGold,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Settings Section
            _buildSectionTitle(Icons.settings_rounded, S.profileSettings),
            const SizedBox(height: 12),
            GlassCard(
              borderRadius: 20,
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  _buildAppInfoRow(
                    Icons.language_rounded,
                    S.languageTitle,
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const LanguageScreen()),
                    ),
                    trailingText: context.watch<LocaleProvider>().followSystem
                        ? S.languageSystemDefault
                        : _languageLabel(context.watch<LocaleProvider>().appLanguage),
                  ),
                  const Divider(color: Colors.white12),
                  _buildSettingRow(context, userProvider, Icons.notifications_rounded,
                      S.profileNotifications, UserProvider.settingNotifications),
                  const Divider(color: Colors.white12),
                  _buildSettingRow(context, userProvider, Icons.music_note_rounded,
                      S.profileSound, UserProvider.settingSound),
                  const Divider(color: Colors.white12),
                  _buildSettingRow(context, userProvider, Icons.volume_up_rounded,
                      S.profileVibration, UserProvider.settingVibration,
                      defaultValue: false),
                  const Divider(color: Colors.white12),
                  _buildSettingRow(context, userProvider, Icons.dark_mode_rounded,
                      S.profileDarkMode, UserProvider.settingDarkMode),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // About Section
            _buildSectionTitle(Icons.info_outline_rounded, S.profileAbout),
            const SizedBox(height: 12),
            GlassCard(
              borderRadius: 20,
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  _buildAppInfoRow(Icons.star_rounded, S.profileRateApp,
                      () => _openLink(context, AppLinks.playStore)),
                  const Divider(color: Colors.white12),
                  _buildAppInfoRow(Icons.share_rounded, S.profileShare,
                      () => _shareApp(context)),
                  const Divider(color: Colors.white12),
                  _buildAppInfoRow(Icons.policy_rounded, S.profilePrivacy,
                      () => _openLink(context, AppLinks.privacyPolicy)),
                  const Divider(color: Colors.white12),
                  _buildAppInfoRow(Icons.description_rounded, S.profileTerms,
                      () => _openLink(context, AppLinks.terms)),
                  const Divider(color: Colors.white12),
                  _buildAppInfoRow(Icons.info_rounded, S.profileVersion(v: '1.0.0'), null),
                  // Google UMP change-consent entry point — shown only where
                  // required (EU/EEA/UK). Hidden automatically for India.
                  if (ConsentService.instance.privacyOptionsRequired) ...[
                    const Divider(color: Colors.white12),
                    _buildAppInfoRow(
                        Icons.privacy_tip_rounded, S.profileConsentOptions,
                        () => ConsentService.instance.showPrivacyOptions()),
                  ],
                  if (auth.isSignedIn) ...[
                    const Divider(color: Colors.white12),
                    _buildAppInfoRow(Icons.logout_rounded, S.profileSignOut,
                        () => _confirmSignOut(context, auth),
                        color: AppColors.neonRed),
                    const Divider(color: Colors.white12),
                    _buildAppInfoRow(Icons.delete_forever_rounded,
                        S.accountDelete,
                        () => _confirmDeleteAccount(context, auth, userProvider),
                        color: AppColors.neonRed),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  void _confirmSignOut(BuildContext context, AuthProvider auth) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(S.profileSignOut, style: const TextStyle(color: Colors.white)),
        content: Text(
          S.profileSignOutConfirm,
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(S.cancel, style: const TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(S.profileSignOut, style: const TextStyle(color: AppColors.neonRed)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await auth.signOut();
    }
  }

  /// Opens an external URL (Play Store, privacy policy, terms).
  Future<void> _openLink(BuildContext context, String url) async {
    final ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(S.linkOpenFailed),
          backgroundColor: Colors.red.shade800,
        ),
      );
    }
  }

  /// Shares the Play Store link via the system share sheet.
  Future<void> _shareApp(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    await Share.share(
      '${S.shareMsg}\n${AppLinks.playStore}',
      subject: S.appTitle,
      // Anchors the share sheet on iPads, where it must be a popover.
      sharePositionOrigin: box != null
          ? box.localToGlobal(Offset.zero) & box.size
          : null,
    );
  }

  /// Two-step account deletion: confirmation dialog (type DELETE), then a
  /// progress dialog while the remote data + Firebase Auth account are wiped.
  Future<void> _confirmDeleteAccount(BuildContext context, AuthProvider auth,
      UserProvider userProvider) async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        var match = false;
        return StatefulBuilder(
          builder: (ctx, setState) => AlertDialog(
            backgroundColor: AppColors.surfaceElevated,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
            title: Text(S.accountDelete,
                style: const TextStyle(color: AppColors.neonRed)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  S.accountDeleteWarning,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 13),
                ),
                if (!auth.isSignedIn) ...[
                  const SizedBox(height: 10),
                  Text(
                    S.accountDeleteLocalOnly,
                    style: const TextStyle(
                        color: AppColors.neonCyan, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 16),
                Text(
                  S.accountDeleteConfirmLabel,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  autofocus: true,
                  style: const TextStyle(color: Colors.white),
                  onChanged: (value) =>
                      setState(() => match = value.trim() == 'DELETE'),
                  decoration: InputDecoration(
                    hintText: 'DELETE',
                    hintStyle: const TextStyle(
                        color: Colors.white24, letterSpacing: 2),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.white24),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.neonRed),
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(S.cancel,
                    style:
                        const TextStyle(color: AppColors.textSecondary)),
              ),
              TextButton(
                onPressed: match ? () => Navigator.pop(ctx, true) : null,
                child: Text(S.accountDelete,
                    style: const TextStyle(color: AppColors.neonRed)),
              ),
            ],
          ),
        );
      },
    );
    if (confirmed != true) {
      controller.dispose();
      return;
    }
    // The confirm dialog above is async — never touch the context after it
    // without checking it is still mounted.
    if (!context.mounted) {
      controller.dispose();
      return;
    }

    // Progress dialog — not dismissible while the account is being deleted.
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: AppColors.surfaceElevated,
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(20))),
          content: Row(
            children: [
              const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Text(
                  S.accountDeleting,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    AccountDeletionStatus status = AccountDeletionStatus.failed;
    AccountCleanupReport report = const AccountCleanupReport();
    var accountGone = false;
    try {
      final user = auth.firebaseUser;
      if (user != null) {
        // Re-authentication happens inside the service *before* any remote
        // data is touched, so a cancel here changes nothing (R15).
        final result = await AccountDeletionService.shared.deleteAccount(user);
        status = result.status;
        report = result.report;
        accountGone = result.accountGone;
      }
      if (accountGone) {
        // Only once the account is really gone: wipe the local Hive profile
        // (and clear the tombstone that stopped it from being re-uploaded).
        await userProvider.signOutLocal();
        await AccountDeletionService.clearTombstone();
        if (user != null) await auth.signOut();
      }
    } catch (e) {
      debugPrint('Delete account flow error: $e');
      status = AccountDeletionStatus.failed;
    }

    if (!context.mounted) {
      controller.dispose();
      return;
    }
    // Close the progress dialog.
    Navigator.of(context, rootNavigator: true).pop();

    final messenger = ScaffoldMessenger.of(context);
    switch (status) {
      case AccountDeletionStatus.success:
        messenger.showSnackBar(
          SnackBar(content: Text(S.accountDeleted)),
        );
        break;
      case AccountDeletionStatus.partial:
        // The account is gone, but some collections could not be removed from
        // this device — say so instead of claiming a clean deletion.
        debugPrint('Delete account cleanup report: $report');
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              '${S.accountDeletedPartial} '
              '(${report.pending.length} hidden items)',
            ),
            backgroundColor: Colors.orange.shade800,
          ),
        );
        break;
      case AccountDeletionStatus.canceled:
        messenger.showSnackBar(
          SnackBar(
            content: Text(S.accountDeleteReauth),
            backgroundColor: Colors.orange.shade800,
          ),
        );
        break;
      case AccountDeletionStatus.failed:
        messenger.showSnackBar(
          SnackBar(
            content: Text(S.accountDeleteFailed),
            backgroundColor: Colors.red.shade800,
          ),
        );
        break;
    }
    controller.dispose();
  }

  Widget _buildDetailRow(IconData icon, String label, String value,
      {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.neonCyan),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary)),
                const SizedBox(height: 2),
                Text(value,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white)),
              ],
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  /// Badges are derived from real stats — nothing is shown "for free".
  List<_Badge> _earnedBadges(UserStats stats, int streak) {
    final badges = <_Badge>[];
    if (stats.bestDailyScore > 0) {
      badges.add(const _Badge(
          'First Score', Icons.flag_rounded, AppColors.neonCyan));
    }
    if (streak >= 7 || stats.longestStreak >= 7) {
      badges.add(const _Badge(
          '7 Day Streak', Icons.whatshot, Colors.orangeAccent));
    }
    if (stats.totalQuizzes >= 10) {
      badges.add(const _Badge(
          '10 Quizzes', Icons.school_rounded, AppColors.neonPurple));
    }
    if (stats.accuracyPercent >= 80 && stats.totalAnswered >= 20) {
      badges.add(const _Badge(
          'Sharp Shooter', Icons.military_tech, AppColors.neonGold));
    }
    if (stats.hasData && stats.averageSecondsPerQuestion > 0 &&
        stats.averageSecondsPerQuestion <= 6) {
      badges.add(const _Badge('Speed Demon', Icons.bolt, AppColors.neonCyan));
    }
    if (stats.battlesWon >= 5) {
      badges.add(const _Badge(
          'Battle Master', Icons.sports_mma_rounded, AppColors.neonPink));
    }
    return badges;
  }

  /// Badges purchased from the shop.
  List<_Badge> _purchasedBadges(UserProvider userProvider) {
    final badges = <_Badge>[];
    if (userProvider.hasItem(ShopItemIds.championBadge)) {
      badges.add(const _Badge('Champion', Icons.emoji_events_rounded, AppColors.neonGold));
    }
    if (userProvider.hasItem(ShopItemIds.scholarBadge)) {
      badges.add(const _Badge('Scholar', Icons.school_rounded, AppColors.neonPurple));
    }
    if (userProvider.hasItem(ShopItemIds.legendBadge)) {
      badges.add(const _Badge('Legend', Icons.star_rounded, AppColors.neonPink));
    }
    return badges;
  }

  Widget _buildStatTile({
    required IconData icon,
    required Color color,
    required String value,
    required String label,
  }) {
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 6),
          Text(value,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
          Text(label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildBadge(String title, IconData icon, Color color) {
    return Column(
      children: [
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.15),
            border: Border.all(color: color.withValues(alpha: 0.6)),
          ),
          child: Icon(icon, color: color, size: 26),
        ),
        const SizedBox(height: 6),
        Text(title,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.white)),
      ],
    );
  }

  void _showEditProfileSheet(
      BuildContext context, UserProvider userProvider, UserModel user) {
    final nameController =
        TextEditingController(text: user.fullName);
    final usernameController =
        TextEditingController(text: user.username);
    UserGender selectedGender = user.gender;

    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(S.profileEdit,
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white)),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      labelText: S.profileFullName,
                      labelStyle: const TextStyle(color: AppColors.textSecondary),
                      enabledBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.white24),
                      ),
                      focusedBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(color: AppColors.neonCyan),
                      ),),
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: usernameController,
                    decoration: InputDecoration(
                      labelText: S.profileUsername,
                      labelStyle: const TextStyle(color: AppColors.textSecondary),
                      enabledBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.white24),
                      ),
                      focusedBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(color: AppColors.neonCyan),
                      ),
                    ),
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 16),
                  Text(S.profileGender,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _buildGenderOption(
                          S.profileMale,
                          UserGender.male,
                          selectedGender == UserGender.male,
                          () => setState(() => selectedGender = UserGender.male),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildGenderOption(
                          S.profileFemale,
                          UserGender.female,
                          selectedGender == UserGender.female,
                          () => setState(() => selectedGender = UserGender.female),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.neonCyan,
                        foregroundColor: Colors.black,
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () {
                        userProvider.saveProfile(
                          username: usernameController.text.trim().isEmpty
                              ? user.username
                              : usernameController.text.trim(),
                          fullName: nameController.text.trim().isEmpty
                              ? user.fullName
                              : nameController.text.trim(),
                          gender: selectedGender,
                        );
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content:
                                  Text(S.profileUpdated)),
                        );
                      },
                      child: Text(S.profileSave,
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildGenderOption(
    String label,
    UserGender gender,
    bool isSelected,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? (gender == UserGender.male
                      ? AppColors.neonCyan
                      : AppColors.neonPink)
                  .withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? (gender == UserGender.male
                        ? AppColors.neonCyan
                        : AppColors.neonPink)
                    .withValues(alpha: 0.8)
                : Colors.white24,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              gender == UserGender.male
                  ? Icons.male_rounded
                  : Icons.female_rounded,
              color: isSelected
                  ? (gender == UserGender.male
                          ? AppColors.neonCyan
                          : AppColors.neonPink)
                      : AppColors.textMuted,
              size: 22,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected
                    ? (gender == UserGender.male
                            ? AppColors.neonCyan
                            : AppColors.neonPink)
                        : AppColors.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showGenderPicker(BuildContext context, UserProvider userProvider) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(S.profileSelectGender,
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _buildGenderOption(
                      S.profileMale,
                      UserGender.male,
                      false,
                      () {
                        userProvider.updateGender(UserGender.male);
                        Navigator.pop(ctx);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildGenderOption(
                      S.profileFemale,
                      UserGender.female,
                      false,
                      () {
                        userProvider.updateGender(UserGender.female);
                        Navigator.pop(ctx);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  /// Reads and writes the toggle straight through Hive — no dead switches.
  Widget _buildSettingRow(
    BuildContext context,
    UserProvider userProvider,
    IconData icon,
    String label,
    String settingKey, {
    bool defaultValue = true,
  }) {
    final isOn = userProvider.setting(settingKey, defaultValue: defaultValue);
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.neonCyan),
        const SizedBox(width: 12),
        Expanded(
          child: Text(label,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white)),
        ),
        Switch(
          value: isOn,
          onChanged: (val) async {
            if (settingKey == UserProvider.settingNotifications && val) {
              final allowed =
                  await NotificationService.instance.requestPermission();
              if (!allowed) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(S.notifPermissionDenied)),
                  );
                }
                return;
              }
            }
            await userProvider.setSetting(settingKey, val);
          },
          activeTrackColor: AppColors.neonCyan.withValues(alpha: 0.5),
          activeThumbColor: AppColors.neonCyan,
        ),
      ],
    );
  }

  /// A single selectable name-effect tile. Owned effects toggle on tap;
  /// unowned ones show a lock and point the player to the shop.
  Widget _buildNameEffectOption(
    BuildContext context,
    UserProvider userProvider, {
    required String id,
    required String label,
    required IconData icon,
    required Color color,
  }) {
    final user = userProvider.user;
    final owned = userProvider.ownsNameEffect(id);
    final selected = user.nameEffect == id;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (!owned) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                duration: const Duration(milliseconds: 1400),
                content: Text(S.profileEffectNotOwned),
              ),
            );
            return;
          }
          // Toggle: tap the active effect to remove it.
          userProvider.setNameEffect(selected ? null : id);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
          decoration: BoxDecoration(
            color: selected
                ? color.withValues(alpha: 0.16)
                : Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? color.withValues(alpha: 0.8)
                  : Colors.white.withValues(alpha: 0.12),
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                owned ? icon : Icons.lock_rounded,
                color: owned ? color : AppColors.textMuted,
                size: 22,
              ),
              const SizedBox(height: 6),
              NameEffectText(
                label,
                effectId: owned ? id : null,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: owned ? Colors.white : AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                selected
                    ? S.active
                    : (owned ? 'TAP TO USE' : 'LOCKED'),
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.4,
                  color: selected
                      ? color
                      : (owned ? AppColors.textSecondary : AppColors.textMuted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(IconData icon, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.neonCyan),
          const SizedBox(width: 8),
          Text(title,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Colors.white)),
        ],
      ),
    );
  }

  // ignore: unused_element
  Widget _buildGameStatCard(IconData icon, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                Text(value,
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Colors.white)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Native name of an app language, for the summary on the settings row.
  String _languageLabel(String code) {
    switch (code) {
      case 'bn':
        return 'বাংলা';
      case 'hi':
        return 'हिन्दी';
      default:
        return 'English';
    }
  }

  Widget _buildAppInfoRow(IconData icon, String label, VoidCallback? onTap,
      {Color? color, String? trailingText}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color ?? AppColors.neonCyan),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: color ?? Colors.white)),
            ),
            if (trailingText != null)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(
                  trailingText,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            if (onTap != null)
              const Icon(Icons.chevron_right_rounded,
                  size: 18, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }

Future<void> _handleGoogleSignIn(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    final userProvider = context.read<UserProvider>();
    final messenger = ScaffoldMessenger.of(context);

    try {
      final signedIn = await auth.signInWithGoogle();
      if (!signedIn) return;

      final user = auth.firebaseUser;
      if (user == null) return;

      userProvider.linkGoogleAccount(
        user.displayName ?? S.profilePlayerFallback,
        user.email ?? 'player@quizbaaz.app',
        photoURL: user.photoURL?.toString(),
      );

      messenger.showSnackBar(
        SnackBar(content: Text(S.profileSignedInGoogle)),
      );
    } on AuthException catch (e) {
      messenger.showSnackBar(
        SnackBar(
            content: Text(e.message),
            backgroundColor: Colors.red.shade800),
      );
    }
  }
}

/// A badge the player has actually earned.
class _Badge {
  final String title;
  final IconData icon;
  final Color color;

  const _Badge(this.title, this.icon, this.color);
}
