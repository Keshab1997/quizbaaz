import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/chapter_model.dart';
import '../../../data/models/localized_text.dart';
import '../../../data/providers/auth_provider.dart';
import '../../../data/repositories/quiz_repository.dart';
import '../../../data/services/chapter_catalog_service.dart';
import '../../widgets/glass_card.dart';
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
          final matchesSubject =
              category.nameText.toJson().values.any(
                    (v) => v.toLowerCase().contains(needle),
                  );
          final chapters = category.chapters
              .where((c) =>
                  matchesSubject ||
                  c.titleText
                      .toJson()
                      .values
                      .any((v) => v.toLowerCase().contains(needle)))
              .toList();
          return CategoryModel(
            categoryId: category.categoryId,
            nameText: category.nameText,
            categoryIcon: category.categoryIcon,
            colorHex: category.colorHex,
            totalChapters: chapters.length,
            chapters: chapters,
          );
        })
        .where((c) => c.chapters.isNotEmpty)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final categories = _visible;
    final totalQuestions =
        _counts.values.fold<int>(0, (sum, n) => sum + n);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Chapter Manager',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        actions: [
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
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.neonCyan))
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
                        child: Text('No chapters match that search.',
                            style: TextStyle(color: AppColors.textSecondary)),
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
        0, (sum, c) => sum + c.chapters.length);
    final empty = _counts.values.where((n) => n == 0).length;

    return GlassCard(
      borderRadius: 18,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          _stat('Subjects', '${_categories.length}', AppColors.neonPurple),
          _stat('Chapters', '$chapterCount', AppColors.neonCyan),
          _stat('Questions', '$totalQuestions', AppColors.neonGreen),
          _stat('Empty', '$empty',
              empty == 0 ? AppColors.neonGreen : AppColors.neonGold),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 19, fontWeight: FontWeight.w900, color: color)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  fontSize: 10.5, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _searchBox() {
    return TextField(
      style: const TextStyle(color: Colors.white, fontSize: 14),
      onChanged: (v) => setState(() => _search = v),
      decoration: InputDecoration(
        hintText: 'Search subject or chapter…',
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

  Widget _categoryCard(CategoryModel category) {
    final color = _parseColor(category.colorHex);
    final questionTotal = category.chapters
        .fold<int>(0, (sum, c) => sum + (_counts[c.chapterId] ?? 0));

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
                  color: Colors.white),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                '${category.chapters.length} chapters · $questionTotal questions',
                style: const TextStyle(
                    fontSize: 11.5, color: AppColors.textSecondary),
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
                      icon: const Icon(Icons.add_rounded,
                          size: 16, color: AppColors.neonCyan),
                      label: const Text('Add chapter',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.neonCyan)),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () => _editSubject(category),
                      icon: const Icon(Icons.edit_rounded,
                          size: 15, color: AppColors.textSecondary),
                      label: const Text('Edit subject',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.textSecondary)),
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
      CategoryModel category, ChapterModel chapter, Color color) {
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
              child: Text('${chapter.chapterNumber}',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w900,
                      color: color.withValues(alpha: 0.8))),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(chapter.titleText.resolve('en'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.white)),
                  const SizedBox(height: 2),
                  Text(coverage,
                      style: const TextStyle(
                          fontSize: 10.5, color: AppColors.textMuted)),
                ],
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
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
              tooltip: chapter.isEnabled
                  ? 'Hide from students'
                  : 'Show to students',
              iconSize: 18,
              color: chapter.isEnabled
                  ? AppColors.neonGreen
                  : AppColors.neonGold,
              icon: Icon(chapter.isEnabled
                  ? Icons.visibility_rounded
                  : Icons.visibility_off_rounded),
              onPressed: () => _setChapterEnabled(
                category,
                chapter,
                !chapter.isEnabled,
              ),
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
    final missing = ['en', 'bn', 'hi']
        .where((code) => !chapter.titleText.has(code))
        .toList();
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
        builder: (_) => QuestionManagerScreen(
          categoryId: category.categoryId,
          subjectName: category.nameText.resolve('en'),
          chapter: chapter,
        ),
      ),
    ).then((_) => _load());
  }

  // --------------------------------------------------------------- editing --

  Future<void> _addSubject() => _editSubject(null);

  Future<void> _editSubject(CategoryModel? existing) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SubjectSheet(
        existing: existing,
        onSave: (id, name, icon, color, priority) => _catalog.saveCategory(
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

  Future<void> _editChapter(
      CategoryModel category, ChapterModel? existing) async {
    final nextNumber = category.chapters.isEmpty
        ? 1
        : category.chapters
                .map((c) => c.chapterNumber)
                .reduce((a, b) => a > b ? a : b) +
            1;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ChapterSheet(
        categoryName: category.categoryName,
        existing: existing,
        defaultNumber: nextNumber,
        onSave: (id, title, description, number, unlocked, enabled) =>
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
          content: Text(isEnabled
              ? '${chapter.titleText.resolve('en')} is now visible to students.'
              : '${chapter.titleText.resolve('en')} is now hidden from students.'),
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

// ============================================================ subject sheet ==

class _SubjectSheet extends StatefulWidget {
  final CategoryModel? existing;
  final Future<void> Function(
    String id,
    LocalizedText name,
    String icon,
    String colorHex,
    int priority,
  ) onSave;

  const _SubjectSheet({required this.existing, required this.onSave});

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
        text: e?.categoryIcon ?? 'assets/icons/coin_and_gem_3d.png');
    _color = TextEditingController(text: e?.colorHex ?? '#53E6FF');
    _priority = TextEditingController(text: '1');
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
        int.tryParse(_priority.text.trim()) ?? 1,
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
          helper: widget.existing == null
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
            controller: _icon, label: 'Icon asset path', hint: 'assets/icons/…'),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _PlainField(
                  controller: _color, label: 'Colour', hint: '#53E6FF'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _PlainField(
                  controller: _priority,
                  label: 'Order',
                  hint: '1',
                  keyboardType: TextInputType.number),
            ),
          ],
        ),
      ],
    );
  }
}

