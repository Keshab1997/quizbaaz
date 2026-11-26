import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/book_study_session.dart';
import '../../../data/providers/book_buddy_provider.dart';
import '../../../data/providers/quiz_provider.dart';
import '../../../data/providers/user_provider.dart';
import '../../../data/services/haptic_service.dart';
import '../../../data/services/sound_service.dart';
import '../../../l10n/app_strings.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/neon_button.dart';
import '../daily_quiz/daily_quiz_screen.dart';

/// AI Book Buddy — Students photograph a textbook page, receive a clear
/// step-by-step explanation, ask follow-up questions, and launch an unranked
/// practice MCQ quiz generated directly from their book page.
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
  void dispose() {
    _questionCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAndScan(ImageSource source) async {
    final buddy = context.read<BookBuddyProvider>();
    if (buddy.isBusy) return;

    SoundService.instance.playClick();
    Haptics.tap();

    final messenger = ScaffoldMessenger.of(context);
    final userId = context.read<UserProvider>().user.userId;

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
        languageCode: S.code,
        defaultTitle: S.bookBuddyDefaultTitle,
        initialQuestionLabel: S.bookBuddyInitialPrompt,
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
      languageCode: S.code,
      userId: userId,
    );
  }

  Future<void> _generateMcqs(int count) async {
    final buddy = context.read<BookBuddyProvider>();
    if (buddy.isBusy) return;

    SoundService.instance.play('ui_whoosh');
    Haptics.tap();
    final userId = context.read<UserProvider>().user.userId;
    await buddy.generateMcqs(
      languageCode: S.code,
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

  String _localizedError(String code) {
    if (code == 'no_api_key') return S.bookBuddyErrNoKey;
    if (code == 'empty_mcq') return S.bookBuddyErrEmptyMcq;
    return code;
  }

  @override
  Widget build(BuildContext context) {
    final buddy = context.watch<BookBuddyProvider>();
    final session = buddy.activeSession;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(
          S.bookBuddyTitle,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (session != null && !buddy.isBusy)
            TextButton.icon(
              onPressed: () {
                SoundService.instance.playClick();
                Haptics.tap();
                setState(() => _showExtractedText = false);
                buddy.startNewScan();
              },
              icon: const Icon(
                Icons.add_a_photo_rounded,
                size: 16,
                color: AppColors.neonCyan,
              ),
              label: Text(
                S.bookBuddyNewScan,
                style: const TextStyle(
                  color: AppColors.neonCyan,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
        physics: const BouncingScrollPhysics(),
        children: [
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
            const SizedBox(height: 14),
            for (final turn in session.turns) ...[
              _buildTurnCard(turn),
              const SizedBox(height: 12),
            ],
            if (buddy.isAsking) ...[
              _buildStatusTile(S.bookBuddyThinking),
              const SizedBox(height: 12),
            ],
            _buildQuickPromptsRow(buddy),
            const SizedBox(height: 10),
            _buildAskInputCard(buddy),
            const SizedBox(height: 18),
            _buildMcqGeneratorCard(buddy, session),
          ],
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
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _localizedError(buddy.errorMessage!),
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12.5,
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
                height: 160,
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
              fontSize: 14,
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
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppColors.cyanGradient,
              boxShadow: [
                BoxShadow(
                  color: AppColors.neonCyan.withValues(alpha: 0.35),
                  blurRadius: 20,
                ),
              ],
            ),
            child: const Icon(
              Icons.document_scanner_rounded,
              color: AppColors.bgDark,
              size: 34,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            S.bookBuddyEmptyTitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            S.bookBuddyEmptySubtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: NeonButton(
                  text: S.bookBuddyScanCamera,
                  height: 48,
                  gradient: AppColors.cyanGradient,
                  glowColor: AppColors.neonCyan,
                  icon: const Icon(
                    Icons.camera_alt_rounded,
                    color: AppColors.bgDark,
                    size: 19,
                  ),
                  textStyle: const TextStyle(
                    color: AppColors.bgDark,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                  ),
                  onPressed: () => _pickAndScan(ImageSource.camera),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: NeonButton(
                  text: S.bookBuddyScanGallery,
                  height: 48,
                  gradient: AppColors.violetGradient,
                  glowColor: AppColors.neonPurple,
                  icon: const Icon(
                    Icons.photo_library_rounded,
                    color: Colors.white,
                    size: 19,
                  ),
                  textStyle: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
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
      borderRadius: 20,
      borderColor: AppColors.neonCyan.withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (previewBytes != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(
                    previewBytes,
                    width: 58,
                    height: 58,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 12),
              ] else ...[
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.neonCyan.withValues(alpha: 0.16),
                    border: Border.all(
                      color: AppColors.neonCyan.withValues(alpha: 0.45),
                    ),
                  ),
                  child: const Icon(
                    Icons.auto_stories_rounded,
                    color: AppColors.neonCyan,
                    size: 22,
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
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.neonGreen.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppColors.neonGreen.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Text(
                        badgeText,
                        style: const TextStyle(
                          color: AppColors.neonGreen,
                          fontSize: 10.5,
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
            const SizedBox(height: 10),
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
                      size: 16,
                      color: AppColors.neonCyan,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        S.bookBuddyExtractedHeader,
                        style: const TextStyle(
                          color: AppColors.neonCyan,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Icon(
                      _showExtractedText
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: AppColors.neonCyan,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
            if (_showExtractedText) ...[
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.bgDark.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SelectableText(
                  session.extractedText,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildTurnCard(BookChatTurn turn) {
    return GlassCard(
      borderRadius: 18,
      borderColor: AppColors.neonPurple.withValues(alpha: 0.3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.help_outline_rounded,
                size: 15,
                color: AppColors.neonGold,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  turn.question,
                  style: const TextStyle(
                    color: AppColors.neonGold,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 18, color: AppColors.outline),
          Row(
            children: [
              const Icon(
                Icons.auto_awesome_rounded,
                size: 15,
                color: AppColors.neonCyan,
              ),
              const SizedBox(width: 6),
              Text(
                S.bookBuddyAiTutor,
                style: const TextStyle(
                  color: AppColors.neonCyan,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            turn.answer,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13.5,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusTile(String label) {
    return GlassCard(
      borderRadius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              color: AppColors.neonCyan,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickPromptsRow(BookBuddyProvider buddy) {
    final chips = [
      S.bookBuddyQuickSimple,
      S.bookBuddyQuickPoints,
      S.bookBuddyQuickExamples,
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          for (var i = 0; i < chips.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            ActionChip(
              backgroundColor: AppColors.surfaceElevated,
              side: BorderSide(
                color: AppColors.neonCyan.withValues(alpha: 0.35),
              ),
              label: Text(
                chips[i],
                style: const TextStyle(
                  color: AppColors.neonCyan,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      borderColor: AppColors.neonCyan.withValues(alpha: 0.3),
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
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13.5,
              ),
              decoration: InputDecoration(
                hintText: S.bookBuddyAskHint,
                hintStyle: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 13,
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
              backgroundColor: AppColors.neonCyan.withValues(alpha: 0.2),
            ),
            icon: const Icon(
              Icons.send_rounded,
              color: AppColors.neonCyan,
              size: 20,
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
      borderColor: AppColors.neonGold.withValues(alpha: 0.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppColors.goldGradient,
                ),
                child: const Icon(
                  Icons.quiz_rounded,
                  color: AppColors.bgDark,
                  size: 21,
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
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      S.bookBuddyMcqSectionSubtitle,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11.5,
                        height: 1.35,
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
              height: 48,
              gradient: AppColors.goldGradient,
              glowColor: AppColors.neonGold,
              icon: const Icon(
                Icons.play_arrow_rounded,
                color: AppColors.bgDark,
                size: 22,
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
                        fontSize: 12,
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
                        fontSize: 12,
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
                    height: 46,
                    gradient: AppColors.cyanGradient,
                    glowColor: AppColors.neonCyan,
                    textStyle: const TextStyle(
                      color: AppColors.bgDark,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                    onPressed: () => _generateMcqs(5),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: NeonButton(
                    text: S.bookBuddyGen10Mcq,
                    height: 46,
                    gradient: AppColors.goldGradient,
                    glowColor: AppColors.neonGold,
                    textStyle: const TextStyle(
                      color: AppColors.bgDark,
                      fontSize: 13,
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
            fontSize: 15,
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
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.neonCyan.withValues(alpha: 0.14),
                  ),
                  child: const Icon(
                    Icons.menu_book_rounded,
                    color: AppColors.neonCyan,
                    size: 19,
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
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13.5,
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
                          fontSize: 11.5,
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
                    size: 19,
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
