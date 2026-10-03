import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/providers/quiz_provider.dart';
import 'screens/battle/battle_screen.dart';
import 'screens/battle/online_battle_screen.dart';
import 'screens/daily_quiz/daily_quiz_ready_screen.dart';
import 'screens/daily_quiz/daily_quiz_screen.dart';
import 'screens/leaderboard/leaderboard_screen.dart';
import 'screens/shop/shop_screen.dart';
import 'screens/update/update_center_screen.dart';

/// Root navigator so a OneSignal tap can open a screen even when the app
/// was killed. [MaterialApp] in `main.dart` must use [key].
class AppNavigator {
  AppNavigator._();

  static final GlobalKey<NavigatorState> key = GlobalKey<NavigatorState>();

  static String? _pendingOpen;

  /// Handles a OneSignal `additionalData.open` value.
  ///
  /// Known values: `daily_quiz`, `battle`, `online_battle`, `leaderboard`,
  /// `shop`, `app_update`. Anything else (or null) just brings the app to
  /// the dashboard.
  ///
  /// `daily_quiz` opens the ready gate (or resumes a live run): tapping the
  /// 19:00 reminder must not spend the day's counted attempt on its own.
  /// `app_update` opens the Update Center (changelog + Play update) — it is
  /// the landing pad for release pushes and the dashboard banner.
  static void handleOpen(String? open) {
    if (open == null || open.isEmpty) return;
    final nav = key.currentState;
    if (nav == null) {
      _pendingOpen = open;
      return;
    }
    _open(nav, open);
  }

  /// Call after the first dashboard frame so a cold-start tap is not lost.
  static void flushPending() {
    final open = _pendingOpen;
    _pendingOpen = null;
    if (open == null) return;
    handleOpen(open);
  }

  static void _open(NavigatorState nav, String open) {
    final ctx = nav.context;
    switch (open) {
      case 'daily_quiz':
        // A reminder tap must never drop the player straight into a live
        // ranked run — the day's one counted attempt would be spent before
        // they decided to play. It opens the ready gate instead; the run
        // starts when they press START there. A daily run that is already
        // in flight is resumed rather than restarted.
        nav.push(MaterialPageRoute<void>(builder: (_) => _dailyQuizEntry(ctx)));
        break;
      case 'battle':
        nav.push(MaterialPageRoute<void>(builder: (_) => const BattleScreen()));
        break;
      case 'online_battle':
        nav.push(
          MaterialPageRoute<void>(builder: (_) => const OnlineBattleScreen()),
        );
        break;
      case 'leaderboard':
        nav.push(
          MaterialPageRoute<void>(builder: (_) => const LeaderboardScreen()),
        );
        break;
      case 'shop':
        nav.push(MaterialPageRoute<void>(builder: (_) => const ShopScreen()));
        break;
      case 'app_update':
        nav.push(
          MaterialPageRoute<void>(builder: (_) => const UpdateCenterScreen()),
        );
        break;
      default:
        break;
    }
  }

  /// Where a `daily_quiz` open lands: the live run when there is one to
  /// resume, the ready gate otherwise.
  static Widget _dailyQuizEntry(BuildContext ctx) {
    var liveRun = false;
    try {
      liveRun = ctx.read<QuizProvider>().hasLiveDailyRun;
    } catch (_) {
      // No QuizProvider in scope — the gate is the harmless option.
    }
    return liveRun ? const DailyQuizScreen() : const DailyQuizReadyScreen();
  }
}
