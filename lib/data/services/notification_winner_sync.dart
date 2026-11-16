import '../../l10n/app_strings.dart';
import '../models/champion_model.dart';
import '../models/notification_item.dart';
import 'competition_clock.dart';
import 'hive_service.dart';
import 'notification_inbox.dart';

/// Announces yesterday's Daily Quiz winner inside the on-device
/// [NotificationInbox] once per competition day.
///
/// Only announces when real champion data exists for yesterday — never invents
/// placeholder winners on a fresh install or quiet day.
class NotificationWinnerSync {
  NotificationWinnerSync._();

  static const String metaAnnouncedWinnerDate = 'announced_winner_date';

  /// Returns yesterday's competition-day key (`yyyy-MM-dd` in UTC+5:30).
  static String yesterdayKey([DateTime? now]) =>
      CompetitionClock.previousDateKey(CompetitionClock.dateKey(now));

  /// Picks yesterday's #1 champion from [champions] using [CompetitionClock],
  /// sorted by rank so list order does not depend on cache insertion order.
  static ChampionModel? findYesterdayTopChampion(
    List<ChampionModel> champions, {
    DateTime? now,
  }) {
    final key = yesterdayKey(now);
    final list =
        champions.where((c) => c.dateKey == key).toList()
          ..sort((a, b) => a.rank.compareTo(b.rank));
    if (list.isEmpty) return null;
    for (final c in list) {
      if (c.rank == 1) return c;
    }
    return list.first;
  }

  /// True when yesterday's winner has already been recorded in the inbox.
  static bool isAnnouncedForYesterday([DateTime? now]) {
    if (!HiveService.isInitialized) return false;
    return HiveService.getMeta<String>(metaAnnouncedWinnerDate) ==
        yesterdayKey(now);
  }

  /// Pure builder for yesterday's winner inbox card (testable without Hive).
  static NotificationItem? buildWinnerItem({
    required List<ChampionModel> champions,
    required String yesterdayKey,
    required String currentUserId,
    DateTime? now,
  }) {
    final winners =
        champions.where((c) => c.dateKey == yesterdayKey).toList()
          ..sort((a, b) => a.rank.compareTo(b.rank));
    if (winners.isEmpty) return null;

    final top = winners.firstWhere(
      (c) => c.rank == 1,
      orElse: () => winners.first,
    );
    final winnerName = displayNameFor(top);
    if (winnerName.isEmpty) return null;

    var myRank = -1;
    for (var i = 0; i < winners.length; i++) {
      if (championRowBelongsToUser(winners[i], userId: currentUserId)) {
        myRank = winners[i].rank > 0 ? winners[i].rank : (i + 1);
        break;
      }
    }

    final String title;
    final String body;
    if (myRank == 1) {
      title = S.notifWinnerSelfChampTitle;
      body = S.notifWinnerSelfChampBody(score: top.score);
    } else if (myRank > 1) {
      title = S.notifWinnerSelfTopTitle(rank: myRank);
      body = S.notifWinnerSelfTopBody(winner: winnerName, score: top.score);
    } else {
      title = S.notifWinnerTitle(name: winnerName);
      body =
          top.giftName.trim().isNotEmpty
              ? S.notifWinnerBodyWithGift(
                score: top.score,
                gift: top.giftName.trim(),
              )
              : S.notifWinnerBody(score: top.score);
    }

    return NotificationItem(
      id: 'winner_$yesterdayKey',
      kind: NotificationItem.kindWinner,
      title: title,
      body: body,
      open: 'winners',
      receivedAt: now ?? DateTime.now(),
    );
  }

  static String displayNameFor(ChampionModel champion) {
    final full = champion.name.trim();
    if (full.isNotEmpty) return full;
    final user = champion.username.trim();
    if (user.isNotEmpty) return '@$user';
    return '';
  }

  /// Writes yesterday's winner notification to [NotificationInbox] once per
  /// competition day. Returns `true` when a new item was announced.
  static Future<bool> announceIfNeeded({
    required List<ChampionModel> champions,
    required String currentUserId,
    DateTime? now,
  }) async {
    if (!HiveService.isInitialized) return false;
    final yKey = yesterdayKey(now);
    if (HiveService.getMeta<String>(metaAnnouncedWinnerDate) == yKey) {
      return false;
    }

    final item = buildWinnerItem(
      champions: champions,
      yesterdayKey: yKey,
      currentUserId: currentUserId,
      now: now,
    );
    if (item == null) return false;

    await HiveService.setMeta(metaAnnouncedWinnerDate, yKey);
    await NotificationInbox.instance.add(item);
    return true;
  }
}
