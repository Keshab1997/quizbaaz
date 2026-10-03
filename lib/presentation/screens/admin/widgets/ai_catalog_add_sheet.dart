import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../data/models/chapter_model.dart';
import '../../../../data/services/ai_catalog_generator.dart';
import '../../../../data/services/chapter_catalog_service.dart';
import '../../../widgets/glass_card.dart';

/// AI-assisted subject/chapter authoring with an explicit review step.
class AiCatalogAddSheet extends StatefulWidget {
  final List<CategoryModel> categories;
  final String actorUid;

  const AiCatalogAddSheet({
    required this.categories,
    required this.actorUid,
    super.key,
  });

  @override
  State<AiCatalogAddSheet> createState() => _AiCatalogAddSheetState();
}

class _AiCatalogAddSheetState extends State<AiCatalogAddSheet> {
  final _request = TextEditingController();
  final _count = TextEditingController(text: '5');
  final _generator = AiCatalogGenerator();
  final _catalog = ChapterCatalogService();

  bool _newSubject = true;
  String? _categoryId;
  AiCatalogDraft? _draft;
  Set<int> _selected = {};
  bool _generating = false;
  bool _saving = false;
  String? _error;

  CategoryModel? get _category {
    final id = _categoryId;
    if (id == null) return null;
    for (final category in widget.categories) {
      if (category.categoryId == id) return category;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    if (widget.categories.isNotEmpty) {
      _categoryId = widget.categories.first.categoryId;
    }
  }

  @override
  void dispose() {
    _request.dispose();
    _count.dispose();
    super.dispose();
  }

  int get _requestedCount {
    final parsed = int.tryParse(_count.text.trim()) ?? 5;
    return parsed.clamp(1, 20);
  }

  Future<void> _generate() async {
    if (!_newSubject && _category == null) {
      setState(() => _error = 'Choose a subject first.');
      return;
    }

    setState(() {
      _generating = true;
      _saving = false;
      _draft = null;
      _selected = {};
      _error = null;
    });

    try {
      final count = _requestedCount;
      final draft =
          _newSubject
              ? await _generator.generateNewSubject(
                request: _request.text,
                chapterCount: count,
                actorUid: widget.actorUid,
              )
              : await _generator.generateChapters(
                subjectName: _category!.nameText.resolve('en'),
                request: _request.text,
                chapterCount: count,
                existingChapterTitles:
                    _category!.chapters
                        .map((chapter) => chapter.titleText.resolve('en'))
                        .toList(),
                actorUid: widget.actorUid,
              );

      if (!mounted) return;
      if (_newSubject &&
          _categoryIdForName(draft.subjectName!.resolve('en')).isNotEmpty &&
          widget.categories.any(
            (category) =>
                category.categoryId ==
                _categoryIdForName(draft.subjectName!.resolve('en')),
          )) {
        setState(() {
          _generating = false;
          _error =
              'A subject with this generated id already exists. Change the request and try again.';
        });
        return;
      }
      setState(() {
        _draft = draft;
        _selected = {for (var i = 0; i < draft.chapters.length; i++) i};
        _generating = false;
      });
    } on AiCatalogGenerationException catch (e) {
      if (mounted) {
        setState(() {
          _generating = false;
          _error = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _generating = false;
          _error = 'Could not generate the catalogue: $e';
        });
      }
    }
  }

  Future<void> _save() async {
    final draft = _draft;
    if (draft == null || _selected.isEmpty) {
      setState(() => _error = 'Select at least one generated chapter.');
      return;
    }

    final existing = _category;
    if (!_newSubject && existing == null) {
      setState(() => _error = 'Choose a subject first.');
      return;
    }
    final categoryId =
        _newSubject
            ? _categoryIdForName(draft.subjectName!.resolve('en'))
            : existing!.categoryId;
    final existingChapters = existing?.chapters ?? const <ChapterModel>[];
    final usedNumbers = <int>{
      for (final chapter in existingChapters) chapter.chapterNumber,
    };
    final usedIds = {for (final chapter in existingChapters) chapter.chapterId};
    var number =
        _newSubject || usedNumbers.isEmpty
            ? 1
            : usedNumbers.reduce((a, b) => a > b ? a : b) + 1;
    final chapters = <ChapterModel>[];

    for (final index in _selected.toList()..sort()) {
      while (usedNumbers.contains(number) ||
          usedIds.contains(_chapterId(categoryId, number))) {
        number++;
      }
      final aiChapter = draft.chapters[index];
      chapters.add(
        ChapterModel(
          chapterId: _chapterId(categoryId, number),
          chapterNumber: number,
          titleText: aiChapter.title,
          descriptionText: aiChapter.description,
          totalQuestions: 0,
          jsonFile:
              'assets/data/questions/${_chapterId(categoryId, number)}.json',
          isUnlocked: true,
          isEnabled: true,
          stars: 0,
          bestScore: 0,
        ),
      );
      usedNumbers.add(number);
      usedIds.add(_chapterId(categoryId, number));
      number++;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _catalog.saveCategoryWithChapters(
        categoryId: categoryId,
        name: _newSubject ? draft.subjectName! : existing!.nameText,
        icon: _newSubject ? draft.icon : existing!.categoryIcon,
        colorHex: _newSubject ? draft.colorHex : existing!.colorHex,
        priority:
            _newSubject
                ? widget.categories.length + 1
                : widget.categories.indexOf(existing!) + 1,
        chapters: chapters,
        actorUid: widget.actorUid,
        generatedByAi: true,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not save the AI draft: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.92,
      minChildSize: 0.55,
      maxChildSize: 0.96,
      builder: (context, controller) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
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
              const SizedBox(height: 14),
              Row(
                children: [
                  const Icon(
                    Icons.auto_awesome_rounded,
                    color: AppColors.neonGold,
                  ),
                  const SizedBox(width: 9),
                  const Expanded(
                    child: Text(
                      'AI subject & chapter author',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'AI creates a draft in EN · BN · HI. Review the list before saving.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('New subject + chapters'),
                    selected: _newSubject,
                    onSelected:
                        _saving || _generating
                            ? null
                            : (_) => setState(() {
                              _newSubject = true;
                              _draft = null;
                              _error = null;
                            }),
                  ),
                  if (widget.categories.isNotEmpty)
                    ChoiceChip(
                      label: const Text('Add to subject'),
                      selected: !_newSubject,
                      onSelected:
                          _saving || _generating
                              ? null
                              : (_) => setState(() {
                                _newSubject = false;
                                _draft = null;
                                _error = null;
                              }),
                    ),
                ],
              ),
              if (!_newSubject) ...[
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _categoryId,
                  dropdownColor: AppColors.bgCard,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: _inputDecoration('Subject'),
                  items:
                      widget.categories
                          .map(
                            (category) => DropdownMenuItem(
                              value: category.categoryId,
                              child: Text(category.nameText.resolve('en')),
                            ),
                          )
                          .toList(),
                  onChanged:
                      _saving || _generating
                          ? null
                          : (value) => setState(() {
                            _categoryId = value;
                            _draft = null;
                            _error = null;
                          }),
                ),
              ],
              const SizedBox(height: 14),
              TextField(
                controller: _request,
                maxLines: 3,
                enabled: !_saving && !_generating,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: _inputDecoration(
                  _newSubject
                      ? 'What should AI add? (optional details)'
                      : 'Which chapters should AI add? (optional details)',
                ).copyWith(
                  hintText:
                      _newSubject
                          ? 'Example: Class 10 Physical Science, WBBSE syllabus'
                          : 'Example: add the remaining electricity chapters',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Number of chapters',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                  SizedBox(
                    width: 80,
                    child: TextField(
                      controller: _count,
                      enabled: !_saving && !_generating,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white),
                      decoration: _inputDecoration('1–20'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 46,
                child: ElevatedButton.icon(
                  onPressed: _saving || _generating ? null : _generate,
                  icon:
                      _generating
                          ? const SizedBox(
                            width: 17,
                            height: 17,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : const Icon(Icons.auto_awesome_rounded),
                  label: Text(_generating ? 'Generating…' : 'Generate draft'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.neonPurple,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                _message(
                  Icons.error_outline_rounded,
                  _error!,
                  AppColors.neonRed,
                ),
              ],
              if (draft != null) ...[
                const SizedBox(height: 18),
                _preview(draft),
                const SizedBox(height: 14),
                SizedBox(
                  height: 46,
                  child: ElevatedButton.icon(
                    onPressed: _saving || _selected.isEmpty ? null : _save,
                    icon:
                        _saving
                            ? const SizedBox(
                              width: 17,
                              height: 17,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : const Icon(Icons.check_circle_outline_rounded),
                    label: Text(
                      _saving
                          ? 'Saving…'
                          : _newSubject
                          ? 'Add subject and selected chapters'
                          : 'Add selected chapters',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.neonGreen,
                      foregroundColor: AppColors.bgDark,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _preview(AiCatalogDraft draft) {
    return GlassCard(
      borderRadius: 16,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_newSubject) ...[
            const Text(
              'Generated subject',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
            ),
            const SizedBox(height: 3),
            Text(
              draft.subjectName!.resolve('en'),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
            Text(
              '${draft.subjectName!.resolve('bn')} · ${draft.subjectName!.resolve('hi')}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
            ),
            const Divider(color: Colors.white12, height: 18),
          ],
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Review chapters',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                '${_selected.length}/${draft.chapters.length} selected',
                style: const TextStyle(color: AppColors.neonCyan, fontSize: 11),
              ),
            ],
          ),
          if (draft.warnings.isNotEmpty) ...[
            const SizedBox(height: 8),
            _message(
              Icons.warning_amber_rounded,
              draft.warnings.join(' '),
              AppColors.neonGold,
            ),
          ],
          for (var i = 0; i < draft.chapters.length; i++)
            CheckboxListTile(
              value: _selected.contains(i),
              onChanged:
                  _saving
                      ? null
                      : (selected) => setState(() {
                        if (selected == true) {
                          _selected.add(i);
                        } else {
                          _selected.remove(i);
                        }
                      }),
              contentPadding: EdgeInsets.zero,
              activeColor: AppColors.neonCyan,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                '${i + 1}. ${draft.chapters[i].title.resolve('en')}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${draft.chapters[i].title.resolve('bn')}\n${draft.chapters[i].title.resolve('hi')}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                  if (draft.chapters[i].description.isNotEmpty)
                    Text(
                      draft.chapters[i].description.resolve('en'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 10,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _message(IconData icon, String text, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: color, fontSize: 11.5, height: 1.3),
          ),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.05),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.white12),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.white12),
      ),
    );
  }

  static String _categoryIdForName(String name) {
    final slug = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return 'cat_${slug.isEmpty ? 'subject' : slug}';
  }

  static String _chapterId(String categoryId, int number) {
    final stem = categoryId
        .replaceFirst(RegExp(r'^cat_'), '')
        .replaceAll(RegExp(r'[^a-zA-Z0-9_]+'), '_');
    return '${stem}_ch_${number.toString().padLeft(2, '0')}';
  }
}
