import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/chapter_model.dart';
import '../../../data/models/question_model.dart';
import '../../../data/services/ai_question_generator.dart';
import '../../../data/services/question_prompt_builder.dart';
import '../../widgets/glass_card.dart';

/// Review gate between the model and the question bank.
///
/// Nothing generated reaches a student without passing through here. That is
/// the whole reason the feature is defensible in an exam-prep app: the model
/// drafts, the admin decides.
///
/// Deliberately per-question rather than all-or-nothing. A batch of ten with
/// two bad answers should cost two taps, not a full regeneration — throwing
/// away eight good questions to fix two is how an admin ends up not using the
/// review screen at all.
class AiGenerationReviewScreen extends StatefulWidget {
  final ChapterModel chapter;
  final String subjectName;
  final String idPrefix;
  final int startSequence;
  final int count;
  final List<String> existingStems;
  final Set<String> existingFingerprints;
  final String actorUid;
  final List<GeneratedQuestion>? initialDrafts;

  const AiGenerationReviewScreen({
    super.key,
    required this.chapter,
    required this.subjectName,
    required this.idPrefix,
    required this.startSequence,
    required this.existingStems,
    required this.existingFingerprints,
    required this.actorUid,
    this.count = 10,
    this.initialDrafts,
  });

  @override
  State<AiGenerationReviewScreen> createState() =>
      _AiGenerationReviewScreenState();
}

class _AiGenerationReviewScreenState extends State<AiGenerationReviewScreen> {
  final _generator = AiQuestionGenerator();

  GenerationProgress? _progress;
  List<GeneratedQuestion> _results = [];
  final Set<String> _selected = {};
  DifficultyMix _difficulty = DifficultyMix.balanced;
  bool _verify = false;
  bool _running = false;
  StreamSubscription<GenerationProgress>? _subscription;

