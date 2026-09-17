import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../data/services/sound_service.dart';

/// Compact language switcher for the quiz screens.
class QuizLanguagePills extends StatelessWidget {
  /// Codes the current question has content for.
  final List<String> available;

  /// Currently displayed language.
  final String selected;

  final ValueChanged<String> onSelected;

  const QuizLanguagePills({
    super.key,
    required this.available,
    required this.selected,
    required this.onSelected,
  });

  static const Map<String, String> _labels = {
    'en': 'EN',
    'bn': 'বাং',
    'hi': 'हिं',
  };

  @override
  Widget build(BuildContext context) {
    if (available.length < 2) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Colors.white.withValues(alpha: 0.06),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final code in available) _pill(code),
        ],
      ),
    );
  }

  Widget _pill(String code) {
    final isSelected = code == selected;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: isSelected
          ? null
          : () {
              SoundService.instance.playClick();
              onSelected(code);
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: isSelected ? AppColors.neonCyan : Colors.transparent,
        ),
        child: Text(
          _labels[code] ?? code.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.2,
            color: isSelected ? AppColors.bgDark : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
