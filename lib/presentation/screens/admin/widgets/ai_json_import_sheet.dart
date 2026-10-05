import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../data/services/ai_syllabus_importer.dart';
import '../../../../data/services/bulk_chapter_importer.dart';
import '../../../widgets/glass_card.dart';

/// Paste syllabus → copy prompt → paste AI JSON → chapters.
///
/// The admin pastes a table-of-contents (e.g. from a guide book), copies the
/// generated prompt into ChatGPT/Gemini, and pastes the returned JSON array
/// back here. Answers are validated with the same never-overwrite rules as
/// the manual paste-a-list flow before anything is written.
class AiJsonImportSheet extends StatefulWidget {
  final String categoryId;
  final String subjectName;
  final String actorUid;

  /// Chapter ids already in this subject. Answer rows colliding with one of
  /// these are flagged "already exists" instead of silently overwriting.
  final Set<String> takenIds;

  /// First free chapter number (max existing + 1). The prompt numbers from
  /// here so a paste never reuses another chapter's number.
  final int startNumber;

  const AiJsonImportSheet({
    super.key,
    required this.categoryId,
    required this.subjectName,
    required this.actorUid,
    required this.takenIds,
    required this.startNumber,
  });

  @override
  State<AiJsonImportSheet> createState() => _AiJsonImportSheetState();
}

class _AiJsonImportSheetState extends State<AiJsonImportSheet> {
  final _syllabus = TextEditingController();
  final _answer = TextEditingController();
  List<BulkChapterDraft> _drafts = [];
  String? _parseError;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // The prompt embeds the syllabus, so it rebuilds on every keystroke;
    // the JSON answer re-parses the same way the bulk sheet previews live.
    _syllabus.addListener(() => setState(() {}));
    _answer.addListener(_parseAnswer);
  }

  bool get _hasSyllabus => _syllabus.text.trim().isNotEmpty;

  String get _prompt => AiSyllabusImporter.buildPrompt(
    subjectName: widget.subjectName,
    categoryId: widget.categoryId,
    startNumber: widget.startNumber,
    syllabusText:
        _hasSyllabus ? _syllabus.text.trim() : '(paste the syllabus above)',
  );

  void _parseAnswer() {
    final text = _answer.text.trim();
    if (text.isEmpty) {
      setState(() {
        _drafts = [];
        _parseError = null;
      });
      return;
    }
    try {
      final drafts = AiSyllabusImporter.parseAnswer(
        text,
        categoryId: widget.categoryId,
        startNumber: widget.startNumber,
        takenIds: widget.takenIds,
      );
      setState(() {
        _drafts = drafts;
        _parseError = null;
      });
    } on FormatException catch (e) {
      setState(() {
        _drafts = [];
        _parseError = e.message;
      });
    }
  }

  Future<void> _copyPrompt() async {
    await Clipboard.setData(ClipboardData(text: _prompt));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Prompt copied — paste it into ChatGPT or Gemini.'),
      ),
    );
  }

  Future<void> _save() async {
    final valid = _drafts.where((d) => d.isValid).toList();
    if (valid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nothing to save — paste the AI answer first.'),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final result = await BulkChapterImporter.saveAll(
        db: FirebaseFirestore.instance,
        categoryId: widget.categoryId,
        drafts: _drafts,
        actorUid: widget.actorUid,
      );
      if (!mounted) return;
      Navigator.pop(context, result);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final valid = _drafts.where((d) => d.isValid).length;
    final skipped = _drafts.length - valid;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.92,
        minChildSize: 0.55,
        maxChildSize: 0.96,
        builder:
            (context, controller) => Container(
              decoration: const BoxDecoration(
                color: AppColors.bgCard,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
              child: ListView(
                controller: controller,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'AI chapter import',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${widget.subjectName} · numbering from No. ${widget.startNumber}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _step(
                    '1',
                    'Paste the syllabus',
                    'A table-of-contents from any book — titles, page numbers and all.',
                  ),
                  const SizedBox(height: 8),
                  _bigField(
                    controller: _syllabus,
                    hint: 'Chapter 1\nPhysics (পদার্থবিদ্যা)\n2-30\n…',
                  ),
                  const SizedBox(height: 16),
                  _step(
                    '2',
                    'Copy the prompt',
                    'Paste it into ChatGPT or Gemini and wait for the JSON array.',
                  ),
                  const SizedBox(height: 8),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 170),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        _prompt,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.textSecondary,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _hasSyllabus ? _copyPrompt : null,
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text('Copy prompt'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _step(
                    '3',
                    'Paste the AI answer',
                    'The JSON array, fences or not — the preview appears below.',
                  ),
                  const SizedBox(height: 8),
                  _bigField(
                    controller: _answer,
                    hint: '[{"id": "…_ch_…", "number": …, "title": {…}}]',
                  ),
                  if (_parseError != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          size: 15,
                          color: AppColors.neonRed,
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            _parseError!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.neonRed,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (_drafts.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      '$valid ready'
                      '${skipped > 0 ? ' · $skipped skipped' : ''}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final draft in _drafts) _draftRow(draft),
                  ],
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.neonPurple,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: _saving ? null : _save,
                      child: Text(
                        _saving
                            ? 'Saving…'
                            : valid == 0
                            ? 'Save'
                            : 'Save $valid chapter${valid == 1 ? '' : 's'}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
      ),
    );
  }

  Widget _step(String number, String title, String hint) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.neonGold.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: AppColors.neonGold.withValues(alpha: 0.5),
            ),
          ),
          child: Text(
            number,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: AppColors.neonGold,
            ),
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                hint,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _bigField({
    required TextEditingController controller,
    required String hint,
  }) {
    return TextField(
      controller: controller,
      minLines: 4,
      maxLines: 8,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 12),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.white12),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.neonCyan),
        ),
      ),
    );
  }

  Widget _draftRow(BulkChapterDraft draft) {
    final ok = draft.isValid;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        borderRadius: 12,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(
                  ok ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                  size: 16,
                  color: ok ? AppColors.neonGreen : AppColors.neonRed,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      draft.title.resolve('en'),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${draft.chapterId} · No. ${draft.chapterNumber}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                    if (!ok) ...[
                      const SizedBox(height: 2),
                      Text(
                        draft.error ?? 'Skipped',
                        style: const TextStyle(
                          color: AppColors.neonRed,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _syllabus.dispose();
    _answer.dispose();
    super.dispose();
  }
}
