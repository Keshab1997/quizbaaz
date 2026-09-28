import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../data/models/localized_text.dart';
import '../../../../l10n/app_strings.dart';

/// One translatable field, edited in every language the app ships.
///
/// The problem this solves: a trilingual question has three stems, four
/// options × three, and three explanations — 21 text boxes. Stacked flat, an
/// admin cannot see at a glance which ones are still empty, and a chapter ends
/// up half-translated without anyone noticing until a student sees English in
/// a Bangla quiz.
///
/// So: one box, a tab per language, and a **filled dot on each tab**. A gap is
/// visible without opening anything.
///
/// ```text
/// ┌─────────────────────────────────────────┐
/// │ Question *              [EN●][BN●][HI○] │
/// │ ┌─────────────────────────────────────┐ │
/// │ │ Which enzyme in saliva breaks down… │ │
/// │ └─────────────────────────────────────┘ │
/// │ ⚠ Hindi is empty                        │
/// └─────────────────────────────────────────┘
/// ```
class TrilingualField extends StatefulWidget {
  final String label;

  /// Starting content. Later changes are reported through [onChanged].
  final LocalizedText initialValue;

  final ValueChanged<LocalizedText> onChanged;

  /// When true, an empty language is an error rather than a hint.
  final bool required;

  final int minLines;
  final int maxLines;
  final String? hintText;

  /// Shown under the box, e.g. "Numbers and formulas stay the same".
  final String? helperText;

  /// Optional per-field translate action, wired by the parent screen when a
  /// key pool is available. Receives the English text, returns bn and hi.
  final Future<Map<String, String>?> Function(String english)? onTranslate;

  const TrilingualField({
    super.key,
    required this.label,
    required this.initialValue,
    required this.onChanged,
    this.required = true,
    this.minLines = 1,
    this.maxLines = 4,
    this.hintText,
    this.helperText,
    this.onTranslate,
  });

  @override
  State<TrilingualField> createState() => _TrilingualFieldState();
}

class _TrilingualFieldState extends State<TrilingualField> {
  late final Map<String, TextEditingController> _controllers;
  String _active = 'en';
  bool _translating = false;

  @override
  void initState() {
    super.initState();
    _controllers = {
      for (final code in kSupportedLanguageCodes)
        code: TextEditingController(
          // resolve() would fall back to English and make an empty Hindi look
          // filled — exactly the mistake this widget exists to prevent.
          text:
              widget.initialValue.has(code)
                  ? widget.initialValue.resolve(code)
                  : '',
        )..addListener(_emit),
    };
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _emit() {
    widget.onChanged(_current);
    setState(() {}); // refresh the filled dots
  }

  LocalizedText get _current => LocalizedText({
    for (final entry in _controllers.entries)
      if (entry.value.text.trim().isNotEmpty)
        entry.key: entry.value.text.trim(),
  });

  List<String> get _missing =>
      kSupportedLanguageCodes
          .where((code) => _controllers[code]!.text.trim().isEmpty)
          .toList();

  Future<void> _translate() async {
    final english = _controllers['en']!.text.trim();
    if (english.isEmpty || widget.onTranslate == null) return;

    setState(() => _translating = true);
    final result = await widget.onTranslate!(english);
    if (!mounted) return;

    if (result != null) {
      result.forEach((code, text) {
        final controller = _controllers[code];
        // Never clobber something the admin already wrote.
        if (controller != null && controller.text.trim().isEmpty) {
          controller.text = text;
        }
      });
    }
    setState(() => _translating = false);
  }

  @override
  Widget build(BuildContext context) {
    final missing = _missing;
    final hasEnglish = _controllers['en']!.text.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                widget.required ? '${widget.label} *' : widget.label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                  letterSpacing: 0.3,
                ),
              ),
            ),
            for (final code in kSupportedLanguageCodes) _tab(code),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _controllers[_active],
          minLines: widget.minLines,
          maxLines: widget.maxLines,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: widget.hintText ?? _hintFor(_active),
            hintStyle: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 13,
            ),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.05),
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
              borderSide: BorderSide(
                color:
                    widget.required && missing.isNotEmpty
                        ? AppColors.neonGold.withValues(alpha: 0.4)
                        : Colors.white12,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.neonCyan),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _statusLine(missing)),
            if (widget.onTranslate != null)
              _translateButton(enabled: hasEnglish && missing.isNotEmpty),
          ],
        ),
      ],
    );
  }

  Widget _tab(String code) {
    final filled = _controllers[code]!.text.trim().isNotEmpty;
    final selected = _active == code;

    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => setState(() => _active = code),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color:
                selected
                    ? AppColors.neonCyan.withValues(alpha: 0.18)
                    : Colors.white.withValues(alpha: 0.05),
            border: Border.all(
              color:
                  selected
                      ? AppColors.neonCyan.withValues(alpha: 0.6)
                      : Colors.white12,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                code.toUpperCase(),
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.4,
                  color:
                      selected ? AppColors.neonCyan : AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 5),
              // The whole point of the widget: an empty language is visible
              // without tapping into it.
              Icon(
                filled ? Icons.circle : Icons.circle_outlined,
                size: 7,
                color: filled ? AppColors.neonGreen : AppColors.neonGold,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusLine(List<String> missing) {
    if (missing.isEmpty) {
      return Row(
        children: [
          const Icon(
            Icons.check_circle_rounded,
            size: 12,
            color: AppColors.neonGreen,
          ),
          const SizedBox(width: 5),
          Text(
            'All languages filled',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.neonGreen.withValues(alpha: 0.9),
            ),
          ),
        ],
      );
    }

    final names = missing.map(_languageName).join(', ');
    final colour =
        widget.required ? AppColors.neonGold : AppColors.textSecondary;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.error_outline_rounded, size: 12, color: colour),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            widget.helperText == null
                ? 'Missing: $names'
                : 'Missing: $names · ${widget.helperText}',
            style: TextStyle(fontSize: 11, color: colour, height: 1.3),
          ),
        ),
      ],
    );
  }

  Widget _translateButton({required bool enabled}) {
    return TextButton.icon(
      onPressed: enabled && !_translating ? _translate : null,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        minimumSize: const Size(0, 30),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon:
          _translating
              ? const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.neonCyan,
                ),
              )
              : const Icon(
                Icons.auto_awesome_rounded,
                size: 14,
                color: AppColors.neonCyan,
              ),
      label: Text(
        _translating ? 'Translating…' : 'Fill from English',
        style: const TextStyle(fontSize: 11.5, color: AppColors.neonCyan),
      ),
    );
  }

  String _hintFor(String code) {
    switch (code) {
      case 'bn':
        return 'বাংলায় লিখুন…';
      case 'hi':
        return 'हिन्दी में लिखें…';
      default:
        return 'Write in English…';
    }
  }

  static String _languageName(String code) {
    switch (code) {
      case 'bn':
        return 'Bangla';
      case 'hi':
        return 'Hindi';
      default:
        return 'English';
    }
  }
}
