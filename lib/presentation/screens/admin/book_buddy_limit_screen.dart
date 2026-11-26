import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/providers/book_buddy_provider.dart';
import '../../../data/providers/user_provider.dart';
import '../../../data/services/firestore_service.dart';
import '../../../data/services/haptic_service.dart';
import '../../../l10n/app_strings.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/neon_button.dart';
import 'widgets/admin_access_banner.dart';
import 'widgets/admin_toast.dart';

/// Admin configuration screen for setting the global AI Book Buddy daily usage
/// cap per student (`config/app.book_buddy_daily_limit`).
class BookBuddyLimitScreen extends StatefulWidget {
  const BookBuddyLimitScreen({super.key});

  @override
  State<BookBuddyLimitScreen> createState() => _BookBuddyLimitScreenState();
}

class _BookBuddyLimitScreenState extends State<BookBuddyLimitScreen> {
  static const List<int> _presets = [0, 3, 5, 10, 15, 25];

  late final TextEditingController _limitController;
  int _selectedLimit = 5;
  bool _adminUnlimited = true;
  bool _loadingRemote = true;
  bool _saving = false;
  Object? _writeError;

  @override
  void initState() {
    super.initState();
    final currentCfg = context.read<UserProvider>().config;
    _selectedLimit = currentCfg.bookBuddyDailyLimit;
    _adminUnlimited = currentCfg.bookBuddyAdminUnlimited;
    _limitController = TextEditingController(text: '$_selectedLimit');

    WidgetsBinding.instance.addPostFrameCallback((_) => _loadLatestConfig());
  }

  @override
  void dispose() {
    _limitController.dispose();
    super.dispose();
  }

  Future<void> _loadLatestConfig() async {
    final userProvider = context.read<UserProvider>();
    final fresh = await userProvider.refreshAppConfig();
    if (!mounted) return;
    setState(() {
      _selectedLimit = fresh.bookBuddyDailyLimit;
      _adminUnlimited = fresh.bookBuddyAdminUnlimited;
      _limitController.text = '$_selectedLimit';
      _loadingRemote = false;
    });
  }

  void _selectPreset(int value) {
    Haptics.tap();
    setState(() {
      _selectedLimit = value;
      _limitController.text = '$value';
      _writeError = null;
    });
  }

  void _stepLimit(int delta) {
    final current =
        int.tryParse(_limitController.text.trim()) ?? _selectedLimit;
    final next = (current + delta).clamp(0, 500);
    _selectPreset(next);
  }

