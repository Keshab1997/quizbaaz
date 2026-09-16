import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/chapter_model.dart';
import '../../../data/models/localized_text.dart';
import '../../../data/models/question_model.dart';
import '../../../data/models/question_set.dart';
import '../../../data/providers/auth_provider.dart';
import '../../../data/repositories/quiz_repository.dart';
import '../../../data/services/ai_question_generator.dart';
import '../../../data/services/question_bank_service.dart';
import '../../../data/services/question_fingerprint.dart';
import '../../../data/services/question_prompt_builder.dart';
import '../../../data/services/question_validator.dart';
import '../../widgets/glass_card.dart';
import 'ai_generation_review_screen.dart';
import 'widgets/trilingual_field.dart';

/// The question bank for one chapter.
///
/// Lists what is already there — the admin's first question is always "what do
/// I already have?" — and offers the two ways to add: by hand, or by
/// generating a batch.
///
/// Questions are shown in consecutive sets of ten. An admin can still delete
/// one question, or permanently remove the exact questions in one set after a
/// count-specific confirmation; there is no "clear chapter" action.
class QuestionManagerScreen extends StatefulWidget {
  final String categoryId;

  /// Subject name in English — the generator puts it in the prompt, and it is
  /// what decides whether answer verification defaults on.
  final String subjectName;

  final ChapterModel chapter;

  const QuestionManagerScreen({
    super.key,
    required this.categoryId,
    required this.subjectName,
    required this.chapter,
  });

  @override
  State<QuestionManagerScreen> createState() => _QuestionManagerScreenState();
}

enum _Filter { all, needsTranslation, ai, manual }

class _QuestionManagerScreenState extends State<QuestionManagerScreen> {
  final _bank = QuestionBankService();
  final _repository = QuizRepository();

  List<QuestionModel> _questions = [];
  Map<String, ValidationResult> _validation = {};
  bool _loading = true;
  String _search = '';
  _Filter _filter = _Filter.all;

  String get _chapterId => widget.chapter.chapterId;

