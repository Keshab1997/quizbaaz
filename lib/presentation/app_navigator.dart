import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/providers/quiz_provider.dart';
import 'screens/battle/battle_screen.dart';
import 'screens/battle/online_battle_screen.dart';
import 'screens/daily_quiz/daily_quiz_screen.dart';
import 'screens/leaderboard/leaderboard_screen.dart';
import 'screens/shop/shop_screen.dart';

/// Root navigator so a OneSignal tap can open a screen even when the app
/// was killed. [MaterialApp] in `main.dart` must use [key].
class AppNavigator {
  AppNavigator._();

  static final GlobalKey<NavigatorState> key = GlobalKey<NavigatorState>();

  static String? _pendingOpen;

  /// Handles a OneSignal `additionalData.open` value.
  ///
  /// Known values: `daily_quiz`, `battle`, `online_battle`, `leaderboard`,
  /// `shop`. Anything else (or null) just brings the app to the dashboard.
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
        try {
          ctx.read<QuizProvider>().startDailyQuiz();
        } catch (_) {}
        nav.push(
          MaterialPageRoute<void>(builder: (_) => const DailyQuizScreen()),
        );
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
      default:
        break;
    }
  }
}