  Future<void> _saveLimit() async {
    final parsed = int.tryParse(_limitController.text.trim());
    if (parsed == null || parsed < 0 || parsed > 500) {
      AdminToast.showError(context, S.adminBookBuddyInvalidToast);
      return;
    }

    setState(() {
      _saving = true;
      _writeError = null;
    });

    final userProvider = context.read<UserProvider>();
    final bookBuddy = context.read<BookBuddyProvider>();

    try {
      await FirestoreService.updateConfigFields({
        'book_buddy_daily_limit': parsed,
        'book_buddy_admin_unlimited': _adminUnlimited,
      });

      final updatedConfig = userProvider.config.copyWith(
        bookBuddyDailyLimit: parsed,
        bookBuddyAdminUnlimited: _adminUnlimited,
      );
      await userProvider.applyAppConfig(updatedConfig);
      await bookBuddy.syncQuotaPolicy(
        config: updatedConfig,
        isAdmin: userProvider.isAdmin,
        userId: userProvider.user.userId,
        pullRemote: false,
      );

      if (!mounted) return;
      setState(() {
        _selectedLimit = parsed;
        _saving = false;
      });

      if (parsed == 0) {
        AdminToast.showInfo(context, S.adminBookBuddyPausedToast);
      } else {
        AdminToast.showSuccess(context, S.adminBookBuddySavedToast(n: parsed));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _writeError = e;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPaused = _selectedLimit <= 0;
    final statusColor = isPaused ? AppColors.neonRed : AppColors.neonGreen;

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
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.neonCyan.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.speed_rounded,
                color: AppColors.neonCyan,
                size: 18,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                S.adminBookBuddyScreenTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        actions: [
          if (_loadingRemote)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.neonCyan,
                  ),
                ),
              ),
            )
          else
            IconButton(
              tooltip: S.adminBookBuddyScreenTitle,
              onPressed: () {
                setState(() => _loadingRemote = true);
                _loadLatestConfig();
              },
              icon: const Icon(
                Icons.refresh_rounded,
                color: AppColors.neonCyan,
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_writeError != null) ...[
              AdminAccessBanner(error: _writeError!),
              const SizedBox(height: 16),
            ],

            // Hero live status card
            GlassCard(
              borderRadius: 20,
              padding: const EdgeInsets.all(18),
              borderColor: statusColor.withValues(alpha: 0.45),
              backgroundColor: const Color(0x45122B4A),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: statusColor.withValues(alpha: 0.45),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isPaused
                                  ? Icons.pause_circle_filled_rounded
                                  : Icons.bolt_rounded,
                              color: statusColor,
                              size: 14,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              isPaused
                                  ? S.adminBookBuddyPausedStatus
                                  : S.adminBookBuddyActiveStatus(
                                    n: _selectedLimit,
                                  ),
                              style: TextStyle(
                                color: statusColor,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    S.adminBookBuddyLiveLabel,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '$_selectedLimit',
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 40,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        S.adminBookBuddyPerDayUnit,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 22),

            // Quick presets
            Text(
              S.adminBookBuddyPresetsLabel,
              style: const TextStyle(
                color: AppColors.neonCyan,
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final preset in _presets)
                  _buildPresetChip(
                    value: preset,
                    selected: _selectedLimit == preset,
                  ),
              ],
            ),

            const SizedBox(height: 20),

            // Custom numeric stepper + input
            GlassCard(
              borderRadius: 18,
              padding: const EdgeInsets.all(16),
              borderColor: AppColors.neonPurple.withValues(alpha: 0.35),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    S.adminBookBuddyCustomLabel,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _buildStepperButton(
                        icon: Icons.remove_rounded,
                        onTap: () => _stepLimit(-1),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _limitController,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(3),
                          ],
                          onChanged: (raw) {
                            final v = int.tryParse(raw.trim());
                            if (v != null) {
                              setState(() => _selectedLimit = v.clamp(0, 500));
                            }
                          },
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                          decoration: InputDecoration(
                            hintText: S.adminBookBuddyCustomHint,
                            hintStyle: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 13,
                            ),
                            filled: true,
                            fillColor: AppColors.bgDark.withValues(alpha: 0.55),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: AppColors.neonCyan.withValues(
                                  alpha: 0.35,
                                ),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: AppColors.neonCyan.withValues(
                                  alpha: 0.28,
                                ),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(
                                color: AppColors.neonCyan,
                                width: 1.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      _buildStepperButton(
                        icon: Icons.add_rounded,
                        onTap: () => _stepLimit(1),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Admin unlimited toggle
            GlassCard(
              borderRadius: 18,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              borderColor: AppColors.neonGold.withValues(alpha: 0.35),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.neonGold.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.verified_user_rounded,
                      color: AppColors.neonGold,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          S.adminBookBuddyAdminBypassTitle,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          S.adminBookBuddyAdminBypassSub,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11.5,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch.adaptive(
                    value: _adminUnlimited,
                    activeThumbColor: AppColors.neonGold,
                    onChanged: (val) {
                      Haptics.tap();
                      setState(() => _adminUnlimited = val);
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Save button
            NeonButton(
              text:
                  _saving ? S.adminBookBuddySavingBtn : S.adminBookBuddySaveBtn,
              icon: const Icon(
                Icons.save_rounded,
                color: AppColors.bgDark,
                size: 20,
              ),
              gradient: AppColors.cyanGradient,
              glowColor: AppColors.neonCyan,
              onPressed: () {
                if (!_saving) _saveLimit();
              },
            ),

            const SizedBox(height: 20),

            // Explanation box
            GlassCard(
              borderRadius: 16,
              padding: const EdgeInsets.all(15),
              borderColor: AppColors.neonCyan.withValues(alpha: 0.22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        color: AppColors.neonCyan,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          S.adminBookBuddyHowItWorksTitle,
                          style: const TextStyle(
                            color: AppColors.neonCyan,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    S.adminBookBuddyHowItWorksBody,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12.5,
                      height: 1.55,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPresetChip({required int value, required bool selected}) {
    final isPause = value == 0;
    final accent = isPause ? AppColors.neonRed : AppColors.neonCyan;
    final label =
        isPause
            ? S.adminBookBuddyPauseOption
            : '$value ${S.adminBookBuddyPerDayUnit}';

    return GestureDetector(
      onTap: () => _selectPreset(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: selected && !isPause ? AppColors.cyanGradient : null,
          color:
              selected
                  ? (isPause ? AppColors.neonRed : null)
                  : AppColors.bgCard.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? accent : accent.withValues(alpha: 0.35),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color:
                selected
                    ? (isPause ? Colors.white : AppColors.bgDark)
                    : AppColors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Widget _buildStepperButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.neonCyan.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.neonCyan.withValues(alpha: 0.38)),
        ),
        child: Icon(icon, color: AppColors.neonCyan, size: 22),
      ),
    );
  }
}
