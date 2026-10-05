import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/chapter_model.dart';
import '../../../data/models/localized_text.dart';
import '../../../data/providers/auth_provider.dart';
import '../../../data/repositories/quiz_repository.dart';
import '../../../data/services/ai_question_generator.dart';
import '../../../data/services/bulk_chapter_importer.dart';
import '../../../data/services/chapter_catalog_service.dart';
import '../../widgets/glass_card.dart';
import 'widgets/ai_catalog_add_sheet.dart';
import 'widgets/bulk_chapter_add_sheet.dart';
import 'question_manager_screen.dart';
import 'widgets/trilingual_field.dart';

/// Subject → chapter tree for the admin.
///
/// Mirrors the layout of `chapters_list.json` on purpose: the admin already
/// knows that shape, and a manager that reorganises the content into something
/// "cleaner" just makes it harder to find a chapter.
///
/// Every chapter row shows its live question count, because the single most
/// common question when adding content is "how many does this one have
/// already?".
class ChapterManagerScreen extends StatefulWidget {
  const ChapterManagerScreen({super.key});

  @override
  State<ChapterManagerScreen> createState() => _ChapterManagerScreenState();
}

class _ChapterManagerScreenState extends State<ChapterManagerScreen> {
  final _repository = QuizRepository();
  final _catalog = ChapterCatalogService();

  List<CategoryModel> _categories = [];
  Map<String, int> _counts = {};
  bool _loading = true;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    // The repository already folds admin-authored counts into
    // chapter.totalQuestions, in one read rather than 56 aggregate queries —
    // and it means this screen and the student's chapter list can never
    // disagree about how many questions a chapter has.
    final categories = await _repository.getCategoriesAndChapters(
      forceRefresh: true,
      includeDisabled: true,
    );

