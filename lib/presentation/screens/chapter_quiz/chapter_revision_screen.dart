import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/chapter_model.dart';
import '../../../data/models/chapter_set_progress.dart';
import '../../../data/models/question_model.dart';
import '../../../data/repositories/quiz_repository.dart';
import '../../../l10n/app_strings.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/quiz_language_pills.dart';

/// The questions one revision screen shows.
///
/// [setIndex] == null revises the whole chapter (authored order); any other
/// value is that set's positional slice — the same boundaries the quiz
/// plays, so "Set 2" always means the same ten questions everywhere.
@visibleForTesting
List<QuestionModel> revisionSlice(List<QuestionModel> all, {int? setIndex}) {
  if (setIndex == null) return all;
  final start = setStartIndex(setIndex);
  if (start >= all.length) return const [];
  return all.sublist(
    start,
    (start + setLengthFor(all.length, setIndex)).clamp(0, all.length),
  );
}

/// Reading-only revision of one chapter set — or of the whole chapter when
/// [setIndex] is omitted — for মুখস্থ.
///
/// Shows every question of the selection with all options, the correct answer
/// highlighted and the explanation underneath — no timer, no scoring, no
/// rewards. It deliberately never touches [QuizProvider]: opening revision
/// cannot disturb an in-progress run, and it cannot farm anything.
///
/// Revision is never locked behind set progress: reading ahead is studying,
/// not playing, so the whole chapter is open from day one.
///
/// Questions load through [QuizRepository.getChapterQuestions], the exact
/// same path the quiz uses, so a chapter or question added to the bundled
/// assets (or by an admin) appears here with no extra wiring.
class ChapterRevisionScreen extends StatefulWidget {
  final ChapterModel chapter;
  final String categoryTitle;
  final int? setIndex;
  final int setCount;
  final Color accent;

  const ChapterRevisionScreen({
    super.key,
    required this.chapter,
    required this.categoryTitle,
    this.setIndex,
    required this.setCount,
    this.accent = AppColors.neonCyan,
  });

  @override
  State<ChapterRevisionScreen> createState() => _ChapterRevisionScreenState();
}

class _ChapterRevisionScreenState extends State<ChapterRevisionScreen> {
  final _repository = QuizRepository();

  bool _loading = true;
  List<QuestionModel> _questions = const [];
  late String _language = S.code;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await _repository.getChapterQuestions(
      widget.chapter.jsonFile,
      chapterId: widget.chapter.chapterId,
    );
    if (!mounted) return;
    setState(() {
      // Authored order, never shuffled: stable numbering is what makes a
      // set re-readable for memorisation.
      _questions = revisionSlice(all, setIndex: widget.setIndex);
      _loading = false;
    });
  }

  /// Languages the loaded set actually carries, so the pills never offer a
  /// tab that would silently fall back to English.
  List<String> get _availableLanguages {
    final codes = <String>{};
    for (final q in _questions) {
      codes.addAll(q.questionText.languages);
    }
    return kSupportedLanguageCodes.where(codes.contains).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.chapter.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
            Text(
              widget.setIndex == null
                  ? S.reviseAllSubtitle
                  : S.setsSetOf(
                    n: widget.setIndex! + 1,
                    total: widget.setCount,
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        actions: [
          QuizLanguagePills(
            available: _availableLanguages,
            selected: _language,
            onSelected: (code) => setState(() => _language = code),
          ),
        ],
      ),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : _questions.isEmpty
              ? _emptyState()
              : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                children: [
                  _noteCard(),
                  const SizedBox(height: 12),
                  for (var i = 0; i < _questions.length; i++) ...[
                    // Whole-chapter mode: a light "Set N" marker at every
                    // boundary the quiz plays, so a 500-question chapter stays
                    // navigable while the numbering stays continuous.
                    if (widget.setIndex == null &&
                        i > 0 &&
                        i % kQuestionsPerSet == 0) ...[
                      _setDivider(i ~/ kQuestionsPerSet + 1),
                      const SizedBox(height: 12),
                    ],
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _RevisionCard(
                        number: i + 1,
                        question: _questions[i],
                        language: _language,
                      ),
                    ),
                  ],
                ],
              ),
    );
  }

  /// "Set N" separator between sets in whole-chapter mode.
  Widget _setDivider(int setNumber) {
    return Row(
      children: [
        const Expanded(child: Divider(color: Colors.white12, height: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            S.setsSet(n: setNumber),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppColors.textMuted,
            ),
          ),
        ),
        const Expanded(child: Divider(color: Colors.white12, height: 1)),
      ],
    );
  }

  Widget _noteCard() {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Row(
        children: [
          const Icon(
            Icons.menu_book_rounded,
            size: 13,
            color: AppColors.textMuted,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              '${S.setsQuestions(n: _questions.length)} · ${S.reviseNote}',
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.inbox_rounded,
              size: 46,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: 14),
            Text(
              S.setsEmpty,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              S.setsEmptyBody,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RevisionCard extends StatelessWidget {
  final int number;
  final QuestionModel question;
  final String language;

  const _RevisionCard({
    required this.number,
    required this.question,
    required this.language,
  });

  @override
  Widget build(BuildContext context) {
    final options = question.optionsIn(language);
    final explanation = question.explanationIn(language);

    return GlassCard(
      borderRadius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: AppColors.neonGold.withValues(alpha: 0.16),
              border: Border.all(
                color: AppColors.neonGold.withValues(alpha: 0.45),
              ),
            ),
            child: Text(
              S.reviewQuestionNo(n: number),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: AppColors.neonGold,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            question.questionIn(language),
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < options.length; i++)
            _optionRow(options[i], isCorrect: i == question.correctIndex),
          if (explanation.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              S.reviewExplanation,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              explanation,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _optionRow(String text, {required bool isCorrect}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color:
            isCorrect
                ? AppColors.neonGreen.withValues(alpha: 0.12)
                : Colors.white.withValues(alpha: 0.04),
        border: Border.all(
          color:
              isCorrect
                  ? AppColors.neonGreen.withValues(alpha: 0.65)
                  : Colors.white.withValues(alpha: 0.10),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: isCorrect ? FontWeight.w800 : FontWeight.w500,
                color: isCorrect ? Colors.white : AppColors.textSecondary,
                height: 1.3,
              ),
            ),
          ),
          if (isCorrect)
            const Icon(
              Icons.check_circle_rounded,
              size: 17,
              color: AppColors.neonGreen,
            ),
        ],
      ),
    );
  }
}
