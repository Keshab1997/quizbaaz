import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/chapter_model.dart';
import '../../../data/models/chapter_set_progress.dart';
import '../../../data/providers/quiz_provider.dart';
import '../../../data/repositories/quiz_repository.dart';
import '../../../data/services/haptic_service.dart';
import '../../../data/services/hive_service.dart';
import '../../../data/services/sound_service.dart';
import '../../../l10n/app_strings.dart';
import '../../widgets/glass_card.dart';
import '../daily_quiz/daily_quiz_screen.dart';

/// Sets of a chapter, and the history of the ones already cleared.
///
/// A chapter used to serve its whole bank as one quiz. That was fine when a
/// chapter had eight questions; the admin panel is built to append forever, so
/// left alone it becomes a 200-question sitting nobody finishes.
///
/// Ten at a time gives the student something completable, a visible finish
/// line, and a reason to come back tomorrow. **Continue** always plays the
/// first set they have not cleared, so they never have to remember where they
/// were.
///
/// The history tab is the other half of that: a cleared set stays available to
/// replay for revision, and a replay credits nothing — no coins, no score, no
/// leaderboard. Revision must never be a way to farm rewards, and it must
/// never feel like it costs something either.
class ChapterSetsScreen extends StatefulWidget {
  final ChapterModel chapter;
  final String categoryTitle;
  final String? categoryTitleBn;
  final Color accent;

  const ChapterSetsScreen({
    super.key,
    required this.chapter,
    required this.categoryTitle,
    this.categoryTitleBn,
    this.accent = AppColors.neonCyan,
  });

  @override
  State<ChapterSetsScreen> createState() => _ChapterSetsScreenState();
}

