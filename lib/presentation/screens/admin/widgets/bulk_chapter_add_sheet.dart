import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../data/services/bulk_chapter_importer.dart';
import '../../../widgets/glass_card.dart';

/// Paste-a-list → live preview → save sheet for adding many chapters at once.
///
/// Accepts lines like `Title EN | Title BN | Title HI` (or with an explicit
/// id first). Never overwrites: ids that already exist are shown as
/// "skipped" and not written — which is why the caller must pass the real
/// [takenIds] and [startNumber], not empty defaults.
class BulkChapterAddSheet extends StatefulWidget {
  final String categoryId;
  final String actorUid;

  /// Chapter ids already in this subject. Preview rows colliding with one of
  /// these are flagged "already exists" instead of silently overwriting.
  final Set<String> takenIds;

  /// First free chapter number (max existing + 1). Auto ids count up from
  /// here so a paste never reuses another chapter's number.
  final int startNumber;

  const BulkChapterAddSheet({
    super.key,
    required this.categoryId,
    required this.actorUid,
    required this.takenIds,
    required this.startNumber,
  });

  @override
  State<BulkChapterAddSheet> createState() => _BulkChapterAddSheetState();
}

class _BulkChapterAddSheetState extends State<BulkChapterAddSheet> {
  final _controller = TextEditingController();
  List<BulkChapterDraft> _drafts = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // parse() is pure and cheap, so the preview follows the paste live —
    // no separate Preview button to forget.
    _controller.addListener(_autoPreview);
  }

  void _autoPreview() {
    setState(() {
      _drafts = BulkChapterImporter.parse(
        _controller.text,
        categoryId: widget.categoryId,
        startNumber: widget.startNumber,
        takenIds: widget.takenIds,
      );
    });
  }

  Future<void> _save() async {
    final valid = _drafts.where((d) => d.isValid).toList();
    if (valid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nothing to save — paste at least one chapter line.'),
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
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder:
            (context, controller) => Container(
              decoration: const BoxDecoration(
                color: AppColors.bgCard,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
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
                    'Add many chapters',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'One per line: Title EN | Title BN | Title HI. The preview updates as you paste.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _controller,
                    minLines: 6,
                    maxLines: 12,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText:
                          'Real Numbers | বাস্তব সংখ্যা | वास्तविक संख्याएँ',
                      hintStyle: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
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
                        borderSide: const BorderSide(
                          color: AppColors.neonCyan,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
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
                  ] else ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Paste your chapter list above — each row appears here with the id and number it will get.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
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
                  ok
                      ? Icons.check_circle_rounded
                      : Icons.error_outline_rounded,
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
    _controller.dispose();
    super.dispose();
  }
}