    if (!mounted) return;
    setState(() {
      _categories = categories;
      _counts = {
        for (final category in categories)
          for (final chapter in category.chapters)
            chapter.chapterId: chapter.totalQuestions,
      };
      _loading = false;
    });
  }

  String get _actorUid =>
      context.read<AuthProvider>().firebaseUser?.uid ?? 'unknown';

  List<CategoryModel> get _visible {
    if (_search.trim().isEmpty) return _categories;
    final needle = _search.toLowerCase();

    return _categories
        .map((category) {
          final matchesSubject = category.nameText.toJson().values.any(
            (v) => v.toLowerCase().contains(needle),
          );
          final chapters =
              category.chapters
                  .where(
                    (c) =>
                        matchesSubject ||
                        c.titleText.toJson().values.any(
                          (v) => v.toLowerCase().contains(needle),
                        ),
                  )
                  .toList();
          return CategoryModel(
            categoryId: category.categoryId,
            nameText: category.nameText,
            categoryIcon: category.categoryIcon,
            colorHex: category.colorHex,
            totalChapters: chapters.length,
            chapters: chapters,
            priority: category.priority,
          );
        })
        .where((c) => c.chapters.isNotEmpty)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final categories = _visible;
    final totalQuestions = _counts.values.fold<int>(0, (sum, n) => sum + n);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text(
          'Chapter Manager',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          IconButton(
            tooltip: 'AI add subject or chapters',
            icon: const Icon(
              Icons.auto_awesome_rounded,
              color: AppColors.neonGold,
            ),
            onPressed: _loading ? null : _openAiCatalogAdd,
          ),
          IconButton(
            tooltip: 'Reload',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.neonPurple,
        onPressed: _addSubject,
        icon: const Icon(Icons.create_new_folder_rounded, size: 20),
        label: const Text('Subject'),
      ),
      body:
          _loading
              ? const Center(
                child: CircularProgressIndicator(color: AppColors.neonCyan),
              )
              : RefreshIndicator(
                onRefresh: _load,
                color: AppColors.neonCyan,
                backgroundColor: AppColors.surfaceElevated,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  children: [
                    _summary(totalQuestions),
                    const SizedBox(height: 14),
                    _searchBox(),
                    const SizedBox(height: 14),
                    if (categories.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 60),
                        child: Center(
                          child: Text(
                            'No chapters match that search.',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        ),
                      ),
                    for (final category in categories) _categoryCard(category),
                  ],
                ),
              ),
    );
  }

  Widget _summary(int totalQuestions) {
    final chapterCount = _categories.fold<int>(
      0,
      (sum, c) => sum + c.chapters.length,
    );
    final empty = _counts.values.where((n) => n == 0).length;

    return GlassCard(
      borderRadius: 18,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth < 420 ? 2 : 4;
          return GridView.count(
            crossAxisCount: columns,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 8,
            childAspectRatio: columns == 2 ? 2.2 : 1.45,
            children: [
              _stat('Subjects', '${_categories.length}', AppColors.neonPurple),
              _stat('Chapters', '$chapterCount', AppColors.neonCyan),
              _stat('Questions', '$totalQuestions', AppColors.neonGreen),
              _stat(
                'Empty',
                '$empty',
                empty == 0 ? AppColors.neonGreen : AppColors.neonGold,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _stat(String label, String value, Color color) {
    // No Expanded here: grid children are not in a Flex, and an Expanded
    // directly under a GridView throws an Incorrect-use-of-ParentData error
    // that blanks the whole summary card.
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 10.5,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _searchBox() {
    return TextField(
      style: const TextStyle(color: Colors.white, fontSize: 14),
      onChanged: (v) => setState(() => _search = v),
      decoration: InputDecoration(
        hintText: 'Search subject or chapter…',
        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
        prefixIcon: const Icon(
          Icons.search_rounded,
          color: AppColors.textSecondary,
        ),
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

  Widget _categoryCard(CategoryModel category) {
    final color = _parseColor(category.colorHex);
    final questionTotal = category.chapters.fold<int>(
      0,
      (sum, c) => sum + (_counts[c.chapterId] ?? 0),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        borderRadius: 18,
        padding: EdgeInsets.zero,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: _search.trim().isNotEmpty,
            tilePadding: const EdgeInsets.symmetric(horizontal: 16),
            childrenPadding: const EdgeInsets.only(bottom: 8),
            iconColor: AppColors.textSecondary,
            collapsedIconColor: AppColors.textSecondary,
            title: Text(
              category.categoryName,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                '${category.chapters.length} chapters · $questionTotal questions',
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            leading: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: color.withValues(alpha: 0.18),
                border: Border.all(color: color.withValues(alpha: 0.5)),
              ),
              child: Icon(Icons.menu_book_rounded, size: 19, color: color),
            ),
            children: [
              for (final chapter in category.chapters)
                _chapterRow(category, chapter, color),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Row(
                  children: [
                    TextButton.icon(
                      onPressed: () => _editChapter(category, null),
                      icon: const Icon(
                        Icons.add_rounded,
                        size: 16,
                        color: AppColors.neonCyan,
                      ),
                      label: const Text(
                        'Add chapter',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.neonCyan,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _bulkAddChapters(category),
                      icon: const Icon(
                        Icons.playlist_add_rounded,
                        size: 16,
                        color: AppColors.neonPurple,
                      ),
                      label: const Text(
                        'Paste list',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.neonPurple,
                        ),
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () => _editSubject(category),
                      icon: const Icon(
                        Icons.edit_rounded,
                        size: 15,
                        color: AppColors.textSecondary,
                      ),
                      label: const Text(
                        'Edit subject',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Reorder chapters',
                      icon: const Icon(
                        Icons.swap_vert_rounded,
                        size: 17,
                        color: AppColors.textSecondary,
                      ),
                      onPressed: () => _reorderChapters(category),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chapterRow(
    CategoryModel category,
    ChapterModel chapter,
    Color color,
  ) {
    final count = _counts[chapter.chapterId] ?? 0;
    final coverage = _coverageLabel(chapter);

    return InkWell(
      onTap: () => _openQuestions(category, chapter),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 9, 8, 9),
        child: Row(
          children: [
            SizedBox(
              width: 30,
              child: Text(
                '${chapter.chapterNumber}',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w900,
                  color: color.withValues(alpha: 0.8),
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    chapter.titleText.resolve('en'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    coverage,
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: (count == 0 ? AppColors.neonGold : AppColors.neonGreen)
                    .withValues(alpha: 0.16),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w900,
                  color: count == 0 ? AppColors.neonGold : AppColors.neonGreen,
                ),
              ),
            ),
            IconButton(
              tooltip:
                  chapter.isEnabled ? 'Hide from students' : 'Show to students',
              iconSize: 18,
              color:
                  chapter.isEnabled ? AppColors.neonGreen : AppColors.neonGold,
              icon: Icon(
                chapter.isEnabled
                    ? Icons.visibility_rounded
                    : Icons.visibility_off_rounded,
              ),
              onPressed:
                  () =>
                      _setChapterEnabled(category, chapter, !chapter.isEnabled),
            ),
            IconButton(
              tooltip: 'Edit chapter',
              iconSize: 17,
              color: AppColors.textSecondary,
              icon: const Icon(Icons.edit_rounded),
              onPressed: () => _editChapter(category, chapter),
            ),
          ],
        ),
      ),
    );
  }

  /// e.g. "EN · BN · hi missing" — which languages the *title* carries.
  String _coverageLabel(ChapterModel chapter) {
    final missing =
        [
          'en',
          'bn',
          'hi',
        ].where((code) => !chapter.titleText.has(code)).toList();
    if (missing.isEmpty) return 'EN · BN · HI';
    return 'missing ${missing.join(", ").toUpperCase()}';
  }

  static Color _parseColor(String hex) {
    final cleaned = hex.replaceFirst('#', '');
    final value = int.tryParse(cleaned, radix: 16);
    if (value == null) return AppColors.neonCyan;
    return Color(cleaned.length == 6 ? 0xFF000000 | value : value);
  }

  // ----------------------------------------------------------- navigation --

  void _openQuestions(CategoryModel category, ChapterModel chapter) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => QuestionManagerScreen(
              categoryId: category.categoryId,
              subjectName: category.nameText.resolve('en'),
              chapter: chapter,
            ),
      ),
    ).then((_) => _load());
  }

  // --------------------------------------------------------------- editing --

  Future<void> _openAiCatalogAdd() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder:
          (_) =>
              AiCatalogAddSheet(categories: _categories, actorUid: _actorUid),
    );
    if (saved == true && mounted) {
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('AI catalogue draft saved.')),
      );
    }
  }

  Future<void> _addSubject() => _editSubject(null);

  Future<void> _editSubject(CategoryModel? existing) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder:
          (_) => _SubjectSheet(
            existing: existing,
            initialPriority: _priorityFor(existing),
            takenIds: {for (final c in _categories) c.categoryId},
            onSave:
                (id, name, icon, color, priority) => _catalog.saveCategory(
                  categoryId: id,
                  name: name,
                  icon: icon,
                  colorHex: color,
                  priority: priority,
                  actorUid: _actorUid,
                ),
          ),
    );
    if (saved == true) _load();
  }

  /// The order value a subject edit must keep. A lost priority drops the
  /// subject to the top of the Firestore-ordered list, so an edit keeps its
  /// value (or its current position when the document never had one) and a
  /// new subject goes last.
  int _priorityFor(CategoryModel? existing) {
    if (existing == null) return _categories.length + 1;
    if (existing.priority > 0) return existing.priority;
    final at = _categories.indexWhere(
      (c) => c.categoryId == existing.categoryId,
    );
    return at >= 0 ? at + 1 : _categories.length + 1;
  }

  Future<void> _editChapter(
    CategoryModel category,
    ChapterModel? existing,
  ) async {
    final nextNumber =
        category.chapters.isEmpty
            ? 1
            : category.chapters
                    .map((c) => c.chapterNumber)
                    .reduce((a, b) => a > b ? a : b) +
                1;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder:
          (_) => _ChapterSheet(
            categoryId: category.categoryId,
            categoryName: category.categoryName,
            existing: existing,
            takenIds: {for (final c in category.chapters) c.chapterId},
            defaultNumber: nextNumber,
            onSave:
                (id, title, description, number, unlocked, enabled) =>
                    _catalog.saveChapter(
                      categoryId: category.categoryId,
                      chapterId: id,
                      title: title,
                      description: description,
                      chapterNumber: number,
                      isUnlocked: unlocked,
                      isEnabled: enabled,
                      actorUid: _actorUid,
                    ),
          ),
    );
    if (saved == true) _load();
  }

  Future<void> _bulkAddChapters(CategoryModel category) async {
    // The sheet must know which ids and numbers are taken: without them it
    // numbers from 1 and its merge-write silently renames existing chapters.
    final takenIds = {for (final c in category.chapters) c.chapterId};
    final startNumber =
        category.chapters.isEmpty
            ? 1
            : category.chapters
                    .map((c) => c.chapterNumber)
                    .reduce((a, b) => a > b ? a : b) +
                1;
    final result = await showModalBottomSheet<BulkChapterResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder:
          (_) => BulkChapterAddSheet(
            categoryId: category.categoryId,
            actorUid: _actorUid,
            takenIds: takenIds,
            startNumber: startNumber,
          ),
    );
    if (result != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.created > 0
                ? 'Added ${result.created} chapters'
                    '${result.skipped > 0 ? ' (${result.skipped} skipped)' : ''}.'
                : 'No new chapters to add.',
          ),
        ),
      );
      if (result.created > 0) await _load();
    }
  }

  Future<void> _reorderChapters(CategoryModel category) async {
    // Reorder always covers the whole subject: the visible list may be
    // search-filtered, and renumbering only that subset would scramble the
    // chapters the search hid.
    final full = _categories.firstWhere(
      (c) => c.categoryId == category.categoryId,
      orElse: () => category,
    );
    final updated = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReorderSheet(chapters: full.chapters),
    );
    if (updated == null) return;
    try {
      await _catalog.reorderChapters(
        categoryId: category.categoryId,
        orderedChapterIds: updated,
        actorUid: _actorUid,
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not reorder: $e')));
    }
  }

  Future<void> _setChapterEnabled(
    CategoryModel category,
    ChapterModel chapter,
    bool isEnabled,
  ) async {
    try {
      await _catalog.setChapterEnabled(
        categoryId: category.categoryId,
        chapter: chapter,
        isEnabled: isEnabled,
        actorUid: _actorUid,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isEnabled
                ? '${chapter.titleText.resolve('en')} is now visible to students.'
                : '${chapter.titleText.resolve('en')} is now hidden from students.',
          ),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update chapter visibility: $e')),
      );
    }
  }
}