class _ChapterSetsScreenState extends State<ChapterSetsScreen>
    with SingleTickerProviderStateMixin {
  final _repository = QuizRepository();
  late final TabController _tabs;

  int _questionCount = 0;
  bool _loading = true;
  Map<int, ChapterSetProgress> _progress = {};

  String get _chapterId => widget.chapter.chapterId;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    // The real count, not chapters_list.json — that only knows the bundled
    // questions and would hide every set an admin added.
    final questions = await _repository.getChapterQuestions(
      widget.chapter.jsonFile,
      chapterId: _chapterId,
    );

    if (!mounted) return;
    setState(() {
      _questionCount = questions.length;
      _progress = {
        for (final entry in HiveService.chapterSetsFor(_chapterId))
          entry.setIndex: entry,
      };
      _loading = false;
    });
  }

  int get _setCount => setCountFor(_questionCount);

  /// First set not yet cleared, or null when the chapter is finished.
  int? get _nextSet => HiveService.nextUnplayedSet(_chapterId, _setCount);

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
              widget.categoryTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: widget.accent,
          labelColor: widget.accent,
          unselectedLabelColor: AppColors.textSecondary,
          labelStyle:
              const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
          tabs: [
            Tab(text: S.setsTitle),
            Tab(text: S.setsHistoryTab),
          ],
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.neonCyan))
          : TabBarView(
              controller: _tabs,
              children: [_setsTab(), _historyTab()],
            ),
    );
  }

  // ------------------------------------------------------------ sets  tab --

  Widget _setsTab() {
    if (_setCount == 0) return _emptyChapter();

    final next = _nextSet;

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.neonCyan,
      backgroundColor: AppColors.surfaceElevated,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          _summaryCard(next),
          const SizedBox(height: 16),
          for (var i = 0; i < _setCount; i++) _setCard(i, next),
        ],
      ),
    );
  }

  Widget _summaryCard(int? next) {
    final cleared = _progress.length;
    final allDone = next == null;

    return GlassCard(
      borderRadius: 20,
      padding: const EdgeInsets.all(18),
      borderColor: widget.accent.withValues(alpha: 0.3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  allDone
                      ? S.setsAllDone
                      : S.setsSetOf(n: (next) + 1, total: _setCount),
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: Colors.white),
                ),
              ),
              Text(
                '$cleared / $_setCount',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: widget.accent),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _setCount == 0 ? 0 : cleared / _setCount,
              minHeight: 7,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              valueColor: AlwaysStoppedAnimation<Color>(widget.accent),
            ),
          ),
          const SizedBox(height: 14),
          if (allDone)
            Text(
              S.setsAllDoneBody,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary, height: 1.4),
            )
          else
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.accent,
                  foregroundColor: AppColors.bgDark,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () => _play(next, practice: false),
                icon: const Icon(Icons.play_arrow_rounded, size: 22),
                label: Text(
                  _progress.isEmpty
                      ? S.setsStart(n: next + 1)
                      : S.setsContinue(n: next + 1),
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 14),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _setCard(int index, int? next) {
    final done = _progress[index];
    final isNext = index == next;
    // Only one set ahead of the frontier is reachable, so progress through a
    // chapter stays ordered instead of the student cherry-picking set 7.
    final locked = done == null && !isNext;
    final length = setLengthFor(_questionCount, index);

    final colour = done != null
        ? AppColors.neonGreen
        : isNext
            ? widget.accent
            : AppColors.textMuted;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        borderRadius: 16,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        borderColor: isNext ? widget.accent.withValues(alpha: 0.45) : null,
        // A finished set replayed from the list is practice too, otherwise the
        // reward guard in QuizProvider could be bypassed by tapping the row
        // instead of the Retry chip.
        onTap: locked ? null : () => _play(index, practice: done != null),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: colour.withValues(alpha: 0.16),
                border: Border.all(color: colour.withValues(alpha: 0.45)),
              ),
              child: Center(
                child: locked
                    ? const Icon(Icons.lock_rounded,
                        size: 18, color: AppColors.textMuted)
                    : done != null
                        ? Icon(
                            done.isPerfect
                                ? Icons.workspace_premium_rounded
                                : Icons.check_rounded,
                            size: 20,
                            color: colour)
                        : Text('${index + 1}',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                                color: colour)),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    S.setsSet(n: index + 1),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: locked ? AppColors.textMuted : Colors.white,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    locked
                        ? S.setsLocked(n: index)
                        : done != null
                            ? '${S.setsCleared} · '
                                '${S.setsBest(correct: done.bestCorrect, total: done.totalQuestions)}'
                            : S.setsQuestions(n: length),
                    style: TextStyle(
                      fontSize: 11.5,
                      color: done != null
                          ? AppColors.neonGreen
                          : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (done != null)
              _retryChip(index)
            else if (isNext)
              Icon(Icons.play_circle_fill_rounded,
                  size: 26, color: widget.accent),
          ],
        ),
      ),
    );
  }

  Widget _retryChip(int index) {
    return TextButton.icon(
      // Retry means "play the finished set again" — practice, so it neither
      // pays out again nor spends power-ups.
      onPressed: () => _play(index, practice: true),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        minimumSize: const Size(0, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: const Icon(Icons.refresh_rounded,
          size: 15, color: AppColors.textSecondary),
      label: Text(S.setsRetry,
          style:
              const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
    );
  }

  Widget _emptyChapter() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inbox_rounded, size: 46, color: AppColors.textMuted),
            const SizedBox(height: 14),
            Text(S.setsEmpty,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
            const SizedBox(height: 6),
            Text(S.setsEmptyBody,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    height: 1.4)),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------- history  tab --

  Widget _historyTab() {
    final cleared = _progress.values.toList()
      ..sort((a, b) => b.lastPlayedAt.compareTo(a.lastPlayedAt));

    if (cleared.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.history_rounded,
                  size: 46, color: AppColors.textMuted),
              const SizedBox(height: 14),
              Text(S.setsNoHistory,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
              const SizedBox(height: 6),
              Text(S.setsNoHistoryBody,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      height: 1.4)),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12, left: 2),
          child: Row(
            children: [
              const Icon(Icons.info_outline_rounded,
                  size: 13, color: AppColors.textMuted),
              const SizedBox(width: 7),
              Expanded(
                child: Text(S.setsPracticeNote,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textMuted)),
              ),
            ],
          ),
        ),
        for (final entry in cleared) _historyCard(entry),
      ],
    );
  }

  Widget _historyCard(ChapterSetProgress entry) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        borderRadius: 16,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            SizedBox(
              width: 46,
              child: Column(
                children: [
                  Text('${entry.accuracyPercent}%',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: entry.isPerfect
                            ? AppColors.neonGold
                            : AppColors.neonGreen,
                      )),
                  const SizedBox(height: 2),
                  Text(S.accuracy,
                      style: const TextStyle(
                          fontSize: 9, color: AppColors.textMuted)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(S.setsSet(n: entry.setNumber),
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: Colors.white)),
                      if (entry.isPerfect) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.workspace_premium_rounded,
                            size: 14, color: AppColors.neonGold),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${S.setsBest(correct: entry.bestCorrect, total: entry.totalQuestions)}'
                    ' · ${S.setsAttempts(n: entry.attempts)}',
                    style: const TextStyle(
                        fontSize: 11.5, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    S.setsPlayedOn(date: _formatDate(entry.lastPlayedAt)),
                    style: const TextStyle(
                        fontSize: 10.5, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 34),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                side: BorderSide(color: widget.accent.withValues(alpha: 0.5)),
              ),
              onPressed: () => _play(entry.setIndex, practice: true),
              icon: Icon(Icons.refresh_rounded, size: 15, color: widget.accent),
              label: Text(S.setsRetry,
                  style: TextStyle(fontSize: 11.5, color: widget.accent)),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inHours < 24) return S.today;
    if (diff.inHours < 48) return S.yesterday;
    if (diff.inDays < 7) return S.daysAgo(n: diff.inDays);
    return '${date.day} ${S.monthName(date.month)} ${date.year}';
  }

  // ------------------------------------------------------------------ play --

  Future<void> _play(int setIndex, {required bool practice}) async {
    SoundService.instance.play('ui_whoosh');
    Haptics.tap();
    await context.read<QuizProvider>().startChapterQuiz(
          widget.chapter.jsonFile,
          chapterId: _chapterId,
          categoryTitle: widget.categoryTitle,
          categoryTitleBn: widget.categoryTitleBn,
          chapterTitle: widget.chapter.title,
          chapterTitleBn: widget.chapter.titleText.resolve('bn'),
          setIndex: setIndex,
          practice: practice,
        );

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DailyQuizScreen()),
    );

    // Coming back from a run, the set may now be cleared and the next unlocked.
    if (mounted) _load();
  }
}