  String get _actorUid =>
      context.read<AuthProvider>().firebaseUser?.uid ?? 'unknown';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    // Without this the "47 -> 55 questions" bar reappears over the chapter
    // list, and its Undo would act on a screen the admin has already left.
    _messenger?.hideCurrentSnackBar();
    super.dispose();
  }

  ScaffoldMessengerState? _messenger;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Captured here because dispose() must not look up an inherited widget.
    _messenger = ScaffoldMessenger.of(context);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    List<QuestionModel> questions;
    try {
      questions = await _bank.fetchQuestions(_chapterId);
    } catch (e) {
      questions = [];
      if (mounted) _toast('Could not load questions: $e', error: true);
    }

    // Validate what is already stored, so pre-existing gaps are visible rather
    // than only being caught on the way in.
    final results = QuestionValidator.validateBatch(questions);

    if (!mounted) return;
    setState(() {
      _questions = questions;
      _validation = {
        for (var i = 0; i < questions.length; i++) questions[i].id: results[i]
      };
      _loading = false;
    });
  }

  bool _matchesCurrentFilter(QuestionModel question) {
    final needle = _search.trim().toLowerCase();
    if (needle.isNotEmpty) {
      final haystack = [
        question.id,
        ...question.questionText.toJson().values,
        for (final option in question.optionTexts) ...option.toJson().values,
      ].join(' ').toLowerCase();
      if (!haystack.contains(needle)) return false;
    }

    switch (_filter) {
      case _Filter.needsTranslation:
        return !question.isFullyTranslated;
      case _Filter.ai:
      case _Filter.manual:
        // Provenance lives on the Firestore document, not the model; until
        // that is surfaced these behave as "all". Kept so the chips are in
        // place for the generator work.
        return true;
      case _Filter.all:
        return true;
    }
  }

  List<QuestionSet> get _visibleSets => QuestionSet.fromQuestions(_questions)
      .where((set) => set.questions.any(_matchesCurrentFilter))
      .toList();

  @override
  Widget build(BuildContext context) {
    final visibleSets = _visibleSets;
    final untranslated =
        _questions.where((q) => !q.isFullyTranslated).length;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Question Bank',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Text(
              widget.chapter.titleText.resolve('en'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Import ChatGPT/Gemini JSON',
            icon: const Icon(Icons.code_rounded, color: AppColors.neonGold),
            onPressed: _showJsonImportSheet,
          ),
          IconButton(
            tooltip: 'Reload',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'import_json',
            backgroundColor: AppColors.neonGold,
            foregroundColor: Colors.black,
            onPressed: _showJsonImportSheet,
            icon: const Icon(Icons.content_paste_rounded, size: 19),
            label: const Text('Import JSON'),
          ),
          const SizedBox(height: 10),
          FloatingActionButton.extended(
            heroTag: 'generate',
            backgroundColor: AppColors.neonPurple,
            onPressed: _generateWithAi,
            icon: const Icon(Icons.auto_awesome_rounded, size: 19),
            label: const Text('Generate 10'),
          ),
          const SizedBox(height: 10),
          FloatingActionButton.extended(
            heroTag: 'manual',
            backgroundColor: AppColors.neonCyan,
            foregroundColor: AppColors.bgDark,
            onPressed: () => _editQuestion(null),
            icon: const Icon(Icons.add_rounded, size: 20),
            label: const Text('Add'),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.neonCyan))
          : RefreshIndicator(
              onRefresh: _load,
              color: AppColors.neonCyan,
              backgroundColor: AppColors.surfaceElevated,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 150),
                children: [
                  _header(untranslated),
                  const SizedBox(height: 12),
                  _searchBox(),
                  const SizedBox(height: 10),
                  _filterChips(),
                  const SizedBox(height: 12),
                  if (_questions.isEmpty)
                    _emptyState()
                  else if (visibleSets.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 50),
                      child: Center(
                        child: Text('Nothing matches that filter.',
                            style: TextStyle(color: AppColors.textSecondary)),
                      ),
                    ),
                  for (final set in visibleSets) _questionSetCard(set),
                ],
              ),
            ),
    );
  }

  Widget _header(int untranslated) {
    return GlassCard(
      borderRadius: 18,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                Text('${_questions.length}',
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: AppColors.neonCyan)),
                const Text('Questions',
                    style: TextStyle(
                        fontSize: 10.5, color: AppColors.textSecondary)),
              ],
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Text('$untranslated',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: untranslated == 0
                            ? AppColors.neonGreen
                            : AppColors.neonGold)),
                const Text('Need translation',
                    style: TextStyle(
                        fontSize: 10.5, color: AppColors.textSecondary)),
              ],
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  'q${QuestionFingerprint.nextSequence(_questions.map((q) => q.id)).toString().padLeft(3, '0')}',
                  style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: AppColors.neonPurple),
                ),
                const Text('Next id',
                    style: TextStyle(
                        fontSize: 10.5, color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return const Padding(
      padding: EdgeInsets.only(top: 60),
      child: Column(
        children: [
          Icon(Icons.quiz_outlined, size: 46, color: AppColors.textMuted),
          SizedBox(height: 14),
          Text('No questions in this chapter yet',
              style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.white)),
          SizedBox(height: 6),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Add one by hand, or generate a batch and review it before saving.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12, color: AppColors.textSecondary, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchBox() {
    return TextField(
      style: const TextStyle(color: Colors.white, fontSize: 14),
      onChanged: (v) => setState(() => _search = v),
      decoration: InputDecoration(
        hintText: 'Search question text or id…',
        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
        prefixIcon:
            const Icon(Icons.search_rounded, color: AppColors.textSecondary),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _filterChips() {
    const labels = {
      _Filter.all: 'All',
      _Filter.needsTranslation: 'Needs translation',
      _Filter.ai: 'AI',
      _Filter.manual: 'Manual',
    };

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final entry in labels.entries)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(entry.value,
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: _filter == entry.key
                            ? AppColors.bgDark
                            : AppColors.textSecondary)),
                selected: _filter == entry.key,
                showCheckmark: false,
                backgroundColor: Colors.white.withValues(alpha: 0.05),
                selectedColor: AppColors.neonCyan,
                side: BorderSide(
                    color: _filter == entry.key
                        ? AppColors.neonCyan
                        : Colors.white12),
                onSelected: (_) => setState(() => _filter = entry.key),
              ),
            ),
        ],
      ),
    );
  }

  Widget _questionSetCard(QuestionSet set) {
    final matching = set.questions.where(_matchesCurrentFilter).toList();
    final hasFilteredQuestions = matching.length != set.questions.length;
    final questionLabel = set.questions.length == 1 ? 'question' : 'questions';

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: GlassCard(
        borderRadius: 18,
        padding: EdgeInsets.zero,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 16),
            childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
            iconColor: AppColors.textSecondary,
            collapsedIconColor: AppColors.textSecondary,
            leading: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: AppColors.neonPurple.withValues(alpha: 0.16),
                border: Border.all(
                  color: AppColors.neonPurple.withValues(alpha: 0.42),
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                '${set.number}',
                style: const TextStyle(
                  color: AppColors.neonPurple,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            title: Text(
              'Set ${set.number}',
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            subtitle: Text(
              hasFilteredQuestions
                  ? '${matching.length} matching of ${set.questions.length} $questionLabel'
                  : '${set.questions.length} $questionLabel',
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.textSecondary,
              ),
            ),
            children: [
              for (final question in matching)
                _questionCard(
                  question,
                  set.startIndex + set.questions.indexOf(question) + 1,
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 2, 8, 0),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.neonRed,
                      side: const BorderSide(color: AppColors.neonRed),
                    ),
                    onPressed: () => _confirmDeleteSet(set),
                    icon: const Icon(Icons.delete_sweep_rounded, size: 17),
                    label: Text('Delete all ${set.questions.length}'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _questionCard(QuestionModel question, int position) {
    final result = _validation[question.id];
    final hasIssue = result != null && !result.isClean;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        borderRadius: 16,
        padding: EdgeInsets.zero,
        borderColor: hasIssue
            ? AppColors.neonGold.withValues(alpha: 0.35)
            : null,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 14),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            iconColor: AppColors.textSecondary,
            collapsedIconColor: AppColors.textSecondary,
            title: Text(
              question.questionText.resolve('en'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  height: 1.35),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Row(
                children: [
                  Text('$position · ${question.id}',
                      style: const TextStyle(
                          fontSize: 10.5, color: AppColors.textMuted)),
                  const SizedBox(width: 8),
                  _languageDots(question),
                  if (hasIssue) ...[
                    const SizedBox(width: 8),
                    const Icon(Icons.error_outline_rounded,
                        size: 12, color: AppColors.neonGold),
                  ],
                ],
              ),
            ),
            children: [
              for (final code in ['en', 'bn', 'hi'])
                _languageBlock(question, code),
              if (hasIssue) ...[
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: AppColors.neonGold.withValues(alpha: 0.1),
                  ),
                  child: Text(result.summary,
                      style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.neonGold,
                          height: 1.35)),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () => _editQuestion(question),
                    icon: const Icon(Icons.edit_rounded,
                        size: 15, color: AppColors.neonCyan),
                    label: const Text('Edit',
                        style:
                            TextStyle(fontSize: 12, color: AppColors.neonCyan)),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => _confirmDelete(question),
                    icon: const Icon(Icons.delete_outline_rounded,
                        size: 15, color: AppColors.neonRed),
                    label: const Text('Delete',
                        style:
                            TextStyle(fontSize: 12, color: AppColors.neonRed)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _languageDots(QuestionModel question) {
    return Row(
      children: [
        for (final code in ['en', 'bn', 'hi'])
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Text(
              code.toUpperCase(),
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w900,
                color: question.questionText.has(code) &&
                        question.optionTexts.every((o) => o.has(code))
                    ? AppColors.neonGreen
                    : AppColors.textMuted.withValues(alpha: 0.5),
              ),
            ),
          ),
      ],
    );
  }

  Widget _languageBlock(QuestionModel question, String code) {
    final stem = question.questionText.has(code)
        ? question.questionText.resolve(code)
        : null;
    if (stem == null) return const SizedBox.shrink();

    final options = question.optionsIn(code);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(code.toUpperCase(),
              style: const TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.6,
                  color: AppColors.neonCyan)),
          const SizedBox(height: 3),
          Text(stem,
              style: const TextStyle(
                  fontSize: 12.5, color: Colors.white, height: 1.35)),
          const SizedBox(height: 5),
          for (var i = 0; i < options.length; i++)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    i == question.correctIndex
                        ? Icons.check_circle_rounded
                        : Icons.circle_outlined,
                    size: 12,
                    color: i == question.correctIndex
                        ? AppColors.neonGreen
                        : AppColors.textMuted,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      options[i],
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.3,
                        fontWeight: i == question.correctIndex
                            ? FontWeight.w700
                            : FontWeight.w400,
                        color: i == question.correctIndex
                            ? AppColors.neonGreen
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (question.explanationText.has(code)) ...[
            const SizedBox(height: 5),
            Text('💡 ${question.explanationText.resolve(code)}',
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textMuted, height: 1.35)),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- actions --

  /// Opens the review screen, and appends whatever the admin approves.
  ///
  /// The screen returns the approved questions rather than writing them
  /// itself, so there is exactly one place in the app that adds to a bank.
  Future<void> _generateWithAi() async {
    final approved = await Navigator.push<List<QuestionModel>>(
      context,
      MaterialPageRoute(
        builder: (_) => AiGenerationReviewScreen(
          chapter: widget.chapter,
          subjectName: widget.subjectName,
          idPrefix: _slug,
          // Read fresh rather than trusting the loaded list: the sequence must
          // continue past the highest id that exists, not the highest shown.
          startSequence:
              QuestionFingerprint.nextSequence(_questions.map((q) => q.id)),
          existingStems: [
            for (final q in _questions) q.questionText.resolve('en'),
          ],
          existingFingerprints: {
            for (final q in _questions)
              QuestionFingerprint.fingerprint(q.questionText.resolve('en')),
          }..remove(''),
          actorUid: _actorUid,
        ),
      ),
    );

    if (approved == null || approved.isEmpty) return;

    try {
      final result = await _bank.appendQuestions(
        chapterId: _chapterId,
        questions: approved,
        actorUid: _actorUid,
        source: 'ai',
      );
      await _invalidateCaches();
      await _load();
      if (mounted) _showAppendResult(result);
    } catch (e) {
      _toast('Could not save: $e', error: true);
    }
  }

  /// Confirms the append with the before/after count, and offers the undo.
  ///
  /// Showing "47 → 55" rather than "saved" is the point: it is the proof that
  /// the previous 47 are still there.
  void _showAppendResult(AppendResult result) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        // ScaffoldMessenger sits above the Navigator, so a long-lived snackbar
        // rides along to whatever screen the admin opens next. Short, and
        // cleared in dispose.
        duration: const Duration(seconds: 5),
        backgroundColor: AppColors.surfaceElevated,
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded,
                size: 18, color: AppColors.neonGreen),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Added ${result.added} · ${result.countLabel}',
                style: const TextStyle(fontSize: 13, color: Colors.white),
              ),
            ),
          ],
        ),
        action: SnackBarAction(
          label: 'Undo',
          textColor: AppColors.neonGold,
          onPressed: () => _undoBatch(result.batchId),
        ),
      ));
  }

  Future<void> _undoBatch(String batchId) async {
    try {
      final removed = await _bank.undoBatch(
        chapterId: _chapterId,
        batchId: batchId,
        actorUid: _actorUid,
      );
      await _invalidateCaches();
      await _load();
      _toast(removed == 0
          ? 'Nothing to undo — that batch is outside the 24h window.'
          : 'Removed $removed question(s) from that batch.');
    } catch (e) {
      _toast('Undo failed: $e', error: true);
    }
  }

  Future<void> _editQuestion(QuestionModel? existing) async {
    final draft = await showModalBottomSheet<QuestionModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _QuestionSheet(
        existing: existing,
        suggestedId: QuestionFingerprint.buildId(
          _slug,
          QuestionFingerprint.nextSequence(_questions.map((q) => q.id)),
        ),
        existingStems: {
          for (final q in _questions)
            if (existing == null || q.id != existing.id)
              q.id: q.questionText.resolve('en'),
        },
      ),
    );
    if (draft == null) return;

    try {
      if (existing == null) {
        final result = await _bank.appendQuestions(
          chapterId: _chapterId,
          questions: [draft],
          actorUid: _actorUid,
          source: 'manual',
        );
        await _invalidateCaches();
        _toast('Added · ${result.countLabel}');
      } else {
        await _bank.updateQuestion(
          chapterId: _chapterId,
          question: draft,
          actorUid: _actorUid,
        );
        await _invalidateCaches();
        _toast('Updated ${draft.id}');
      }
      await _load();
    } catch (e) {
      _toast('Save failed: $e', error: true);
    }
  }

  /// `math_ch_01` → `math_ch_01`; used as the id prefix for new questions.
  String get _slug => _chapterId;

  /// Drops the cached chapter tree and this chapter's question list.
  ///
  /// Both are Hive-cached with a 15-minute TTL, so without this a student — and
  /// the chapter list one screen back — would keep seeing the old count for up
  /// to a quarter of an hour after an admin adds questions.
  Future<void> _invalidateCaches() => _repository.invalidateQuestionCache(
        jsonFilePath: widget.chapter.jsonFile,
      );

  Future<void> _confirmDeleteSet(QuestionSet set) async {
    final count = set.questions.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgNavy,
        title: Text('Delete Set ${set.number}?',
            style: const TextStyle(fontSize: 16, color: Colors.white)),
        content: Text(
          'This permanently deletes all $count question${count == 1 ? '' : 's'} '
          'in Set ${set.number}. This cannot be undone.',
          style: const TextStyle(
              fontSize: 12.5, color: AppColors.textSecondary, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: AppColors.neonRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete all $count',
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    try {
      final result = await _bank.deleteQuestions(
        chapterId: _chapterId,
        questionIds: set.questions.map((question) => question.id).toList(),
        actorUid: _actorUid,
      );
      await _invalidateCaches();
      _toast(
        'Deleted ${result.deletedCount} question(s) from Set ${set.number}.',
      );
      await _load();
    } catch (e) {
      _toast('Set delete failed: $e', error: true);
    }
  }

  Future<void> _confirmDelete(QuestionModel question) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgNavy,
        title: const Text('Delete this question?',
            style: TextStyle(fontSize: 16, color: Colors.white)),
        content: Text(
          '${question.id}\n\n"${question.questionText.resolve('en')}"\n\n'
          'Only this question is removed. The rest of the chapter is untouched.',
          style: const TextStyle(
              fontSize: 12.5, color: AppColors.textSecondary, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: AppColors.neonRed),
            onPressed: () => Navigator.pop(ctx, true),
            child:
                const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    try {
      await _bank.deleteQuestion(
        chapterId: _chapterId,
        questionId: question.id,
        actorUid: _actorUid,
      );
      await _invalidateCaches();
      _toast('Deleted ${question.id}');
      await _load();
    } catch (e) {
      _toast('Delete failed: $e', error: true);
    }
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: error ? AppColors.neonRed : null,
      ));
  }

  Future<void> _showJsonImportSheet() async {
    final prompt = QuestionPromptBuilder.buildGenerationPrompt(
      chapter: widget.chapter,
      subjectName: widget.subjectName,
      count: 10,
      idPrefix: _slug,
      startSequence: QuestionFingerprint.nextSequence(_questions.map((q) => q.id)),
      existingStems: [for (final q in _questions) q.questionText.resolve('en')],
    );

    final jsonText = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _JsonImportSheet(prompt: prompt),
    );

    if (!mounted) return;
    if (jsonText == null || jsonText.trim().isEmpty) return;

    final parsedQuestions = _parseCustomJsonQuestions(
      jsonText,
      idPrefix: _slug,
      startSequence: QuestionFingerprint.nextSequence(_questions.map((q) => q.id)),
    );

    if (parsedQuestions.isEmpty) {
      _toast('❌ Valid questions could not be parsed from JSON. Please check format.', error: true);
      return;
    }

    final stems = {for (final q in _questions) q.id: q.questionText.resolve('en')};
    final fingerprints = {for (final q in _questions) QuestionFingerprint.fingerprint(q.questionText.resolve('en'))}..remove('');

    final drafts = <GeneratedQuestion>[];
    for (final q in parsedQuestions) {
      final result = QuestionValidator.validate(
        q,
        existingStems: stems,
        existingFingerprints: fingerprints,
      );
      drafts.add(GeneratedQuestion(question: q, validation: result));
    }

    final approved = await Navigator.push<List<QuestionModel>>(
      context,
      MaterialPageRoute(
        builder: (_) => AiGenerationReviewScreen(
          chapter: widget.chapter,
          subjectName: widget.subjectName,
          idPrefix: _slug,
          startSequence: QuestionFingerprint.nextSequence(_questions.map((q) => q.id)),
          existingStems: [for (final q in _questions) q.questionText.resolve('en')],
          existingFingerprints: fingerprints,
          actorUid: _actorUid,
          initialDrafts: drafts,
        ),
      ),
    );

    if (!mounted) return;
    if (approved == null || approved.isEmpty) return;

    try {
      final result = await _bank.appendQuestions(
        chapterId: _chapterId,
        questions: approved,
        actorUid: _actorUid,
        source: 'manual_json_import',
      );
      await _invalidateCaches();
      await _load();
      if (mounted) _showAppendResult(result);
    } catch (e) {
      if (mounted) _toast('Could not save imported questions: $e', error: true);
    }
  }

  static List<QuestionModel> _parseCustomJsonQuestions(
    String raw, {
    required String idPrefix,
    required int startSequence,
  }) {
    var text = raw.trim();
    if (text.startsWith('```')) {
      final firstNewline = text.indexOf('\n');
      if (firstNewline > 0) text = text.substring(firstNewline + 1);
      final closing = text.lastIndexOf('```');
      if (closing >= 0) text = text.substring(0, closing);
      text = text.trim();
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      final start = text.indexOf('[');
      final end = text.lastIndexOf(']');
      if (start >= 0 && end > start) {
        try {
          decoded = jsonDecode(text.substring(start, end + 1));
        } catch (_) {}
      }
    }

    if (decoded == null) {
      final start = text.indexOf('{');
      final end = text.lastIndexOf('}');
      if (start >= 0 && end > start) {
        try {
          decoded = [jsonDecode(text.substring(start, end + 1))];
        } catch (_) {}
      }
    }

    if (decoded == null) return [];

    final list = decoded is List ? decoded : [decoded];
    final questions = <QuestionModel>[];
    var seq = startSequence;

    for (final item in list) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);

      // Question stem
      LocalizedText questionText;
      if (map['question'] is Map) {
        questionText = LocalizedText.fromJson(map['question']);
      } else if (map['question'] is String) {
        questionText = LocalizedText.fromJson({
          'en': map['question'].toString(),
          'bn': map['question_bn']?.toString() ?? '',
          'hi': map['question_hi']?.toString() ?? '',
        });
      } else {
        continue;
      }

      // Options
      List<LocalizedText> optionTexts = [];
      if (map['options'] is List) {
        for (final opt in (map['options'] as List)) {
          if (opt is Map) {
            optionTexts.add(LocalizedText.fromJson(opt));
          } else if (opt != null) {
            optionTexts.add(LocalizedText.fromJson(opt.toString()));
          }
        }
      }

      if (optionTexts.length < 2) continue;

      // Correct index
      int correctIndex = 0;
      if (map['correct_index'] != null) {
        correctIndex = (map['correct_index'] as num?)?.toInt() ?? 0;
      } else if (map['correctIndex'] != null) {
        correctIndex = (map['correctIndex'] as num?)?.toInt() ?? 0;
      } else if (map['correct_answer'] != null) {
        final ansStr = map['correct_answer'].toString().toLowerCase().trim();
        final idx = optionTexts.indexWhere(
            (o) => o.toJson().values.any((val) => val.toLowerCase().trim() == ansStr));
        if (idx >= 0) correctIndex = idx;
      }

      // Explanation
      LocalizedText explanationText = const LocalizedText.empty();
      if (map['explanation'] is Map) {
        explanationText = LocalizedText.fromJson(map['explanation']);
      } else if (map['explanation'] is String) {
        explanationText = LocalizedText.fromJson(map['explanation'].toString());
      }

      // ID
      String id = map['id']?.toString().trim() ?? '';
      if (id.isEmpty) {
        id = QuestionFingerprint.buildId(idPrefix, seq);
      }
      seq++;

      questions.add(QuestionModel(
        id: id,
        questionText: questionText,
        optionTexts: optionTexts,
        correctIndex: correctIndex.clamp(0, optionTexts.length - 1),
        explanationText: explanationText,
        points: (map['points'] as num?)?.toInt() ?? 10,
        timeLimitSec: (map['time_limit_sec'] as num?)?.toInt() ?? 15,
      ));
    }

    return questions;
  }
}

