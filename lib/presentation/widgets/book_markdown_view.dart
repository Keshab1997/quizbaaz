import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants/app_colors.dart';

/// Rich, student-friendly Markdown renderer tailored for AI Book Buddy study
/// notes (headings, tables, bullet lists, callouts, and `**bold**` highlights).
///
/// Uses Hind Siliguri when [languageCode] is `'bn'` (or when Bengali glyphs are
/// detected in [markdown]) so Bengali study notes always render crisply even
/// when the app's global UI language is English.
class BookMarkdownView extends StatelessWidget {
  final String markdown;
  final String languageCode;
  final double textScale;

  const BookMarkdownView({
    super.key,
    required this.markdown,
    required this.languageCode,
    this.textScale = 1.08,
  });

  static final RegExp _bengaliGlyphs = RegExp(r'[\u0980-\u09FF]');

  TextStyle _baseFont({
    required double fontSize,
    FontWeight fontWeight = FontWeight.w500,
    Color color = AppColors.textPrimary,
    double height = 1.65,
  }) {
    final scaled = fontSize * textScale;
    final useBanglaFont =
        languageCode == 'bn' || _bengaliGlyphs.hasMatch(markdown);
    if (useBanglaFont) {
      return GoogleFonts.hindSiliguri(
        fontSize: scaled,
        fontWeight: fontWeight,
        color: color,
        height: height,
      );
    }
    return GoogleFonts.poppins(
      fontSize: scaled,
      fontWeight: fontWeight,
      color: color,
      height: height,
    );
  }