// ============================================================ chapter sheet ==

class _ChapterSheet extends StatefulWidget {
  final String categoryName;
  final ChapterModel? existing;
  final int defaultNumber;
  final Future<void> Function(
    String id,
    LocalizedText title,
    LocalizedText description,
    int number,
    bool unlocked,
    bool enabled,
  ) onSave;

  const _ChapterSheet({
    required this.categoryName,
    required this.existing,
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

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _id = TextEditingController(text: e?.chapterId ?? '');
    _number =
        TextEditingController(text: '${e?.chapterNumber ?? widget.defaultNumber}');
    _title = e?.titleText ?? const LocalizedText.empty();
    _description = e?.descriptionText ?? const LocalizedText.empty();
    _unlocked = e?.isUnlocked ?? true;
    _enabled = e?.isEnabled ?? true;
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
      title: widget.existing == null
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
                  keyboardType: TextInputType.number),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TrilingualField(
          label: 'Chapter title',
          initialValue: _title,
          onChanged: (v) => _title = v,
        ),
        const SizedBox(height: 16),
        TrilingualField(
          label: 'Description',
          initialValue: _description,
          required: false,
          maxLines: 3,
          onChanged: (v) => _description = v,
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
            title: const Text('Visible to students',
                style: TextStyle(fontSize: 13.5, color: Colors.white)),
            subtitle: const Text(
                'Off hides this chapter from all student chapter lists.',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          ),
        ),
        Material(
          type: MaterialType.transparency,
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _unlocked,
            activeThumbColor: AppColors.neonCyan,
            onChanged: (v) => setState(() => _unlocked = v),
            title: const Text('Unlocked',
                style: TextStyle(fontSize: 13.5, color: Colors.white)),
            subtitle: const Text('Off means students must finish the previous chapter',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
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
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.9),
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
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(title,
                        style: const TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800,
                            color: Colors.white)),
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
                    children: children),
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded,
                        size: 15, color: AppColors.neonRed),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(error!,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.neonRed)),
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
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: saving ? null : onSave,
                  child: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.bgDark),
                        )
                      : const Text('Save',
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
        Text(label,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
                letterSpacing: 0.3)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          enabled: enabled,
          keyboardType: keyboardType,
          style: TextStyle(
              color: enabled ? Colors.white : AppColors.textMuted,
              fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle:
                const TextStyle(color: AppColors.textMuted, fontSize: 13),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.05),
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
          Text(helper!,
              style: const TextStyle(
                  fontSize: 10.5, color: AppColors.textMuted, height: 1.3)),
        ],
      ],
    );
  }
}