// ============================================================ reorder sheet ==

/// Up/down reorder list for chapters. Shows titles (not raw ids) and returns
/// the new id order on save.
class _ReorderSheet extends StatefulWidget {
  final List<ChapterModel> chapters;
  const _ReorderSheet({required this.chapters});
  @override
  State<_ReorderSheet> createState() => _ReorderSheetState();
}

class _ReorderSheetState extends State<_ReorderSheet> {
  late List<ChapterModel> _order;

  @override
  void initState() {
    super.initState();
    _order = List<ChapterModel>.from(widget.chapters);
  }

  void _move(int index, int delta) {
    final next = index + delta;
    if (next < 0 || next >= _order.length) return;
    setState(() {
      final chapter = _order.removeAt(index);
      _order.insert(next, chapter);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        builder:
            (context, controller) => Container(
              decoration: const BoxDecoration(
                color: AppColors.bgCard,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
              child: Column(
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
                    'Reorder chapters',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Top of the list becomes chapter 1.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.builder(
                      controller: controller,
                      itemCount: _order.length,
                      itemBuilder: (context, index) {
                        final chapter = _order[index];
                        return ListTile(
                          key: ValueKey(chapter.chapterId),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 4,
                          ),
                          leading: SizedBox(
                            width: 26,
                            child: Text(
                              '${index + 1}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                color: AppColors.neonCyan,
                              ),
                            ),
                          ),
                          title: Text(
                            chapter.titleText.resolve('en'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13.5,
                              color: Colors.white,
                            ),
                          ),
                          subtitle: Text(
                            chapter.chapterId,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textMuted,
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Move up',
                                icon: const Icon(Icons.arrow_upward_rounded),
                                iconSize: 20,
                                color: AppColors.textSecondary,
                                onPressed:
                                    index == 0 ? null : () => _move(index, -1),
                              ),
                              IconButton(
                                tooltip: 'Move down',
                                icon: const Icon(Icons.arrow_downward_rounded),
                                iconSize: 20,
                                color: AppColors.textSecondary,
                                onPressed:
                                    index == _order.length - 1
                                        ? null
                                        : () => _move(index, 1),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed:
                          () => Navigator.pop(context, [
                            for (final c in _order) c.chapterId,
                          ]),
                      child: const Text(
                        'Save order',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ],
              ),
            ),
      ),
    );
  }
}

// ============================================================ subject sheet ==

class _SubjectSheet extends StatefulWidget {
  final CategoryModel? existing;

  /// Prefilled order value — the existing priority on edit, length + 1 for
  /// a new subject — so saving never silently reorders the subject list.
  final int initialPriority;

  /// Subject ids already on file. A *new* subject reusing one would
  /// silently overwrite it, so the sheet refuses those ids.
  final Set<String> takenIds;
  final Future<void> Function(
    String id,
    LocalizedText name,
    String icon,
    String colorHex,
    int priority,
  )
  onSave;

  const _SubjectSheet({
    required this.existing,
    required this.initialPriority,
    required this.takenIds,
    required this.onSave,
  });

  @override
  State<_SubjectSheet> createState() => _SubjectSheetState();
}

class _SubjectSheetState extends State<_SubjectSheet> {
  late final TextEditingController _id;
  late final TextEditingController _icon;
  late final TextEditingController _color;
  late final TextEditingController _priority;
  late LocalizedText _name;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _id = TextEditingController(text: e?.categoryId ?? '');
    _icon = TextEditingController(
      text: e?.categoryIcon ?? 'assets/icons/coin_and_gem_3d.png',
    );
    _color = TextEditingController(text: e?.colorHex ?? '#53E6FF');
    _priority = TextEditingController(text: '${widget.initialPriority}');
    _name = e?.nameText ?? const LocalizedText.empty();
  }

  @override
  void dispose() {
    _id.dispose();
    _icon.dispose();
    _color.dispose();
    _priority.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final id = _id.text.trim();
    if (id.isEmpty) return setState(() => _error = 'Subject id is required');
    if (!RegExp(r'^[a-z0-9_]+$').hasMatch(id)) {
      return setState(
        () => _error = 'Id: lowercase letters, numbers and _ only',
      );
    }
    if (widget.existing == null && widget.takenIds.contains(id)) {
      return setState(() => _error = '"$id" already exists — pick another id');
    }
    if (!_name.has('en')) {
      return setState(() => _error = 'English name is required');
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(
        id,
        _name,
        _icon.text.trim(),
        _color.text.trim(),
        int.tryParse(_priority.text.trim()) ?? widget.initialPriority,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SheetShell(
      title: widget.existing == null ? 'New subject' : 'Edit subject',
      saving: _saving,
      error: _error,
      onSave: _save,
      children: [
        _PlainField(
          controller: _id,
          label: 'Subject id',
          hint: 'cat_math',
          enabled: widget.existing == null,
          helper:
              widget.existing == null
                  ? 'Lowercase, no spaces. Cannot be changed later.'
                  : 'Ids are permanent — questions are filed under them.',
        ),
        const SizedBox(height: 16),
        TrilingualField(
          label: 'Subject name',
          initialValue: _name,
          onChanged: (v) => _name = v,
        ),
        const SizedBox(height: 16),
        _PlainField(
          controller: _icon,
          label: 'Icon asset path',
          hint: 'assets/icons/…',
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _PlainField(
                controller: _color,
                label: 'Colour',
                hint: '#53E6FF',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _PlainField(
                controller: _priority,
                label: 'Order',
                hint: '1',
                keyboardType: TextInputType.number,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ============================================================ chapter sheet ==

class _ChapterSheet extends StatefulWidget {
  final String categoryId;
  final String categoryName;
  final ChapterModel? existing;

  /// Chapter ids already in this subject. A *new* chapter reusing one of
  /// these would silently overwrite it, so the sheet refuses those ids.
  final Set<String> takenIds;
  final int defaultNumber;
  final Future<void> Function(
    String id,
    LocalizedText title,
    LocalizedText description,
    int number,
    bool unlocked,
    bool enabled,
  )
  onSave;

  const _ChapterSheet({
    required this.categoryId,
    required this.categoryName,
    required this.existing,
    required this.takenIds,
    required this.defaultNumber,
    required this.onSave,
  });

  @override
  State<_ChapterSheet> createState() => _ChapterSheetState();
}

class _ChapterSheetState extends State<_ChapterSheet> {
  late final TextEditingController _id;
  late final TextEditingController _number;
  late LocalizedText _title;
  late LocalizedText _description;
  late bool _unlocked;
  late bool _enabled;
  bool _saving = false;
  String? _error;
  AiQuestionGenerator? _translator;

  /// The last id this sheet suggested itself. The admin's own typing is
  /// detected as any deviation from it — from that point the id is theirs
  /// and the sheet stops overwriting it.
  String _autoId = '';
  bool _idTouched = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _idTouched = e != null;
    _autoId =
        e?.chapterId ??
        BulkChapterImporter.suggestChapterId(
          widget.categoryId,
          widget.defaultNumber,
        );
    _id = TextEditingController(text: e?.chapterId ?? _autoId);
    _number = TextEditingController(
      text: '${e?.chapterNumber ?? widget.defaultNumber}',
    );
    _id.addListener(() {
      if (_id.text != _autoId && !_idTouched) {
        setState(() => _idTouched = true);
      }
    });
    _number.addListener(_resuggestId);
    _title = e?.titleText ?? const LocalizedText.empty();
    _description = e?.descriptionText ?? const LocalizedText.empty();
    _unlocked = e?.isUnlocked ?? true;
    _enabled = e?.isEnabled ?? true;
    _translator = AiQuestionGenerator();
  }

  /// Follows the chapter number while the admin has not typed their own id.
  void _resuggestId() {
    if (widget.existing != null || _idTouched) return;
    final number = int.tryParse(_number.text.trim()) ?? widget.defaultNumber;
    final next = BulkChapterImporter.suggestChapterId(
      widget.categoryId,
      number,
    );
    if (next != _autoId) {
      _autoId = next;
      _id.text = next;
    }
  }

  Future<Map<String, String>?> _translateOne(String english) {
    final translator = _translator;
    if (translator == null || english.trim().isEmpty) return Future.value(null);
    return translator.translateField(english.trim());
  }

  @override
  void dispose() {
    _id.dispose();
    _number.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final id = _id.text.trim();
    if (id.isEmpty) return setState(() => _error = 'Chapter id is required');
    if (!RegExp(r'^[a-z0-9_]+$').hasMatch(id)) {
      return setState(
        () => _error = 'Id: lowercase letters, numbers and _ only',
      );
    }
    if (widget.existing == null && widget.takenIds.contains(id)) {
      return setState(() => _error = '"$id" already exists — pick another id');
    }
    if (!_title.has('en')) {
      return setState(() => _error = 'English title is required');
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(
        id,
        _title,
        _description,
        int.tryParse(_number.text.trim()) ?? widget.defaultNumber,
        _unlocked,
        _enabled,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SheetShell(
      title:
          widget.existing == null
              ? 'New chapter · ${widget.categoryName}'
              : 'Edit chapter',
      saving: _saving,
      error: _error,
      onSave: _save,
      children: [
        Row(
          children: [
            Expanded(
              flex: 3,
              child: _PlainField(
                controller: _id,
                label: 'Chapter id',
                hint: 'math_ch_15',
                enabled: widget.existing == null,
                helper: 'Questions are filed under this id.',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _PlainField(
                controller: _number,
                label: 'No.',
                hint: '1',
                keyboardType: TextInputType.number,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TrilingualField(
          label: 'Chapter title',
          initialValue: _title,
          onChanged: (v) => _title = v,
          onTranslate: _translateOne,
        ),
        const SizedBox(height: 16),
        TrilingualField(
          label: 'Description',
          initialValue: _description,
          required: false,
          maxLines: 3,
          onChanged: (v) => _description = v,
          onTranslate: _translateOne,
        ),
        const SizedBox(height: 8),
        // Own Material so the tile ink paints above the sheet's
        // DecoratedBox (Flutter asserts otherwise).
        Material(
          type: MaterialType.transparency,
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _enabled,
            activeThumbColor: AppColors.neonGreen,
            onChanged: (v) => setState(() => _enabled = v),
            title: const Text(
              'Visible to students',
              style: TextStyle(fontSize: 13.5, color: Colors.white),
            ),
            subtitle: const Text(
              'Off hides this chapter from all student chapter lists.',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          ),
        ),
        Material(
          type: MaterialType.transparency,
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _unlocked,
            activeThumbColor: AppColors.neonCyan,
            onChanged: (v) => setState(() => _unlocked = v),
            title: const Text(
              'Unlocked',
              style: TextStyle(fontSize: 13.5, color: Colors.white),
            ),
            subtitle: const Text(
              'Off means students must finish the previous chapter',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          ),
        ),
      ],
    );
  }
}

// ================================================================== shared ==

/// The rounded sheet every admin form sits in — one place for the header,
/// the error line and the save button, so the forms stay consistent.
class _SheetShell extends StatelessWidget {
  final String title;
  final bool saving;
  final String? error;
  final VoidCallback onSave;
  final List<Widget> children;

  const _SheetShell({
    required this.title,
    required this.saving,
    required this.error,
    required this.onSave,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
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
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
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
                  children: children,
                ),
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      size: 15,
                      color: AppColors.neonRed,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        error!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.neonRed,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.neonCyan,
                    foregroundColor: AppColors.bgDark,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: saving ? null : onSave,
                  child:
                      saving
                          ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.bgDark,
                            ),
                          )
                          : const Text(
                            'Save',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                            ),
                          ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single-language text field, styled to match [TrilingualField].
class _PlainField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final String? helper;
  final bool enabled;
  final TextInputType? keyboardType;

  const _PlainField({
    required this.controller,
    required this.label,
    this.hint,
    this.helper,
    this.enabled = true,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          enabled: enabled,
          keyboardType: keyboardType,
          style: TextStyle(
            color: enabled ? Colors.white : AppColors.textMuted,
            fontSize: 14,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 13,
            ),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.05),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.white12),
            ),
          ),
        ),
        if (helper != null) ...[
          const SizedBox(height: 5),
          Text(
            helper!,
            style: const TextStyle(
              fontSize: 10.5,
              color: AppColors.textMuted,
              height: 1.3,
            ),
          ),
        ],
      ],
    );
  }
}
