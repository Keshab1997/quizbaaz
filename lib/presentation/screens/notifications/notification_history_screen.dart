import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../data/models/notification_item.dart';
import '../../../data/providers/user_provider.dart';
import '../../../data/services/haptic_service.dart';
import '../../../data/services/notification_inbox.dart';
import '../../../data/services/sound_service.dart';
import '../../../l10n/app_strings.dart';
import '../../app_navigator.dart';
import '../../widgets/glass_card.dart';

/// Inbox of captured local reminders and OneSignal pushes.
///
/// Hive only — a fresh install is empty on purpose.
class NotificationHistoryScreen extends StatefulWidget {
  const NotificationHistoryScreen({super.key});

  @override
  State<NotificationHistoryScreen> createState() =>
      _NotificationHistoryScreenState();
}

class _NotificationHistoryScreenState extends State<NotificationHistoryScreen> {
  @override
  void initState() {
    super.initState();
    NotificationInbox.instance.reload();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationInbox.instance.markAllRead();
    });
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          S.notifInboxClear,
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          S.notifInboxClearConfirm,
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              S.cancel,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              S.notifInboxClear,
              style: const TextStyle(color: AppColors.neonRed),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await NotificationInbox.instance.clear();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(S.notifInboxCleared)),
    );
  }

  void _openItem(NotificationItem item) {
    SoundService.instance.play('ui_click');
    Haptics.tap();
    NotificationInbox.instance.markRead(item.id);
    final open = item.open;
    if (open == null || open.isEmpty) return;
    AppNavigator.handleOpen(open);
  }

  @override
  Widget build(BuildContext context) {
    final notificationsOn =
        context.watch<UserProvider>().setting(UserProvider.settingNotifications);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
              color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          S.notifInboxTitle,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
        actions: [
          ListenableBuilder(
            listenable: NotificationInbox.instance,
            builder: (context, _) {
              if (NotificationInbox.instance.isEmpty) {
                return const SizedBox.shrink();
              }
              return IconButton(
                tooltip: S.notifInboxClear,
                icon: const Icon(Icons.delete_outline_rounded,
                    color: AppColors.neonCyan),
                onPressed: _clearAll,
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: GlassCard(
              borderRadius: 16,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              borderColor: (notificationsOn
                      ? AppColors.neonCyan
                      : AppColors.neonOrange)
                  .withValues(alpha: 0.28),
              child: Row(
                children: [
                  Icon(
                    notificationsOn
                        ? Icons.notifications_active_rounded
                        : Icons.notifications_off_outlined,
                    color: notificationsOn
                        ? AppColors.neonCyan
                        : AppColors.neonOrange,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      notificationsOn ? S.notifBellOn : S.notifBellOff,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: NotificationInbox.instance,
              builder: (context, _) {
                final items = NotificationInbox.instance.items;
                if (items.isEmpty) return _buildEmpty();
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                  itemCount: items.length,
                  itemBuilder: (context, index) =>
                      _buildCard(items[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.notifications_none_rounded,
              size: 80,
              color: AppColors.textMuted.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              S.notifInboxNone,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              S.notifInboxEmptyBody,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(NotificationItem item) {
    final color =
        item.isReminder ? AppColors.neonGold : AppColors.neonPurple;
    final kindLabel =
        item.isReminder ? S.notifKindReminder : S.notifKindPush;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        borderRadius: 18,
        borderColor: color.withValues(alpha: item.read ? 0.18 : 0.45),
        onTap: () => _openItem(item),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.14),
                border: Border.all(color: color.withValues(alpha: 0.4)),
              ),
              child: Icon(
                item.isReminder
                    ? Icons.alarm_rounded
                    : Icons.campaign_rounded,
                color: color,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          kindLabel,
                          style: TextStyle(
                            color: color,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _formatWhen(item.receivedAt),
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (item.body.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      item.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (!item.read) ...[
              const SizedBox(width: 8),
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 6),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.neonCyan,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatWhen(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return S.notifJustNow;
    if (diff.inHours < 1) return S.notifMinutesAgo(n: diff.inMinutes);
    if (diff.inDays == 0) {
      final hh = date.hour.toString().padLeft(2, '0');
      final mm = date.minute.toString().padLeft(2, '0');
      return '$hh:$mm';
    }
    if (diff.inDays == 1) return S.yesterday;
    if (diff.inDays < 7) return S.daysAgo(n: diff.inDays);
    return '${date.day}/${date.month}';
  }
}