// =========================================================== question sheet ==

/// Add/edit form for a single question.
///
/// Validates with the same [QuestionValidator] the generator uses, live as the
/// admin types, so a hand-written question cannot be saved in a state a
/// generated one would have been rejected for.
class _QuestionSheet extends StatefulWidget {
  final QuestionModel? existing;
  final String suggestedId;
  final Map<String, String> existingStems;

  const _QuestionSheet({
    required this.existing,
    required this.suggestedId,
    required this.existingStems,
  });

  @override
  State<_QuestionSheet> createState() => _QuestionSheetState();
}

class _QuestionSheetState extends State<_QuestionSheet> {
  late final TextEditingController _id;
  late final TextEditingController _points;
  late final TextEditingController _timeLimit;

  late LocalizedText _question;
  late List<LocalizedText> _options;
  late LocalizedText _explanation;
  late int _correctIndex;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _id = TextEditingController(text: e?.id ?? widget.suggestedId);
    _points = TextEditingController(text: '${e?.points ?? 10}');
    _timeLimit = TextEditingController(text: '${e?.timeLimitSec ?? 15}');
    _question = e?.questionText ?? const LocalizedText.empty();
    _options = e?.optionTexts.toList() ??
        List.generate(4, (_) => const LocalizedText.empty());
    _explanation = e?.explanationText ?? const LocalizedText.empty();
    _correctIndex = e?.correctIndex ?? 0;
  }

  @override
  void dispose() {
    _id.dispose();
    _points.dispose();
    _timeLimit.dispose();
    super.dispose();
  }

  QuestionModel get _draft => QuestionModel(
        id: _id.text.trim(),
        questionText: _question,
        optionTexts: _options,
        correctIndex: _correctIndex,
        explanationText: _explanation,
        points: int.tryParse(_points.text.trim()) ?? 10,
        timeLimitSec: int.tryParse(_timeLimit.text.trim()) ?? 15,
      );

  ValidationResult get _result => QuestionValidator.validate(
        _draft,
        existingStems: widget.existingStems,
      );

  @override
  Widget build(BuildContext context) {
    final result = _result;

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.92),
        decoration: const BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.existing == null
                          ? 'New question'
                          : 'Edit ${widget.existing!.id}',
                      style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                          color: Colors.white),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    color: AppColors.textSecondary,
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _idRow(),
                    const SizedBox(height: 16),
                    TrilingualField(
                      label: 'Question',
                      initialValue: _question,
                      minLines: 2,
                      maxLines: 5,
                      onChanged: (v) => setState(() => _question = v),
                    ),
                    const SizedBox(height: 18),
                    const Text('OPTIONS — tap the circle to mark the answer',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                            color: AppColors.textSecondary)),
                    const SizedBox(height: 10),
                    for (var i = 0; i < _options.length; i++) _optionRow(i),
                    const SizedBox(height: 6),
                    _optionButtons(),
                    const SizedBox(height: 18),
                    TrilingualField(
                      label: 'Explanation',
                      initialValue: _explanation,
                      required: false,
                      minLines: 2,
                      maxLines: 4,
                      helperText: 'shown on the review screen',
                      onChanged: (v) => setState(() => _explanation = v),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(child: _numberField(_points, 'Points')),
                        const SizedBox(width: 12),
                        Expanded(
                            child: _numberField(_timeLimit, 'Seconds')),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            _validationBar(result),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
              child: SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: result.isAcceptable
                        ? AppColors.neonCyan
                        : Colors.white12,
                    foregroundColor: result.isAcceptable
                        ? AppColors.bgDark
                        : AppColors.textMuted,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: result.isAcceptable
                      ? () => Navigator.pop(context, _draft)
                      : null,
                  child: const Text('Save question',
                      style: TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 14)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _idRow() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _id,
            enabled: widget.existing == null,
            onChanged: (_) => setState(() {}),
            style: TextStyle(
                color: widget.existing == null
                    ? Colors.white
                    : AppColors.textMuted,
                fontSize: 13),
            decoration: InputDecoration(
              labelText: 'Question id',
              labelStyle: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _optionRow(int index) {
    final isCorrect = index == _correctIndex;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 22),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => setState(() => _correctIndex = index),
              child: Icon(
                isCorrect
                    ? Icons.check_circle_rounded
                    : Icons.circle_outlined,
                size: 22,
                color:
                    isCorrect ? AppColors.neonGreen : AppColors.textMuted,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TrilingualField(
              label: 'Option ${String.fromCharCode(65 + index)}'
                  '${isCorrect ? '  ✓ correct' : ''}',
              initialValue: _options[index],
              minLines: 1,
              maxLines: 2,
              onChanged: (v) => setState(() => _options[index] = v),
            ),
          ),
          if (_options.length > 2)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: IconButton(
                iconSize: 16,
                color: AppColors.textMuted,
                icon: const Icon(Icons.remove_circle_outline_rounded),
                onPressed: () => setState(() {
                  _options.removeAt(index);
                  if (_correctIndex >= _options.length) {
                    _correctIndex = _options.length - 1;
                  }
                }),
              ),
            ),
        ],
      ),
    );
  }

  Widget _optionButtons() {
    if (_options.length >= 6) return const SizedBox.shrink();
    return TextButton.icon(
      onPressed: () =>
          setState(() => _options.add(const LocalizedText.empty())),
      icon: const Icon(Icons.add_rounded, size: 16, color: AppColors.neonCyan),
      label: const Text('Add option',
          style: TextStyle(fontSize: 12, color: AppColors.neonCyan)),
    );
  }

  Widget _numberField(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      onChanged: (_) => setState(() {}),
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle:
            const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  /// Live feedback strip above the save button — the same rules the generator
  /// applies, so the two paths cannot disagree about what is publishable.
  Widget _validationBar(ValidationResult result) {
    if (result.isClean) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(20, 6, 20, 0),
        child: Row(
          children: [
            Icon(Icons.check_circle_rounded,
                size: 14, color: AppColors.neonGreen),
            SizedBox(width: 7),
            Text('Ready to save',
                style: TextStyle(fontSize: 12, color: AppColors.neonGreen)),
          ],
        ),
      );
    }

    final blocking = result.rejections;
    final colour =
        blocking.isEmpty ? AppColors.neonGold : AppColors.neonRed;
    final messages = (blocking.isEmpty ? result.warnings : blocking)
        .map((i) => i.toString())
        .take(3)
        .join(' · ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, size: 14, color: colour),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              result.nearDuplicate != null && blocking.isEmpty
                  ? 'Similar to ${result.nearDuplicate!.questionId} '
                      '(${result.nearDuplicate!.scoreLabel}) · $messages'
                  : messages,
              style: TextStyle(fontSize: 11.5, color: colour, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _JsonImportSheet extends StatefulWidget {
  final String prompt;

  const _JsonImportSheet({required this.prompt});

  @override
  State<_JsonImportSheet> createState() => _JsonImportSheetState();
}

class _JsonImportSheetState extends State<_JsonImportSheet> {
  late final TextEditingController _textController;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController();
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _copyPrompt() {
    Clipboard.setData(ClipboardData(text: widget.prompt));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ AI Prompt copied! Paste into ChatGPT or Gemini.'),
        backgroundColor: AppColors.neonGreen,
      ),
    );
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.isNotEmpty) {
      setState(() {
        _textController.text = data.text!;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('📋 Pasted from clipboard!')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
        decoration: const BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 4),
              child: Row(
                children: [
                  const Icon(Icons.code_rounded, color: AppColors.neonGold, size: 22),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Import JSON / ChatGPT / Gemini',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    color: AppColors.textSecondary,
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Step 1: Prompt
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.neonPurple.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.neonPurple.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.copy_rounded, color: AppColors.neonPurple, size: 18),
                              SizedBox(width: 6),
                              Text(
                                'Step 1: Copy AI Prompt',
                                style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Copy this chapter-specific prompt and paste it into ChatGPT, Gemini, or Claude when API rate limit occurs.',
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.neonPurple,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: _copyPrompt,
                              icon: const Icon(Icons.content_copy_rounded, size: 16),
                              label: const Text('Copy Prompt for ChatGPT / Gemini', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Step 2: Paste JSON
                    const Row(
                      children: [
                        Icon(Icons.content_paste_rounded, color: AppColors.neonGold, size: 18),
                        SizedBox(width: 6),
                        Text(
                          'Step 2: Paste ChatGPT / Gemini JSON',
                          style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Paste the JSON code block or array generated by AI:',
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _pasteFromClipboard,
                          icon: const Icon(Icons.paste_rounded, size: 14, color: AppColors.neonGold),
                          label: const Text('Paste Clipboard', style: TextStyle(fontSize: 11, color: AppColors.neonGold)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _textController,
                      maxLines: 8,
                      minLines: 5,
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace'),
                      decoration: InputDecoration(
                        hintText: '[\n  {\n    "question": { "en": "...", "bn": "...", "hi": "..." },\n    "options": [...],\n    "correct_index": 0\n  }\n]',
                        hintStyle: TextStyle(color: AppColors.textMuted.withValues(alpha: 0.5), fontSize: 11),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.05),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: AppColors.neonGold),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Submit Button
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.neonGold,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: () {
                          Navigator.pop(context, _textController.text);
                        },
                        icon: const Icon(Icons.check_circle_rounded, size: 20),
                        label: const Text('Parse & Review Questions', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
