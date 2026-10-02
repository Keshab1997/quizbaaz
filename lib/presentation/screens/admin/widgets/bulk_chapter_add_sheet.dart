import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../data/services/bulk_chapter_importer.dart';
import '../../../widgets/glass_card.dart';

/// Paste-a-list → preview → save sheet for adding many chapters at once.
///
/// Accepts lines like `Title EN | Title BN | Title HI` (or with an explicit
/// id first). Never overwrites: ids that already exist are shown as
/// "skipped" and not written.
class BulkChapterAddSheet extends StatefulWidget {
  final String categoryId;
  final String actorUid;

  const BulkChapterAddSheet({
    super.key,
    required this.categoryId,
    required this.actorUid,
  });

  @override
  State<BulkChapterAddSheet> createState() => _BulkChapterAddSheetState();
}

class _BulkChapterAddSheetState extends State<BulkChapterAddSheet> {
  final _controller = TextEditingController();
  List<BulkChapterDraft> _drafts = [];
  bool _saving = false;

  void _preview(Set<String> takenIds, int startNumber) {
    setState(() {
      _drafts = BulkChapterImporter.parse(
        _controller.text,
        categoryId: widget.categoryId,
        startNumber: startNumber,
        takenIds: takenIds,
      );
    });
  }

  Future<void> _save() async {
    final valid = _drafts.where((d) => d.isValid).toList();
    if (valid.isEmpty) return;
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
              padding: const EdgeInsets.all(18),
              child: ListView(
                controller: controller,
                children: [
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
                    'One per line: Title EN | Title BN | Title HI.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
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
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.05),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _preview(const {}, 1),
                          child: const Text('Preview'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: _saving ? null : _save,
                          child: Text(_saving ? 'Saving…' : 'Save'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  for (final draft in _drafts)
                    GlassCard(
                      borderRadius: 12,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              draft.title.resolve('en'),
                              style: const TextStyle(color: Colors.white),
                            ),
                            Text(
                              draft.chapterId,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textMuted,
                              ),
                            ),
                            if (!draft.isValid)
                              Text(
                                draft.error ?? 'Skipped',
                                style: const TextStyle(
                                  color: AppColors.neonRed,
                                  fontSize: 11,
                                ),
                              ),
                          ],
                        ),
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