  @override
  void initState() {
    super.initState();
    // Verification defaults on where a wrong answer is least forgivable — a
    // mis-marked Maths or Physical Science question is unambiguously wrong,
    // while a History nuance is often a judgement call the admin makes anyway.
    final subject = widget.subjectName.toLowerCase();
    _verify = subject.contains('math') ||
        subject.contains('physical') ||
        subject.contains('science');
    _start();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _start() {
    if (widget.initialDrafts != null && widget.initialDrafts!.isNotEmpty) {
      setState(() {
        _running = false;
        _results = widget.initialDrafts!;
        _progress = GenerationProgress(
          stage: GenerationStage.done,
          requested: widget.initialDrafts!.length,
          accepted: widget.initialDrafts!.length,
          message: 'Loaded ${widget.initialDrafts!.length} questions from JSON',
          results: widget.initialDrafts!,
        );
        _selected
          ..clear()
          ..addAll(
            widget.initialDrafts!
                .where((r) => r.isClean)
                .map((r) => r.question.id),
          );
      });
      return;
    }

    setState(() {
      _running = true;
      _results = [];
      _selected.clear();
      _progress = GenerationProgress(
        stage: GenerationStage.starting,
        requested: widget.count,
        message: 'Preparing…',
      );
    });

    _subscription?.cancel();
    _subscription = _generator
        .generate(
      chapter: widget.chapter,
      subjectName: widget.subjectName,
      idPrefix: widget.idPrefix,
      startSequence: widget.startSequence,
      count: widget.count,
      existingStems: widget.existingStems,
      existingFingerprints: widget.existingFingerprints,
      difficulty: _difficulty,
      verify: _verify,
      actorUid: widget.actorUid,
    )
        .listen((progress) {
      if (!mounted) return;
      setState(() {
        _progress = progress;
        if (progress.isTerminal) {
          _running = false;
          _results = progress.results;
          // Pre-select only what needs no attention. Anything flagged is an
          // explicit decision, never something that slips in by default.
          _selected
            ..clear()
            ..addAll(
              progress.results
                  .where((r) => r.isClean)
                  .map((r) => r.question.id),
            );
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final progress = _progress;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Review drafts',
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
          if (!_running)
            TextButton.icon(
              onPressed: _start,
              icon: const Icon(Icons.refresh_rounded,
                  size: 16, color: AppColors.neonPurple),
              label: const Text('Regenerate',
                  style:
                      TextStyle(fontSize: 12, color: AppColors.neonPurple)),
            ),
        ],
      ),
      bottomNavigationBar: _running ? null : _approveBar(),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            if (progress != null) _progressCard(progress),
            const SizedBox(height: 12),
            if (!_running) _options(),
            const SizedBox(height: 12),
            for (var i = 0; i < _results.length; i++)
              _draftCard(_results[i], i + 1),
            if (!_running && _results.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 50),
                child: Center(
                  child: Text('Nothing was produced. Try again.',
                      style: TextStyle(color: AppColors.textSecondary)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------- progress --

  Widget _progressCard(GenerationProgress progress) {
    final failed = progress.stage == GenerationStage.failed;
    final colour = failed
        ? AppColors.neonRed
        : progress.stage == GenerationStage.done
            ? AppColors.neonGreen
            : AppColors.neonPurple;

    return GlassCard(
      borderRadius: 18,
      padding: const EdgeInsets.all(16),
      borderColor: colour.withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (_running)
                const SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.neonPurple),
                )
              else
                Icon(
                  failed
                      ? Icons.error_outline_rounded
                      : Icons.check_circle_rounded,
                  size: 17,
                  color: colour,
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  progress.message,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: colour),
                ),
              ),
              Text(
                '${progress.accepted}/${progress.requested}',
                style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress.fraction,
              minHeight: 6,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              valueColor: AlwaysStoppedAnimation<Color>(colour),
            ),
          ),
          if (progress.rejected > 0) ...[
            const SizedBox(height: 8),
            Text(
              '${progress.rejected} draft(s) rejected by the checks and replaced',
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }

  Widget _options() {
    return GlassCard(
      borderRadius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        children: [
          Row(
            children: [
              const Text('Difficulty',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary)),
              const SizedBox(width: 8),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final mix in DifficultyMix.values)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: ChoiceChip(
                            label: Text(mix.label,
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: _difficulty == mix
                                        ? AppColors.bgDark
                                        : AppColors.textSecondary)),
                            selected: _difficulty == mix,
                            showCheckmark: false,
                            backgroundColor: Colors.white.withValues(alpha: 0.05),
                            selectedColor: AppColors.neonCyan,
                            side: BorderSide(
                                color: _difficulty == mix
                                    ? AppColors.neonCyan
                                    : Colors.white12),
                            onSelected: (_) => setState(() => _difficulty = mix),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          // Own Material so the tile ink paints above the card's
          // DecoratedBox (Flutter asserts otherwise).
          Material(
            type: MaterialType.transparency,
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _verify,
              activeThumbColor: AppColors.neonCyan,
              onChanged: (v) => setState(() => _verify = v),
              title: const Text('Double-check answers',
                  style: TextStyle(fontSize: 12.5, color: Colors.white)),
              subtitle: const Text(
                  'A second key re-reads each answer. Slower, catches mis-marked options.',
                  style: TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- drafts --

  Widget _draftCard(GeneratedQuestion draft, int position) {
    final question = draft.question;
    final selected = _selected.contains(question.id);
    final flag = _flagFor(draft);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        borderRadius: 16,
        padding: EdgeInsets.zero,
        borderColor: flag?.colour.withValues(alpha: 0.4) ??
            (selected ? AppColors.neonGreen.withValues(alpha: 0.3) : null),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.only(left: 4, right: 12),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            iconColor: AppColors.textSecondary,
            collapsedIconColor: AppColors.textSecondary,
            leading: Checkbox(
              value: selected,
              activeColor: AppColors.neonGreen,
              onChanged: (v) => setState(() {
                if (v == true) {
                  _selected.add(question.id);
                } else {
                  _selected.remove(question.id);
                }
              }),
            ),
            title: Text(
              question.questionText.resolve('en'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  height: 1.35),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Text('$position · ${question.id}',
                      style: const TextStyle(
                          fontSize: 10.5, color: AppColors.textMuted)),
                  if (flag != null) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: Row(
                        children: [
                          Icon(flag.icon, size: 11, color: flag.colour),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(flag.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 10.5, color: flag.colour)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            children: [
              if (flag != null) _flagBanner(draft, flag),
              for (final code in ['en', 'bn', 'hi'])
                _languageBlock(draft, code),
            ],
          ),
        ),
      ),
    );
  }

  Widget _flagBanner(GeneratedQuestion draft, _Flag flag) {
    final verification = draft.verification;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: flag.colour.withValues(alpha: 0.1),
        border: Border.all(color: flag.colour.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(flag.detail,
              style: TextStyle(
                  fontSize: 11.5, color: flag.colour, height: 1.4)),
          if (verification != null && verification.disagrees) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 30),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  side: BorderSide(color: flag.colour.withValues(alpha: 0.6)),
                ),
                onPressed: verification.suggestedIndex == null
                    ? null
                    : () => _applySuggestion(draft, verification.suggestedIndex!),
                child: Text(
                  'Mark option '
                  '${String.fromCharCode(65 + (verification.suggestedIndex ?? 0))} instead',
                  style: TextStyle(fontSize: 11.5, color: flag.colour),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _languageBlock(GeneratedQuestion draft, String code) {
    final question = draft.question;
    if (!question.questionText.has(code)) return const SizedBox.shrink();

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
          Text(question.questionText.resolve(code),
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
                    child: Text(options[i],
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.3,
                          fontWeight: i == question.correctIndex
                              ? FontWeight.w700
                              : FontWeight.w400,
                          color: i == question.correctIndex
                              ? AppColors.neonGreen
                              : AppColors.textSecondary,
                        )),
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

  // ------------------------------------------------------------- approving --

  Widget _approveBar() {
    final count = _selected.length;
    final flagged =
        _results.where((r) => !r.isClean && _selected.contains(r.question.id)).length;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (flagged > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '$flagged flagged question(s) are selected — check them first',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.neonGold),
                ),
              ),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      count == 0 ? Colors.white12 : AppColors.neonGreen,
                  foregroundColor:
                      count == 0 ? AppColors.textMuted : AppColors.bgDark,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15)),
                ),
                onPressed: count == 0 ? null : _approve,
                icon: const Icon(Icons.playlist_add_check_rounded, size: 20),
                label: Text(
                  count == 0
                      ? 'Select questions to add'
                      : 'Add $count question${count == 1 ? '' : 's'} to chapter',
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _approve() {
    final approved = _results
        .where((r) => _selected.contains(r.question.id))
        .map((r) => r.question)
        .toList();
    Navigator.pop(context, approved);
  }

  void _applySuggestion(GeneratedQuestion draft, int index) {
    setState(() {
      final position =
          _results.indexWhere((r) => r.question.id == draft.question.id);
      if (position < 0) return;

      final question = draft.question;
      _results[position] = draft.copyWith(
        question: QuestionModel(
          id: question.id,
          questionText: question.questionText,
          optionTexts: question.optionTexts,
          correctIndex: index,
          explanationText: question.explanationText,
          points: question.points,
          timeLimitSec: question.timeLimitSec,
        ),
        verification: const VerificationVerdict(
          verdict: 'ok',
          reason: 'answer corrected by admin',
        ),
      );
    });
  }

  _Flag? _flagFor(GeneratedQuestion draft) {
    final verification = draft.verification;
    if (verification != null && verification.disagrees) {
      return _Flag(
        icon: Icons.report_problem_rounded,
        colour: AppColors.neonRed,
        label: 'Answer disputed',
        detail: 'The second check says option '
            '${String.fromCharCode(65 + (verification.suggestedIndex ?? 0))} '
            'is correct, not '
            '${String.fromCharCode(65 + draft.question.correctIndex)}.'
            '${verification.reason.isEmpty ? '' : ' ${verification.reason}'}',
      );
    }

    final near = draft.validation.nearDuplicate;
    if (near != null) {
      return _Flag(
        icon: Icons.copy_rounded,
        colour: AppColors.neonGold,
        label: 'Similar to ${near.questionId}',
        detail: 'This closely resembles ${near.questionId} '
            '(${near.scoreLabel}): "${near.stem}"',
      );
    }

    if (verification != null && verification.unsure) {
      return _Flag(
        icon: Icons.help_outline_rounded,
        colour: AppColors.neonGold,
        label: 'Unverified',
        detail: 'The second check could not confirm the answer.'
            '${verification.reason.isEmpty ? '' : ' ${verification.reason}'}',
      );
    }

    final warnings = draft.validation.warnings;
    if (warnings.isNotEmpty) {
      return _Flag(
        icon: Icons.info_outline_rounded,
        colour: AppColors.neonGold,
        label: warnings.first.field,
        detail: warnings.map((w) => w.toString()).join('\n'),
      );
    }
    return null;
  }
}

class _Flag {
  final IconData icon;
  final Color colour;
  final String label;
  final String detail;

  const _Flag({
    required this.icon,
    required this.colour,
    required this.label,
    required this.detail,
  });
}
