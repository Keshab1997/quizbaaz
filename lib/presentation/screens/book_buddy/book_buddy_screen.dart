import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/book_study_session.dart';
import '../../../data/providers/auth_provider.dart';
import '../../../data/providers/book_buddy_provider.dart';
import '../../../data/providers/quiz_provider.dart';
import '../../../data/providers/user_provider.dart';
import '../../../data/services/haptic_service.dart';
import '../../../data/services/sound_service.dart';
import '../../../l10n/app_strings.dart';
import '../../../l10n/strings_bn.dart';
import '../../../l10n/strings_en.dart';
import '../../../l10n/strings_hi.dart';
import '../../widgets/book_markdown_view.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/neon_button.dart';
import '../daily_quiz/daily_quiz_screen.dart';

/// AI Book Buddy — Students photograph a textbook page, choose their preferred
/// AI explanation language (`বাংলা` / `English` / `हिन्दी` independent of app
/// language), read rich formatted study cards with adjustable font size, ask
/// follow-up questions, and launch an unranked practice MCQ quiz.
class BookBuddyScreen extends StatefulWidget {
  const BookBuddyScreen({super.key});

  @override
  State<BookBuddyScreen> createState() => _BookBuddyScreenState();
}

class _BookBuddyScreenState extends State<BookBuddyScreen> {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _questionCtrl = TextEditingController();
  bool _showExtractedText = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final userProvider = context.read<UserProvider>();
      context.read<BookBuddyProvider>().syncQuotaPolicy(
        config: userProvider.config,
        isAdmin: userProvider.isAdmin,
        userId: userProvider.user.userId,
      );
    });
  }

  @override
  void dispose() {
    _questionCtrl.dispose();
    super.dispose();
  }

  /// Resolves a string key in the student's chosen AI reply language (`en`/`bn`/`hi`)
  /// so quick-prompt chips and initial prompts match the selected reply language!
  String _promptInLang(String key, String langCode) {
    final map = switch (langCode) {
      'bn' => kStringsBn,
      'hi' => kStringsHi,
      _ => kStringsEn,
    };
    return map[key] ?? kStringsEn[key] ?? S.raw(key);
  }

  TextStyle _contentStyle(
    String langCode, {
    required double fontSize,
    FontWeight fontWeight = FontWeight.w700,
    Color color = AppColors.textPrimary,
    double height = 1.4,
  }) {
    if (langCode == 'bn') {
      return GoogleFonts.hindSiliguri(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        height: height,
      );
    }
    return GoogleFonts.poppins(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
    );
  }

  /// Guests may read saved pages and replay saved quizzes, but every AI call
  /// needs a signed-in account: `firestore.rules` v2.4.0 only releases the key
  /// pool to `request.auth`, so a signed-out call would fail with "key pool
  /// not ready" — a misleading error. Ask for sign-in first instead.
  bool _guardAiAccess() {
    if (!context.read<UserProvider>().user.isGuest) return true;
    Haptics.error();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(S.bookBuddySignInRequired),
        backgroundColor: AppColors.neonRed,
      ),
    );
    return false;
  }

  Future<void> _handleSignIn() async {
    final auth = context.read<AuthProvider>();
    if (auth.isBusy) return;

    final userProvider = context.read<UserProvider>();
    final messenger = ScaffoldMessenger.of(context);

    try {
      final signedIn = await auth.signInWithGoogle();
      if (!mounted) return;
      if (!signedIn) {
        messenger.showSnackBar(SnackBar(content: Text(S.authSignInCanceled)));
        return;
      }

      final account = auth.firebaseUser;
      if (account == null) {
        throw AuthException(S.dashGoogleSignInFailed);
      }

      await userProvider.linkGoogleAccount(
        account.displayName ?? account.email ?? S.profilePlayerFallback,
        account.email ?? account.uid,
        photoURL: account.photoURL,
        uid: account.uid,
      );
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(S.bookBuddySignInSuccess)));
    } on AuthException catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Colors.red.shade800,
        ),
      );
    } catch (e) {
      debugPrint('BookBuddyScreen: Google Sign-In failed – $e');
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(S.dashGoogleSignInFailed),
          backgroundColor: Colors.red.shade800,
        ),
      );
    }
  }

  Future<void> _pickAndScan(ImageSource source) async {
    final buddy = context.read<BookBuddyProvider>();
    if (buddy.isBusy) return;
    if (!_guardAiAccess()) return;

    // Check daily quota before even opening camera/gallery so the user gets
    // instant feedback when today's limit is reached or paused.
    if (buddy.isQuotaExhausted) {
      Haptics.error();
      final msg =
          buddy.isPausedByAdmin
              ? S.bookBuddyErrPaused
              : S.bookBuddyErrDailyLimit(total: buddy.dailyLimit);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppColors.neonRed),
      );
      return;
    }

    SoundService.instance.playClick();
    Haptics.tap();

    final messenger = ScaffoldMessenger.of(context);
    final userId = context.read<UserProvider>().user.userId;
    final replyLang = buddy.replyLanguage;

    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 1800,
        maxHeight: 1800,
        imageQuality: 85,
      );
      if (picked == null || !mounted) return;

      final bytes = await picked.readAsBytes();
      if (!mounted) return;

      await buddy.scanBookPage(
        imageBytes: bytes,
        languageCode: replyLang,
        defaultTitle: _promptInLang('bookBuddyDefaultTitle', replyLang),
        initialQuestionLabel: _promptInLang(
          'bookBuddyInitialPrompt',
          replyLang,
        ),
        userId: userId,
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(S.bookBuddyErrPickFailed),
          backgroundColor: AppColors.neonRed,
        ),
      );
    }
  }

  Future<void> _sendQuestion([String? presetQuestion]) async {
    final buddy = context.read<BookBuddyProvider>();
    if (buddy.isBusy) return;
    if (!_guardAiAccess()) return;

    final text = (presetQuestion ?? _questionCtrl.text).trim();
    if (text.isEmpty) return;

    SoundService.instance.playClick();
    Haptics.tap();
    if (presetQuestion == null) {
      _questionCtrl.clear();
      FocusScope.of(context).unfocus();
    }

    final userId = context.read<UserProvider>().user.userId;
    await buddy.askQuestion(
      question: text,
      languageCode: buddy.replyLanguage,
      userId: userId,
    );
  }

  Future<void> _generateMcqs(int count) async {
    final buddy = context.read<BookBuddyProvider>();
    if (buddy.isBusy) return;
    if (!_guardAiAccess()) return;

    SoundService.instance.play('ui_whoosh');
    Haptics.tap();
    final userId = context.read<UserProvider>().user.userId;
    await buddy.generateMcqs(
      languageCode: buddy.replyLanguage,
      count: count,
      userId: userId,
    );
  }

  Future<void> _playGeneratedQuiz(BookStudySession session) async {
    if (session.generatedMcqs.isEmpty) return;
    SoundService.instance.play('ui_whoosh');
    Haptics.tap();

    final quiz = context.read<QuizProvider>();
    final navigator = Navigator.of(context);
    await quiz.startCustomPracticeQuiz(
      session.generatedMcqs,
      title: session.title,
    );
    if (!mounted) return;
    await navigator.push(
      MaterialPageRoute(builder: (_) => const DailyQuizScreen()),
    );
  }

  String _localizedError(BookBuddyProvider buddy, String code) {
    if (code == 'no_api_key') return S.bookBuddyErrNoKey;
    if (code == 'empty_mcq') return S.bookBuddyErrEmptyMcq;
    if (code == 'paused_by_admin') return S.bookBuddyErrPaused;
    if (code == 'daily_limit_reached') {
      return S.bookBuddyErrDailyLimit(total: buddy.dailyLimit);
    }
    return code;
  }

  @override
  Widget build(BuildContext context) {
    final buddy = context.watch<BookBuddyProvider>();
    final auth = context.watch<AuthProvider>();
    final isGuest = context.watch<UserProvider>().user.isGuest;
    final session = buddy.activeSession;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(
          S.bookBuddyTitle,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (session != null && !buddy.isBusy)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: TextButton.icon(
                onPressed: () {
                  SoundService.instance.playClick();
                  Haptics.tap();
                  setState(() => _showExtractedText = false);
                  buddy.startNewScan();
                },
                icon: const Icon(
                  Icons.add_a_photo_rounded,
                  size: 17,
                  color: AppColors.neonCyan,
                ),
                label: Text(
                  S.bookBuddyNewScan,
                  style: const TextStyle(
                    color: AppColors.neonCyan,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        physics: const BouncingScrollPhysics(),
        children: [
          // Top control bar: AI Reply Language selector + Font size A-/A+
          _buildLanguageAndFontBar(buddy, showFontControls: session != null),
          const SizedBox(height: 10),
          // Guests get a sign-in note instead of the quota meter: the key pool
          // is gated by `request.auth`, so no AI call can succeed signed out.
          if (isGuest) ...[
            _buildSignInNoteCard(auth),
            const SizedBox(height: 14),
          ] else ...[
            // Daily AI Quota meter (Admin-set limit & today's remaining count)
            _buildDailyQuotaCard(buddy),
            const SizedBox(height: 14),
          ],
          if (buddy.errorMessage != null) ...[
            _buildErrorBanner(buddy),
            const SizedBox(height: 14),
          ],
          if (buddy.isScanning)
            _buildScanningState(buddy)
          else if (session == null) ...[
            _buildCaptureHero(),
            if (buddy.savedSessions.isNotEmpty) ...[
              const SizedBox(height: 22),
              _buildSavedSessionsList(buddy),
            ],
          ] else ...[
            _buildSessionHeaderCard(buddy, session),
            const SizedBox(height: 16),
            for (final turn in session.turns) ...[
              _buildTurnCard(buddy, turn),
              const SizedBox(height: 14),
            ],
            if (buddy.isAsking) ...[
              _buildStatusTile(S.bookBuddyThinking),
              const SizedBox(height: 14),
            ],
            _buildQuickPromptsRow(buddy),
            const SizedBox(height: 12),
            _buildAskInputCard(buddy),
            const SizedBox(height: 20),
            _buildMcqGeneratorCard(buddy, session),
          ],
        ],
      ),
    );
  }

  /// Dedicated AI Reply Language selector (`বাংলা` / `English` / `हिन्दी`) +
  /// instant text size `A-` / `A+` controls.
  Widget _buildLanguageAndFontBar(
    BookBuddyProvider buddy, {
    required bool showFontControls,
  }) {
    final options = <(String, String)>[
      ('bn', S.bookBuddyLangBn),
      ('en', S.bookBuddyLangEn),
      ('hi', S.bookBuddyLangHi),
    ];

    return GlassCard(
      borderRadius: 18,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      borderColor: AppColors.neonPurple.withValues(alpha: 0.38),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.translate_rounded,
                size: 17,
                color: AppColors.neonCyan,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  S.bookBuddyLangLabel,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (showFontControls) ...[
                _buildFontStepButton(
                  label: 'A-',
                  enabled: buddy.textScale > BookBuddyProvider.minTextScale,
                  onTap: () => buddy.adjustTextScale(-0.08),
                ),
                const SizedBox(width: 6),
                _buildFontStepButton(
                  label: 'A+',
                  enabled: buddy.textScale < BookBuddyProvider.maxTextScale,
                  onTap: () => buddy.adjustTextScale(0.08),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var i = 0; i < options.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: _buildLanguagePill(
                    code: options[i].$1,
                    label: options[i].$2,
                    selected: buddy.replyLanguage == options[i].$1,
                    onTap:
                        buddy.isBusy
                            ? null
                            : () {
                              SoundService.instance.playClick();
                              Haptics.tap();
                              buddy.setReplyLanguage(options[i].$1);
                            },
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFontStepButton({
    required String label,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap:
          enabled
              ? () {
                SoundService.instance.playClick();
                Haptics.tap();
                onTap();
              }
              : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color:
              enabled
                  ? AppColors.neonCyan.withValues(alpha: 0.16)
                  : Colors.white.withValues(alpha: 0.04),
          border: Border.all(
            color:
                enabled
                    ? AppColors.neonCyan.withValues(alpha: 0.45)
                    : Colors.white12,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: enabled ? AppColors.neonCyan : AppColors.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  Widget _buildLanguagePill({
    required String code,
    required String label,
    required bool selected,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 170),
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: selected ? AppColors.cyanGradient : null,
          color: selected ? null : Colors.white.withValues(alpha: 0.05),
          border: Border.all(
            color:
                selected
                    ? AppColors.neonCyan
                    : Colors.white.withValues(alpha: 0.14),
          ),
          boxShadow:
              selected
                  ? [
                    BoxShadow(
                      color: AppColors.neonCyan.withValues(alpha: 0.28),
                      blurRadius: 12,
                    ),
                  ]
                  : null,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: _contentStyle(
            code,
            fontSize: 13.5,
            fontWeight: FontWeight.w800,
            color: selected ? AppColors.bgDark : AppColors.textPrimary,
            height: 1.2,
          ),
        ),
      ),
    );
  }

  /// Live Daily AI Quota card showing the Admin-set daily limit & remaining uses.
  /// Guest-only note. Saved pages and saved quizzes still work offline, but
  /// every AI call needs a Firebase auth token before the rules release a key,
  /// so the sign-in card replaces the (meaningless) quota meter.
  Widget _buildSignInNoteCard(AuthProvider auth) {
    return GlassCard(
      borderRadius: 22,
      borderColor: AppColors.neonPurple.withValues(alpha: 0.45),
      backgroundColor: AppColors.bgCardGlass,
      padding: const EdgeInsets.all(16),
      shadows: [
        BoxShadow(
          color: AppColors.neonPurple.withValues(alpha: 0.16),
          blurRadius: 22,
          offset: const Offset(0, 10),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.neonPurple.withValues(alpha: 0.16),
                  border: Border.all(
                    color: AppColors.neonPurple.withValues(alpha: 0.5),
                  ),
                ),
                child: const Icon(
                  Icons.lock_person_rounded,
                  color: AppColors.neonPurple,
                  size: 21,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  S.bookBuddySignInTitle,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            S.bookBuddySignInSubtitle,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: NeonButton(
              text: S.bookBuddySignInButton,
              height: 46,
              gradient: AppColors.violetGradient,
              glowColor: AppColors.neonPurple,
              icon:
                  auth.isBusy
                      ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      )
                      : const Icon(
                        Icons.login_rounded,
                        color: Colors.white,
                        size: 19,
                      ),
              textStyle: const TextStyle(
                color: Colors.white,
                fontSize: 13.5,
                fontWeight: FontWeight.w900,
              ),
              onPressed: () => unawaited(_handleSignIn()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDailyQuotaCard(BookBuddyProvider buddy) {
    final isUnlimited = buddy.isUnlimitedForUser;
    final isPaused = buddy.isPausedByAdmin;
    final exhausted = buddy.isQuotaExhausted;

    final Color accent;
    final IconData icon;
    final String badgeText;

    if (isUnlimited) {
      accent = AppColors.neonGold;
      icon = Icons.verified_user_rounded;
      badgeText = S.bookBuddyQuotaUnlimited;
    } else if (isPaused) {
      accent = AppColors.neonRed;
      icon = Icons.pause_circle_filled_rounded;
      badgeText = S.bookBuddyQuotaPausedBadge;
    } else if (exhausted) {
      accent = AppColors.neonRed;
      icon = Icons.hourglass_disabled_rounded;
      badgeText = S.bookBuddyQuotaExhaustedBadge;
    } else if (buddy.remainingToday <= 1) {
      accent = AppColors.neonGold;
      icon = Icons.bolt_rounded;
      badgeText = S.bookBuddyQuotaRemaining(
        left: buddy.remainingToday,
        total: buddy.dailyLimit,
      );
    } else {
      accent = AppColors.neonGreen;
      icon = Icons.bolt_rounded;
      badgeText = S.bookBuddyQuotaRemaining(
        left: buddy.remainingToday,
        total: buddy.dailyLimit,
      );
    }

    final double progress =
        isUnlimited
            ? 1.0
            : (buddy.dailyLimit <= 0
                ? 0.0
                : (buddy.remainingToday / buddy.dailyLimit).clamp(0.0, 1.0));

    return GlassCard(
      borderRadius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      borderColor: accent.withValues(alpha: 0.38),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: accent),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  S.bookBuddyQuotaLabel,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: accent.withValues(alpha: 0.45)),
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(
                    color: accent,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          if (!isUnlimited && buddy.dailyLimit > 0) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: Colors.white.withValues(alpha: 0.09),
                valueColor: AlwaysStoppedAnimation<Color>(accent),
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            S.bookBuddyQuotaHint,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 11,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(BookBuddyProvider buddy) {
    return GlassCard(
      borderRadius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      borderColor: AppColors.neonRed.withValues(alpha: 0.55),
      backgroundColor: AppColors.neonRed.withValues(alpha: 0.12),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: AppColors.neonRed,
            size: 21,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _localizedError(buddy, buddy.errorMessage!),
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: buddy.clearError,
            icon: const Icon(
              Icons.close_rounded,
              size: 18,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanningState(BookBuddyProvider buddy) {
    final previewBytes = buddy.activeImageBytes;
    return GlassCard(
      borderRadius: 22,
      borderColor: AppColors.neonCyan.withValues(alpha: 0.4),
      padding: const EdgeInsets.all(22),
      child: Column(
        children: [
          if (previewBytes != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.memory(
                previewBytes,
                height: 170,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 18),
          ],
          const CircularProgressIndicator(color: AppColors.neonCyan),
          const SizedBox(height: 14),
          Text(
            S.bookBuddyScanning,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCaptureHero() {
    return GlassCard(
      borderRadius: 24,
      borderColor: AppColors.neonCyan.withValues(alpha: 0.38),
      padding: const EdgeInsets.all(22),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppColors.cyanGradient,
              boxShadow: [
                BoxShadow(
                  color: AppColors.neonCyan.withValues(alpha: 0.35),
                  blurRadius: 22,
                ),
              ],
            ),
            child: const Icon(
              Icons.document_scanner_rounded,
              color: AppColors.bgDark,
              size: 36,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            S.bookBuddyEmptyTitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            S.bookBuddyEmptySubtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14.5,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: NeonButton(
                  text: S.bookBuddyScanCamera,
                  height: 50,
                  gradient: AppColors.cyanGradient,
                  glowColor: AppColors.neonCyan,
                  icon: const Icon(
                    Icons.camera_alt_rounded,
                    color: AppColors.bgDark,
                    size: 20,
                  ),
                  textStyle: const TextStyle(
                    color: AppColors.bgDark,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                  onPressed: () => _pickAndScan(ImageSource.camera),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: NeonButton(
                  text: S.bookBuddyScanGallery,
                  height: 50,
                  gradient: AppColors.violetGradient,
                  glowColor: AppColors.neonPurple,
                  icon: const Icon(
                    Icons.photo_library_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                  textStyle: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                  onPressed: () => _pickAndScan(ImageSource.gallery),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSessionHeaderCard(
    BookBuddyProvider buddy,
    BookStudySession session,
  ) {
    final previewBytes = buddy.activeImageBytes;
    final badgeText =
        session.usedVisionFallback
            ? S.bookBuddyVisionUsed
            : S.bookBuddyOcrSaved(
              label:
                  session.tokenSavingsLabel.isNotEmpty
                      ? session.tokenSavingsLabel
                      : '90%',
            );

    return GlassCard(
      borderRadius: 22,
      borderColor: AppColors.neonCyan.withValues(alpha: 0.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (previewBytes != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.memory(
                    previewBytes,
                    width: 62,
                    height: 62,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 12),
              ] else ...[
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        AppColors.neonCyan.withValues(alpha: 0.25),
                        AppColors.neonPurple.withValues(alpha: 0.2),
                      ],
                    ),
                    border: Border.all(
                      color: AppColors.neonCyan.withValues(alpha: 0.45),
                    ),
                  ),
                  child: const Icon(
                    Icons.auto_stories_rounded,
                    color: AppColors.neonCyan,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.title,
                      style: _contentStyle(
                        session.replyLanguage,
                        fontSize: 18 * buddy.textScale,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.neonGreen.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppColors.neonGreen.withValues(alpha: 0.38),
                        ),
                      ),
                      child: Text(
                        badgeText,
                        style: const TextStyle(
                          color: AppColors.neonGreen,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (session.hasExtractedText) ...[
            const SizedBox(height: 12),
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap:
                  () =>
                      setState(() => _showExtractedText = !_showExtractedText),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    const Icon(
                      Icons.subject_rounded,
                      size: 17,
                      color: AppColors.neonCyan,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        S.bookBuddyExtractedHeader,
                        style: const TextStyle(
                          color: AppColors.neonCyan,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Icon(
                      _showExtractedText
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: AppColors.neonCyan,
                      size: 22,
                    ),
                  ],
                ),
              ),
            ),
            if (_showExtractedText) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.bgDark.withValues(alpha: 0.58),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: SelectableText(
                  session.extractedText,
                  style: _contentStyle(
                    session.replyLanguage,
                    fontSize: 14 * buddy.textScale,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary,
                    height: 1.55,
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildTurnCard(BookBuddyProvider buddy, BookChatTurn turn) {
    final lang = buddy.replyLanguage;
    return GlassCard(
      borderRadius: 22,
      padding: const EdgeInsets.all(18),
      borderColor: AppColors.neonPurple.withValues(alpha: 0.38),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Student prompt pill
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: AppColors.neonGold.withValues(alpha: 0.12),
              border: Border.all(
                color: AppColors.neonGold.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.help_rounded,
                    size: 18,
                    color: AppColors.neonGold,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    turn.question,
                    style: _contentStyle(
                      lang,
                      fontSize: 15 * buddy.textScale,
                      fontWeight: FontWeight.w800,
                      color: AppColors.neonGold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // AI Tutor badge header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppColors.cyanGradient,
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  size: 14,
                  color: AppColors.bgDark,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                S.bookBuddyAiTutor,
                style: const TextStyle(
                  color: AppColors.neonCyan,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Rich formatted Markdown explanation (headings, tables, bold, callouts)
          BookMarkdownView(
            markdown: turn.answer,
            languageCode: lang,
            textScale: buddy.textScale,
          ),
        ],
      ),
    );
  }

  Widget _buildStatusTile(String label) {
    return GlassCard(
      borderRadius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      child: Row(
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: AppColors.neonCyan,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickPromptsRow(BookBuddyProvider buddy) {
    final lang = buddy.replyLanguage;
    final chips = [
      _promptInLang('bookBuddyQuickSimple', lang),
      _promptInLang('bookBuddyQuickPoints', lang),
      _promptInLang('bookBuddyQuickExamples', lang),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          for (var i = 0; i < chips.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            ActionChip(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              backgroundColor: AppColors.surfaceElevated,
              side: BorderSide(
                color: AppColors.neonCyan.withValues(alpha: 0.4),
              ),
              label: Text(
                chips[i],
                style: _contentStyle(
                  lang,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.neonCyan,
                  height: 1.2,
                ),
              ),
              onPressed: buddy.isBusy ? null : () => _sendQuestion(chips[i]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAskInputCard(BookBuddyProvider buddy) {
    return GlassCard(
      borderRadius: 18,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      borderColor: AppColors.neonCyan.withValues(alpha: 0.35),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _questionCtrl,
              enabled: !buddy.isBusy,
              minLines: 1,
              maxLines: 3,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendQuestion(),
              style: _contentStyle(
                buddy.replyLanguage,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                hintText: _promptInLang(
                  'bookBuddyAskHint',
                  buddy.replyLanguage,
                ),
                hintStyle: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 14,
                ),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: buddy.isBusy ? null : _sendQuestion,
            style: IconButton.styleFrom(
              backgroundColor: AppColors.neonCyan.withValues(alpha: 0.22),
            ),
            icon: const Icon(
              Icons.send_rounded,
              color: AppColors.neonCyan,
              size: 21,
            ),
            tooltip: S.bookBuddyAskSend,
          ),
        ],
      ),
    );
  }

  Widget _buildMcqGeneratorCard(
    BookBuddyProvider buddy,
    BookStudySession session,
  ) {
    return GlassCard(
      borderRadius: 22,
      borderColor: AppColors.neonGold.withValues(alpha: 0.45),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppColors.goldGradient,
                ),
                child: const Icon(
                  Icons.quiz_rounded,
                  color: AppColors.bgDark,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      S.bookBuddyMcqSectionTitle,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      S.bookBuddyMcqSectionSubtitle,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12.5,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (buddy.isGeneratingMcqs)
            _buildStatusTile(S.bookBuddyGeneratingMcq)
          else if (session.hasMcqs) ...[
            NeonButton(
              text: S.bookBuddyPlayQuiz(n: session.generatedMcqs.length),
              height: 50,
              gradient: AppColors.goldGradient,
              glowColor: AppColors.neonGold,
              icon: const Icon(
                Icons.play_arrow_rounded,
                color: AppColors.bgDark,
                size: 24,
              ),
              onPressed: () => _playGeneratedQuiz(session),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: AppColors.neonCyan.withValues(alpha: 0.45),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => _generateMcqs(5),
                    child: Text(
                      S.bookBuddyGen5Mcq,
                      style: const TextStyle(
                        color: AppColors.neonCyan,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: AppColors.neonPurple.withValues(alpha: 0.5),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => _generateMcqs(10),
                    child: Text(
                      S.bookBuddyGen10Mcq,
                      style: const TextStyle(
                        color: AppColors.neonPurple,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ] else
            Row(
              children: [
                Expanded(
                  child: NeonButton(
                    text: S.bookBuddyGen5Mcq,
                    height: 48,
                    gradient: AppColors.cyanGradient,
                    glowColor: AppColors.neonCyan,
                    textStyle: const TextStyle(
                      color: AppColors.bgDark,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w900,
                    ),
                    onPressed: () => _generateMcqs(5),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: NeonButton(
                    text: S.bookBuddyGen10Mcq,
                    height: 48,
                    gradient: AppColors.goldGradient,
                    glowColor: AppColors.neonGold,
                    textStyle: const TextStyle(
                      color: AppColors.bgDark,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w900,
                    ),
                    onPressed: () => _generateMcqs(10),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildSavedSessionsList(BookBuddyProvider buddy) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          S.bookBuddySavedHeader,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        for (final item in buddy.savedSessions) ...[
          GlassCard(
            borderRadius: 16,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            onTap: () => buddy.openSavedSession(item),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.neonCyan.withValues(alpha: 0.14),
                  ),
                  child: const Icon(
                    Icons.menu_book_rounded,
                    color: AppColors.neonCyan,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _contentStyle(
                          item.replyLanguage,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        S.bookBuddySavedMeta(
                          turns: item.turns.length,
                          mcqs: item.generatedMcqs.length,
                        ),
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: S.bookBuddyDeleteSession,
                  onPressed: () => buddy.deleteSession(item.id),
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    color: AppColors.textMuted,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}
