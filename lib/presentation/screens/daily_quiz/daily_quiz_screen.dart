import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/models/question_model.dart';
import '../../../data/providers/quiz_provider.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/quiz_language_pills.dart';
import '../quiz_result/quiz_result_screen.dart';
import '../../../l10n/app_strings.dart';
import 'daily_quiz_loading_card.dart';

class DailyQuizScreen extends StatelessWidget {
  const DailyQuizScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final quiz = context.watch<QuizProvider>();

    if (quiz.isQuizCompleted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const QuizResultScreen()),
        );
      });
    }

    final currentQ = quiz.currentQuestion;

    final screen = Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Daily Live Quiz',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            // Which set this is, so a chapter run never feels like it came
            // from nowhere.
            if (quiz.setCount > 1)
              Text(
                S.setsSetOf(n: quiz.setNumber, total: quiz.setCount),
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary),
              ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => _showExitDialog(context),
        ),
        actions: [
          if (currentQ != null) ...[
          // Active Boosters Indicator
          if (quiz.doublePointsActive)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.neonPink.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.neonPink.withValues(alpha: 0.5)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.double_arrow_rounded, color: AppColors.neonPink, size: 14),
                  SizedBox(width: 4),
                  Text('2x', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: AppColors.neonPink)),
                ],
              ),
            ),
          if (quiz.extraLifeAvailable && !quiz.extraLifeUsed)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.neonRed.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.neonRed.withValues(alpha: 0.5)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.favorite_rounded, color: AppColors.neonRed, size: 14),
                  SizedBox(width: 4),
                  Text('+1', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: AppColors.neonRed)),
                ],
              ),
            ),
          // Read the question in another language without leaving the quiz.
          QuizLanguagePills(
            available: quiz.availableLanguages,
            selected: quiz.displayLanguage,
            onSelected: quiz.setDisplayLanguage,
          ),

          // Score
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.neonGold.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.neonGold.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                const Icon(Icons.stars, color: AppColors.neonGold, size: 16),
                const SizedBox(width: 4),
                Text(
                  '${quiz.score} pts',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.neonGold,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          ],
        ],
      ),
      body: currentQ == null
          ? Center(
              child: quiz.hasNoQuestions
                  ? const Padding(
                      padding: EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.inbox_rounded,
                              size: 44, color: AppColors.textMuted),
                          SizedBox(height: 14),
                          Text(
                            'No questions available',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: Colors.white),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'This question bank is empty. Please try another '
                            'chapter or check back later.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 12, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    )
                  : const DailyQuizLoadingCard(),
            )
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Practice runs credit nothing, and the player must know
                    // that before they spend ten minutes on one.
                    if (quiz.isPractice) ...[
                      _practiceBanner(),
                      const SizedBox(height: 10),
                    ],

                    // Top Progress & Timer
                    _buildProgressAndTimer(quiz),
                    const SizedBox(height: 14),

                    // Lifelines Bar (scrollable)
                    _buildLifelines(context, quiz),
                    const SizedBox(height: 14),

                    // Hint Display (if used)
                    if (quiz.currentHint != null) ...[
                      _buildHintCard(quiz.currentHint!),
                      const SizedBox(height: 10),
                    ],

                    // Audience Poll Display (if used)
                    if (quiz.audiencePollResults != null) ...[
                      _buildAudiencePollCard(quiz),
                      const SizedBox(height: 10),
                    ],

                    // Question Card
                    _buildQuestionCard(context, currentQ),
                    const SizedBox(height: 18),

                    // 4 Options
                    Expanded(
                      child: ListView.builder(
                        physics: const BouncingScrollPhysics(),
                        itemCount: currentQ.options.length,
                        itemBuilder: (context, index) {
                          return _buildOptionButton(context, quiz, currentQ, index);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _showExitDialog(context);
      },
      child: screen,
    );
  }

  Widget _practiceBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: AppColors.neonGold.withValues(alpha: 0.12),
        border: Border.all(color: AppColors.neonGold.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.refresh_rounded,
              size: 15, color: AppColors.neonGold),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              S.setsPracticeBanner,
              style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.neonGold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressAndTimer(QuizProvider quiz) {
    final timerPercent = quiz.questionTimeSec == 0
        ? 0.0
        : quiz.secondsRemaining / quiz.questionTimeSec;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Question ${quiz.currentIndex + 1} of ${quiz.questions.length}',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
            Row(
              children: [
                Icon(
                  Icons.timer,
                  size: 16,
                  color: quiz.secondsRemaining <= 5 ? AppColors.neonRed : AppColors.neonCyan,
                ),
                const SizedBox(width: 4),
                Text(
                  '${quiz.secondsRemaining}s',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: quiz.secondsRemaining <= 5 ? AppColors.neonRed : AppColors.neonCyan,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: timerPercent,
            minHeight: 6,
            backgroundColor: Colors.white.withValues(alpha: 0.1),
            valueColor: AlwaysStoppedAnimation<Color>(
              quiz.secondsRemaining <= 5 ? AppColors.neonRed : AppColors.neonCyan,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLifelines(BuildContext context, QuizProvider quiz) {
    return SizedBox(
      height: 50,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        children: [
          // 50-50
          _buildLifelineBtn(
            label: '50:50',
            icon: Icons.filter_2,
            count: quiz.fiftyFiftyStock,
            isUsed: quiz.fiftyFiftyUsed,
            color: AppColors.neonCyan,
            onTap: () => _useFiftyFifty(context, quiz),
          ),
          const SizedBox(width: 8),

          // Freeze Time
          _buildLifelineBtn(
            label: '+10s',
            icon: Icons.ac_unit,
            count: quiz.freezeTimeStock,
            isUsed: quiz.freezeUsed,
            color: AppColors.neonCyan,
            onTap: () => _useFreezeTime(context, quiz),
          ),
          const SizedBox(width: 8),

          // Skip Question
          _buildLifelineBtn(
            label: 'Skip',
            icon: Icons.skip_next_rounded,
            count: quiz.skipQuestionStock,
            isUsed: quiz.skipUsed,
            color: AppColors.neonPurple,
            onTap: () => _useSkipQuestion(context, quiz),
          ),
          const SizedBox(width: 8),

          // Hint Reveal
          _buildLifelineBtn(
            label: 'Hint',
            icon: Icons.lightbulb_rounded,
            count: quiz.hintRevealStock,
            isUsed: quiz.hintUsed,
            color: AppColors.neonGold,
            onTap: () => _useHintReveal(context, quiz),
          ),
          const SizedBox(width: 8),

          // Audience Poll
          _buildLifelineBtn(
            label: 'Poll',
            icon: Icons.people_rounded,
            count: quiz.audiencePollStock,
            isUsed: quiz.audienceUsed,
            color: AppColors.neonGreen,
            onTap: () => _useAudiencePoll(context, quiz),
          ),
        ],
      ),
    );
  }

  Widget _buildLifelineBtn({
    required String label,
    required IconData icon,
    required int count,
    required bool isUsed,
    required Color color,
    required VoidCallback onTap,
  }) {
    final bool outOfStock = count <= 0;
    final bool disabled = isUsed || outOfStock;

    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: disabled
              ? Colors.white.withValues(alpha: 0.03)
              : color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: disabled
                ? Colors.white.withValues(alpha: 0.06)
                : color.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: disabled ? AppColors.textMuted : color,
            ),
            const SizedBox(width: 6),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: disabled ? AppColors.textMuted : AppColors.textPrimary,
                  ),
                ),
                Text(
                  isUsed ? 'Used' : 'x$count',
                  style: TextStyle(
                    fontSize: 9,
                    color: disabled ? AppColors.textMuted : color,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHintCard(String hint) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.neonGold.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.neonGold.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.lightbulb_rounded, color: AppColors.neonGold, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'HINT',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: AppColors.neonGold,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hint,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAudiencePollCard(QuizProvider quiz) {
    final results = quiz.audiencePollResults!;
    final options = quiz.currentQuestion!.options;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.neonGreen.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.neonGreen.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.people_rounded, color: AppColors.neonGreen, size: 18),
              SizedBox(width: 8),
              Text(
                'AUDIENCE POLL',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: AppColors.neonGreen,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...List.generate(options.length, (index) {
            final percent = results[index] ?? 0;
            final letter = String.fromCharCode(65 + index);
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    child: Text(
                      '$letter.',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: percent / 100,
                        minHeight: 16,
                        backgroundColor: Colors.white.withValues(alpha: 0.1),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          AppColors.neonGreen.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 36,
                    child: Text(
                      '$percent%',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppColors.neonGreen,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // Lifeline Actions
  void _useFiftyFifty(BuildContext context, QuizProvider quiz) {
    if (quiz.useFiftyFifty()) return;

    final message = quiz.fiftyFiftyStock <= 0
        ? S.quizNoFiftyFifty
        : quiz.fiftyFiftyUsed
            ? S.quizFiftyFiftyUsed
            : S.quizFiftyFiftyBlocked;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _useFreezeTime(BuildContext context, QuizProvider quiz) {
    if (quiz.useFreezeTime()) return;

    final message = quiz.freezeTimeStock <= 0
        ? S.quizNoFreeze
        : quiz.freezeUsed
            ? S.quizFreezeUsed
            : S.quizFreezeBlocked;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _useSkipQuestion(BuildContext context, QuizProvider quiz) {
    if (quiz.useSkipQuestion()) return;

    final message = quiz.skipQuestionStock <= 0
        ? S.quizNoSkip
        : quiz.skipUsed
            ? S.quizSkipUsed
            : S.quizSkipBlocked;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _useHintReveal(BuildContext context, QuizProvider quiz) {
    if (quiz.useHintReveal()) return;

    final message = quiz.hintRevealStock <= 0
        ? S.quizNoHint
        : quiz.hintUsed
            ? S.quizHintUsed
            : S.quizHintBlocked;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _useAudiencePoll(BuildContext context, QuizProvider quiz) {
    if (quiz.useAudiencePoll()) return;

    final message = quiz.audiencePollStock <= 0
        ? S.quizNoPoll
        : quiz.audienceUsed
            ? S.quizPollUsed
            : S.quizPollBlocked;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildQuestionCard(BuildContext context, QuestionModel question) {
    final language = context.watch<QuizProvider>().displayLanguage;

    // Board students revise in English terminology even when reading Bangla or
    // Hindi, so the English stem stays visible as a secondary line. Reading in
    // English already, it would just repeat itself.
    final primary = question.questionIn(language);
    final secondary = language == 'en' ? null : question.questionIn('en');

    return GlassCard(
      borderRadius: 22,
      borderColor: AppColors.neonPurple.withValues(alpha: 0.3),
      backgroundColor: const Color(0x331E1B4B),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            primary,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
              height: 1.35,
            ),
          ),
          if (secondary != null && secondary != primary) ...[
            const SizedBox(height: 8),
            Text(
              secondary,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOptionButton(
    BuildContext context,
    QuizProvider quiz,
    QuestionModel question,
    int index,
  ) {
    final isDisabled = quiz.disabledOptionIndices.contains(index);
    if (isDisabled) {
      return const SizedBox.shrink();
    }

    final isSelected = quiz.selectedOptionIndex == index;
    final isAnswerSubmitted = quiz.isAnswerSubmitted;
    final isCorrect = question.correctIndex == index;

    Color borderColor = Colors.white.withValues(alpha: 0.12);
    Color bgColor = Colors.white.withValues(alpha: 0.05);
    Color textColor = AppColors.textPrimary;
    Widget? trailingIcon;

    if (isAnswerSubmitted) {
      if (isCorrect) {
        borderColor = AppColors.neonGreen;
        bgColor = AppColors.neonGreen.withValues(alpha: 0.2);
        trailingIcon = const Icon(Icons.check_circle, color: AppColors.neonGreen);
      } else if (isSelected) {
        borderColor = AppColors.neonRed;
        bgColor = AppColors.neonRed.withValues(alpha: 0.2);
        trailingIcon = const Icon(Icons.cancel, color: AppColors.neonRed);
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: GestureDetector(
        onTap: () => quiz.selectOption(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor, width: 1.5),
            boxShadow: isAnswerSubmitted && (isCorrect || isSelected)
                ? [
                    BoxShadow(
                      color: (isCorrect ? AppColors.neonGreen : AppColors.neonRed).withValues(alpha: 0.3),
                      blurRadius: 10,
                    )
                  ]
                : null,
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
                child: Center(
                  child: Text(
                    String.fromCharCode(65 + index), // A, B, C, D
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: AppColors.neonCyan,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  question.optionsIn(quiz.displayLanguage)[index],
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
              ),
              if (trailingIcon != null) trailingIcon,
            ],
          ),
        ),
      ),
    );
  }

  void _showExitDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: Text(S.quizQuitTitle),
        content: Text(S.quizQuitBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(S.cancel, style: const TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.neonRed),
            onPressed: () {
              context.read<QuizProvider>().abandonQuiz();
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: Text(S.quizQuit, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
