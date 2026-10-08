import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/app_colors.dart';
import 'admin_toast.dart';
import '../../../../data/models/chapter_model.dart';
import '../../../../data/services/admin_ai_prompt_builder.dart';
import '../../../widgets/glass_card.dart';

/// Copy-paste prompt cards for ChatGPT / Gemini.
class AdminPromptCopyCard extends StatefulWidget {
  final ChapterModel chapter;
  final String subjectName;

  /// The two ends of this workflow: paste the model's JSON back, or generate
  /// a batch through the API key pool. They used to float over the list as
  /// FABs and covered the very card they belong to — now they close it.
  final VoidCallback? onImportJson;
  final VoidCallback? onGenerate;

  const AdminPromptCopyCard({
    super.key,
    required this.chapter,
    required this.subjectName,
    this.onImportJson,
    this.onGenerate,
  });

  @override
  State<AdminPromptCopyCard> createState() => _AdminPromptCopyCardState();
}

class _AdminPromptCopyCardState extends State<AdminPromptCopyCard> {
  final _plainController = TextEditingController();
  bool _copiedWrite = false;
  bool _copiedFix = false;

  @override
  void dispose() {
    _plainController.dispose();
    super.dispose();
  }

  Future<void> _copy(String text, bool isWrite) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    setState(() {
      if (isWrite) {
        _copiedWrite = true;
      } else {
        _copiedFix = true;
      }
    });
    AdminToast.showSuccess(
      context,
      'Prompt copied — paste it into ChatGPT / Gemini.',
    );
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) {
      setState(() {
        _copiedWrite = false;
        _copiedFix = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      borderRadius: 16,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.smart_toy_outlined,
                  color: AppColors.neonPurple,
                  size: 18,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Ask ChatGPT / Gemini',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Copy a prompt, get JSON back, then Import JSON below. Nothing is auto-saved.',
              style: TextStyle(
                fontSize: 11.5,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            _promptRow(
              step: '1',
              title: 'Write 10 questions',
              subtitle: 'Model writes fresh en/bn/hi JSON for this chapter.',
              copied: _copiedWrite,
              onCopy:
                  () => _copy(
                    AdminAiPromptBuilder.buildQuestionBatchPrompt(
                      chapter: widget.chapter,
                      subjectName: widget.subjectName,
                    ),
                    true,
                  ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _plainController,
              minLines: 3,
              maxLines: 6,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText:
                    'Optional: paste plain questions here — step 2 converts them to JSON.',
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
              ),
            ),
            const SizedBox(height: 10),
            _promptRow(
              step: '2',
              title: 'Fix my text into JSON',
              subtitle: 'Model converts the text above into import-ready JSON.',
              copied: _copiedFix,
              enabled: _plainController.text.trim().isNotEmpty,
              onCopy:
                  () => _copy(
                    AdminAiPromptBuilder.buildPlainToJsonPrompt(
                      chapter: widget.chapter,
                      plainQuestions: _plainController.text,
                    ),
                    false,
                  ),
            ),
            if (widget.onImportJson != null || widget.onGenerate != null) ...[
              const SizedBox(height: 14),
              // The two ends of the flow, labelled so the order reads:
              // copy a prompt → then bring the result back (or let the key
              // pool write it). The steps above produce the JSON; these
              // accept it.
              Row(
                children: [
                  Text(
                    'THEN',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.1,
                      color: AppColors.textMuted.withValues(alpha: 0.9),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Divider(
                      height: 1,
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  if (widget.onImportJson != null)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: widget.onImportJson,
                        icon: const Icon(Icons.content_paste_rounded, size: 17),
                        label: const Text('Import JSON'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.neonGold,
                          side: BorderSide(
                            color: AppColors.neonGold.withValues(alpha: 0.55),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  if (widget.onImportJson != null && widget.onGenerate != null)
                    const SizedBox(width: 10),
                  if (widget.onGenerate != null)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: widget.onGenerate,
                        icon: const Icon(Icons.auto_awesome_rounded, size: 17),
                        label: const Text('Generate 10'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.neonPurple,
                          side: BorderSide(
                            color: AppColors.neonPurple.withValues(alpha: 0.6),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Numbered badge, matching the step markers in the Import JSON sheet so
  /// both halves of the workflow read the same way. Dims with the row when
  /// the step is not available yet.
  Widget _stepBadge(String number, {bool enabled = true}) {
    final colour = enabled ? AppColors.neonGold : AppColors.textMuted;
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: colour.withValues(alpha: 0.5)),
      ),
      child: Text(
        number,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w900,
          color: colour,
        ),
      ),
    );
  }

  Widget _promptRow({
    required String step,
    required String title,
    required String subtitle,
    required bool copied,
    required VoidCallback onCopy,
    bool enabled = true,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          _stepBadge(step, enabled: enabled),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            onPressed: enabled ? onCopy : null,
            icon: Icon(
              copied ? Icons.check_rounded : Icons.copy_rounded,
              size: 14,
              color: copied ? AppColors.neonGreen : AppColors.neonCyan,
            ),
            label: Text(
              copied ? 'Copied' : 'Copy prompt',
              style: TextStyle(
                fontSize: 11.5,
                color: copied ? AppColors.neonGreen : AppColors.neonCyan,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
