import '../../l10n/app_strings.dart';

/// A single piece of authored copy in every language the app ships.
///
/// Quiz content is **pre-translated and committed**, not machine-translated at
/// runtime. That was a deliberate reversal: an exam-prep app cannot risk a
/// machine mangling "Real Numbers" or "current", it must work offline in areas
/// with poor connectivity, and a bundled string costs nothing per user.
///
/// JSON accepts two shapes:
///
/// ```json
/// "question": { "en": "What is …", "bn": "কী …", "hi": "क्या …" }
/// "question": "What is …"          // shorthand: English only
/// ```
///
/// The shorthand exists so a draft can be written quickly and translated
/// later; [resolve] degrades to English rather than showing a blank.
class LocalizedText {
  final Map<String, String> _values;

  const LocalizedText(this._values);

  const LocalizedText.empty() : _values = const {};

  /// Builds one from either a `{lang: text}` map or a bare English string.
  factory LocalizedText.fromJson(dynamic raw) {
    if (raw == null) return const LocalizedText.empty();

    if (raw is String) {
      final text = raw.trim();
      return text.isEmpty
          ? const LocalizedText.empty()
          : LocalizedText({'en': text});
    }

    if (raw is Map) {
      final values = <String, String>{};
      raw.forEach((key, value) {
        if (value is String && value.trim().isNotEmpty) {
          values['$key'] = value.trim();
        }
      });
      return LocalizedText(values);
    }

    return const LocalizedText.empty();
  }

  /// Text for [languageCode], falling back to English, then to any language
  /// that has content, then to an empty string.
  ///
  /// The fallback chain is what lets a chapter ship with Bangla ready and
  /// Hindi still pending without breaking the screen.
  String resolve(String languageCode) {
    final exact = _values[languageCode];
    if (exact != null && exact.isNotEmpty) return exact;

    final english = _values['en'];
    if (english != null && english.isNotEmpty) return english;

    for (final value in _values.values) {
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  /// Text in the language the UI is currently showing.
  String get current => resolve(S.code);

  /// True when no language has any content.
  bool get isEmpty => _values.values.every((v) => v.isEmpty);

  bool get isNotEmpty => !isEmpty;

  /// Language codes that actually have content.
  Iterable<String> get languages => _values.keys;

  /// True when [languageCode] has its own translation rather than a fallback.
  bool has(String languageCode) => (_values[languageCode] ?? '').isNotEmpty;

  Map<String, String> toJson() => Map<String, String>.from(_values);

  @override
  String toString() => current;
}
