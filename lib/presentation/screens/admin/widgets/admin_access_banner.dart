import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../data/services/admin_access_service.dart';
import '../../../widgets/glass_card.dart';

/// Banner explaining WHY an admin write failed with permission-denied.
class AdminAccessBanner extends StatefulWidget {
  final Object error;
  const AdminAccessBanner({super.key, required this.error});
  @override
  State<AdminAccessBanner> createState() => _AdminAccessBannerState();
}

class _AdminAccessBannerState extends State<AdminAccessBanner> {
  bool? _hasClaim;
  bool _checking = true;
  bool _refreshing = false;
  String? _uid;

  @override
  void initState() {
    super.initState();
    AdminAccessService.hasAdminClaim().then((has) {
      if (!mounted) return;
      setState(() {
        _hasClaim = has;
        _uid = AdminAccessService.uid;
        _checking = false;
      });
    });
  }

  Future<void> _refreshClaim() async {
    setState(() => _refreshing = true);
    final has = await AdminAccessService.refresh();
    if (!mounted) return;
    setState(() {
      _hasClaim = has;
      _refreshing = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          has ? 'Admin claim active — try saving again.' : 'Still no claim.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDenied = AdminAccessService.isPermissionDenied(widget.error);
    return GlassCard(
      borderRadius: 14,
      borderColor: AppColors.neonRed.withValues(alpha: 0.5),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.cloud_off_rounded, color: AppColors.neonRed),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Cloud permission nei — save blocked',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              isDenied
                  ? 'Rules sudhu admin:true claim-ke admin bole. Claim na thakle write deny hobe.'
                  : 'Cloud-e save kora jayni: ${widget.error}',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 8),
            if (_checking)
              const Text('Checking admin claim…')
            else
              Text('Claim: ${_hasClaim == true ? 'YES' : 'NO'}\nuid: $_uid'),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _refreshing ? null : _refreshClaim,
                    icon: const Icon(Icons.refresh_rounded, size: 14),
                    label: const Text('Refresh claim'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                        _uid == null
                            ? null
                            : () =>
                                Clipboard.setData(ClipboardData(text: _uid!)),
                    icon: const Icon(Icons.copy_rounded, size: 14),
                    label: const Text('Copy my uid'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact claim status chip for the admin dashboard header.
class AdminClaimChip extends StatefulWidget {
  const AdminClaimChip({super.key});
  @override
  State<AdminClaimChip> createState() => _AdminClaimChipState();
}

class _AdminClaimChipState extends State<AdminClaimChip> {
  bool? _hasClaim;

  @override
  void initState() {
    super.initState();
    AdminAccessService.hasAdminClaim().then((has) {
      if (mounted) setState(() => _hasClaim = has);
    });
  }

  @override
  Widget build(BuildContext context) {
    final has = _hasClaim;
    final color =
        has == null
            ? AppColors.textMuted
            : has
            ? AppColors.neonGreen
            : AppColors.neonGold;
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        has == null
            ? 'Claim: …'
            : has
            ? 'Claim: admin ✓'
            : 'Claim: missing',
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
