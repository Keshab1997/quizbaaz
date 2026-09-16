import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/providers/locale_provider.dart';
import '../../../l10n/app_strings.dart';
import '../../widgets/glass_card.dart';

/// Language settings.
///
/// A single choice drives the entire app: interface *and* quiz content, since
/// questions ship pre-translated in the same three languages. Keeping it to
/// one control is the point — an earlier build had a second "quiz language"
/// backed by runtime machine translation, which meant the app could show a
/// screen in one language and its question in another, and depended on the
/// network to do it.
class LanguageScreen extends StatelessWidget {
  const LanguageScreen({super.key});

  static const _appLanguages = <String, String>{
    'en': 'English',
    'bn': 'বাংলা',
    'hi': 'हिन्दी',
  };

  static const _appLanguageSubtitles = <String, String>{
    'en': 'English',
    'bn': 'Bengali',
    'hi': 'Hindi',
  };

  @override
  Widget build(BuildContext context) {
    final localeProvider = context.watch<LocaleProvider>();

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          S.languageTitle,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
          children: [
            Text(
              S.languageSubtitle,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 20),

            // ------------------------------------------------ app language --
            _SectionLabel(S.languageAppSection),
            const SizedBox(height: 10),
            GlassCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  _OptionTile(
                    title: S.languageSystemDefault,
                    subtitle: 'Auto',
                    icon: Icons.phone_android_rounded,
                    selected: localeProvider.followSystem,
                    onTap: () async {
                      await localeProvider.useSystemLanguage();
                      if (context.mounted) _toast(context);
                    },
                  ),
                  for (final entry in _appLanguages.entries)
                    _OptionTile(
                      title: entry.value,
                      subtitle: _appLanguageSubtitles[entry.key],
                      icon: Icons.language_rounded,
                      selected: !localeProvider.followSystem &&
                          localeProvider.appLanguage == entry.key,
                      onTap: () async {
                        await localeProvider.setAppLanguage(entry.key);
                        if (context.mounted) _toast(context);
                      },
                    ),
                ],
              ),
            ),

          ],
        ),
      ),
    );
  }

  void _toast(BuildContext context) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(S.languageChanged)));
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.2,
        color: AppColors.textSecondary,
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _OptionTile({
    required this.title,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    // Own Material so the ripple paints above the GlassCard instead of
    // being hidden by it (Flutter asserts otherwise).
    return Material(
      type: MaterialType.transparency,
      child: ListTile(
        onTap: onTap,
        leading: Icon(
          icon,
          size: 20,
          color: selected ? AppColors.neonCyan : AppColors.textSecondary,
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: selected ? FontWeight.bold : FontWeight.w500,
            color: selected ? AppColors.neonCyan : AppColors.textPrimary,
          ),
        ),
        subtitle: subtitle == null
            ? null
            : Text(
                subtitle!,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textSecondary,
                ),
              ),
        trailing: selected
            ? const Icon(Icons.check_circle_rounded,
                color: AppColors.neonCyan, size: 20)
            : null,
      ),
    );
  }
}