  @override
  Widget build(BuildContext context) {
    final blocks = _parseBlocks(markdown);
    if (blocks.isEmpty) return const SizedBox.shrink();

    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < blocks.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            _buildBlock(blocks[i]),
          ],
        ],
      ),
    );
  }

  Widget _buildBlock(_MdBlock block) {
    switch (block.kind) {
      case _MdKind.divider:
        return Container(
          height: 1.2,
          margin: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.neonCyan.withValues(alpha: 0.05),
                AppColors.neonCyan.withValues(alpha: 0.45),
                AppColors.neonPurple.withValues(alpha: 0.45),
                AppColors.neonPurple.withValues(alpha: 0.05),
              ],
            ),
          ),
        );

      case _MdKind.heading:
        final isTop = block.headingLevel <= 2;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              colors: [
                AppColors.neonCyan.withValues(alpha: isTop ? 0.18 : 0.11),
                AppColors.neonPurple.withValues(alpha: 0.08),
              ],
            ),
            border: const Border(
              left: BorderSide(color: AppColors.neonCyan, width: 3.5),
            ),
          ),
          child: Text.rich(
            _inlineSpans(
              block.text,
              base: _baseFont(
                fontSize: isTop ? 18.0 : 16.5,
                fontWeight: FontWeight.w800,
                color: AppColors.neonCyan,
                height: 1.4,
              ),
              boldColor: Colors.white,
            ),
          ),
        );

      case _MdKind.callout:
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            color: AppColors.neonGold.withValues(alpha: 0.11),
            border: Border.all(
              color: AppColors.neonGold.withValues(alpha: 0.45),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.lightbulb_rounded,
                  color: AppColors.neonGold,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text.rich(
                  _inlineSpans(
                    block.text,
                    base: _baseFont(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                      height: 1.55,
                    ),
                    boldColor: AppColors.neonGold,
                  ),
                ),
              ),
            ],
          ),
        );

      case _MdKind.bulletList:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < block.items.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.neonCyan,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text.rich(
                      _inlineSpans(
                        block.items[i],
                        base: _baseFont(fontSize: 16.0),
                        boldColor: AppColors.neonGold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        );

      case _MdKind.numberedList:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < block.items.length; i++) ...[
              if (i > 0) const SizedBox(height: 9),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 3),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.neonPurple.withValues(alpha: 0.24),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.neonPurple.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Text(
                      '${i + 1}',
                      style: _baseFont(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.neonCyan,
                        height: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text.rich(
                      _inlineSpans(
                        block.items[i],
                        base: _baseFont(fontSize: 16.0),
                        boldColor: AppColors.neonGold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        );

      case _MdKind.table:
        return _buildTable(block.tableRows);

      case _MdKind.paragraph:
        return Text.rich(
          _inlineSpans(
            block.text,
            base: _baseFont(fontSize: 16.0),
            boldColor: AppColors.neonGold,
          ),
        );
    }
  }

  Widget _buildTable(List<List<String>> rows) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final colCount = rows.fold<int>(
      1,
      (maxCols, r) => r.length > maxCols ? r.length : maxCols,
    );

    List<String> padRow(List<String> row) => [
      for (var c = 0; c < colCount; c++) c < row.length ? row[c] : '',
    ];

    final header = padRow(rows.first);
    final body = rows.skip(1).map(padRow).toList();

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.neonCyan.withValues(alpha: 0.35)),
        color: AppColors.bgDark.withValues(alpha: 0.48),
      ),
      clipBehavior: Clip.antiAlias,
      child: Table(
        border: TableBorder(
          horizontalInside: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
          ),
          verticalInside: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
          ),
        ),
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          TableRow(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.neonCyan.withValues(alpha: 0.22),
                  AppColors.neonPurple.withValues(alpha: 0.22),
                ],
              ),
            ),
            children: [
              for (final cell in header)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Text.rich(
                    _inlineSpans(
                      cell,
                      base: _baseFont(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.neonCyan,
                        height: 1.35,
                      ),
                      boldColor: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
          for (var r = 0; r < body.length; r++)
            TableRow(
              decoration: BoxDecoration(
                color:
                    r.isOdd
                        ? Colors.white.withValues(alpha: 0.03)
                        : Colors.transparent,
              ),
              children: [
                for (var c = 0; c < body[r].length; c++)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Text.rich(
                      _inlineSpans(
                        body[r][c],
                        base: _baseFont(
                          fontSize: 14.8,
                          fontWeight:
                              c == 0 ? FontWeight.w600 : FontWeight.w700,
                          color:
                              c == 0
                                  ? AppColors.textPrimary
                                  : AppColors.neonGold,
                          height: 1.45,
                        ),
                        boldColor: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  TextSpan _inlineSpans(
    String raw, {
    required TextStyle base,
    required Color boldColor,
  }) {
    final pattern = RegExp(r'\*\*(.+?)\*\*|`([^`]+)`');
    final spans = <InlineSpan>[];
    var cursor = 0;

    for (final match in pattern.allMatches(raw)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: raw.substring(cursor, match.start)));
      }
      final boldText = match.group(1);
      final codeText = match.group(2);
      if (boldText != null) {
        spans.add(
          TextSpan(
            text: boldText,
            style: base.copyWith(fontWeight: FontWeight.w800, color: boldColor),
          ),
        );
      } else if (codeText != null) {
        spans.add(
          TextSpan(
            text: ' $codeText ',
            style: base.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.neonCyan,
              backgroundColor: AppColors.neonCyan.withValues(alpha: 0.14),
            ),
          ),
        );
      }
      cursor = match.end;
    }

    if (cursor < raw.length) {
      spans.add(TextSpan(text: raw.substring(cursor)));
    }
    return TextSpan(style: base, children: spans);
  }

  static final RegExp _dividerRe = RegExp(r'^[-*_]{3,}$');
  static final RegExp _headingRe = RegExp(r'^(#{1,4})\s+(.+)$');
  static final RegExp _bulletRe = RegExp(r'^(?:[-*•])\s+(.+)$');
  static final RegExp _numberedRe = RegExp(r'^(?:[\d০-৯]+[.)])\s+(.+)$');
  static final RegExp _tableSepRe = RegExp(r'^\|?[\s:\-|]+\|?$');

  static bool _isTableLine(String trimmed) =>
      trimmed.startsWith('|') && trimmed.indexOf('|', 1) > 0;

  static List<String> _splitTableCells(String line) {
    var s = line.trim();
    if (s.startsWith('|')) s = s.substring(1);
    if (s.endsWith('|')) s = s.substring(0, s.length - 1);
    return s.split('|').map((c) => c.trim()).toList();
  }

  static List<_MdBlock> _parseBlocks(String input) {
    final lines = input.replaceAll('\r\n', '\n').split('\n');
    final blocks = <_MdBlock>[];
    var i = 0;

    while (i < lines.length) {
      final trimmed = lines[i].trim();
      if (trimmed.isEmpty) {
        i++;
        continue;
      }

      if (_dividerRe.hasMatch(trimmed)) {
        blocks.add(const _MdBlock.divider());
        i++;
        continue;
      }

      final headingMatch = _headingRe.firstMatch(trimmed);
      if (headingMatch != null) {
        blocks.add(
          _MdBlock.heading(
            level: headingMatch.group(1)!.length,
            text: headingMatch.group(2)!.trim(),
          ),
        );
        i++;
        continue;
      }

      if (_isTableLine(trimmed)) {
        final rows = <List<String>>[];
        while (i < lines.length && _isTableLine(lines[i].trim())) {
          final rowLine = lines[i].trim();
          if (!_tableSepRe.hasMatch(rowLine)) {
            rows.add(_splitTableCells(rowLine));
          }
          i++;
        }
        if (rows.isNotEmpty) {
          blocks.add(_MdBlock.table(rows));
        }
        continue;
      }

      if (_bulletRe.hasMatch(trimmed)) {
        final items = <String>[];
        while (i < lines.length) {
          final m = _bulletRe.firstMatch(lines[i].trim());
          if (m == null) break;
          items.add(m.group(1)!.trim());
          i++;
        }
        blocks.add(_MdBlock.bulletList(items));
        continue;
      }

      if (_numberedRe.hasMatch(trimmed)) {
        final items = <String>[];
        while (i < lines.length) {
          final m = _numberedRe.firstMatch(lines[i].trim());
          if (m == null) break;
          items.add(m.group(1)!.trim());
          i++;
        }
        blocks.add(_MdBlock.numberedList(items));
        continue;
      }

      if (trimmed.startsWith('>')) {
        final quoteLines = <String>[];
        while (i < lines.length && lines[i].trim().startsWith('>')) {
          quoteLines.add(lines[i].trim().replaceFirst(RegExp(r'^>\s*'), ''));
          i++;
        }
        blocks.add(_MdBlock.callout(quoteLines.join(' ')));
        continue;
      }

      // Collect consecutive plain lines into one paragraph or callout
      final paraLines = <String>[];
      while (i < lines.length) {
        final t = lines[i].trim();
        if (t.isEmpty ||
            _dividerRe.hasMatch(t) ||
            _headingRe.hasMatch(t) ||
            _isTableLine(t) ||
            _bulletRe.hasMatch(t) ||
            _numberedRe.hasMatch(t) ||
            t.startsWith('>')) {
          break;
        }
        paraLines.add(t);
        i++;
      }
      final joined = paraLines.join('\n');
      if (_looksLikeCallout(joined)) {
        blocks.add(_MdBlock.callout(joined));
      } else {
        blocks.add(_MdBlock.paragraph(joined));
      }
    }

    return blocks;
  }

  static bool _looksLikeCallout(String text) {
    final lower = text.toLowerCase();
    return text.startsWith('**মূল কথা') ||
        text.startsWith('**মনে রাখবে') ||
        text.startsWith('**টিপস') ||
        text.startsWith('**গুরুত্বপূর্ণ') ||
        lower.startsWith('**key takeaway') ||
        lower.startsWith('**important') ||
        lower.startsWith('**remember') ||
        lower.startsWith('**summary') ||
        text.startsWith('**मुख्य बात') ||
        text.startsWith('**याद रखें');
  }
}

enum _MdKind {
  divider,
  heading,
  callout,
  bulletList,
  numberedList,
  table,
  paragraph,
}

class _MdBlock {
  final _MdKind kind;
  final String text;
  final int headingLevel;
  final List<String> items;
  final List<List<String>> tableRows;

  const _MdBlock._({
    required this.kind,
    this.text = '',
    this.headingLevel = 2,
    this.items = const [],
    this.tableRows = const [],
  });

  const _MdBlock.divider() : this._(kind: _MdKind.divider);
  const _MdBlock.heading({required int level, required String text})
    : this._(kind: _MdKind.heading, headingLevel: level, text: text);
  const _MdBlock.callout(String text)
    : this._(kind: _MdKind.callout, text: text);
  const _MdBlock.bulletList(List<String> items)
    : this._(kind: _MdKind.bulletList, items: items);
  const _MdBlock.numberedList(List<String> items)
    : this._(kind: _MdKind.numberedList, items: items);
  const _MdBlock.table(List<List<String>> rows)
    : this._(kind: _MdKind.table, tableRows: rows);
  const _MdBlock.paragraph(String text)
    : this._(kind: _MdKind.paragraph, text: text);
}
