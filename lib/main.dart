import 'dart:async';

import 'package:admin_api_key_manager/admin_api_key_manager.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'data/providers/auth_provider.dart';
import 'data/providers/battle_provider.dart';
import 'data/providers/locale_provider.dart';
import 'data/providers/quiz_provider.dart';
import 'data/providers/rewards_provider.dart';
import 'data/providers/user_provider.dart';
import 'data/services/ad_service.dart';
import 'data/services/consent_service.dart';
import 'data/services/firebase_options.dart';
import 'data/services/hive_service.dart';
import 'data/services/notification_service.dart';
import 'data/services/onesignal_service.dart';
import 'data/services/sound_service.dart';
import 'data/services/sync_service.dart';
import 'l10n/app_strings.dart';
import 'presentation/app_navigator.dart';
import 'presentation/screens/dashboard/dashboard_screen.dart';
import 'presentation/widgets/app_background.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1) Hive is the source of truth — it must be ready before anything reads.
  await Hive.initFlutter();
  await HiveService.initialize();

  // 1b) Language must be resolved before the first frame, otherwise the app
  //     flashes English for a moment on a Bangla/Hindi device.
  final localeProvider = LocaleProvider()..initialize();

  // Everything below is optional. Empty placeholder WAVs, a slow Play
  // Services handshake, UMP consent fetches and the LLM key pool have all
  // been observed to hang forever on `await` — which freezes the native
  // splash and looks like the app "opened but never started". Hive is the
  // only thing the first frame needs.
  unawaited(SoundService.instance.init());

  // 2) Firebase is optional: the whole app works offline without it.
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(const Duration(seconds: 8));
  } catch (e) {
    debugPrint('Firebase not configured yet: $e');
  }

  // 3) LLM key pool for the admin question generator. Admin-only — a
  //    failure here must not stop the app for a student.
  unawaited(Future(() async {
    try {
      await KeyCache.init().timeout(const Duration(seconds: 5));
      ApiKeyManager.instance.initialize();
    } catch (e) {
      debugPrint('API key manager unavailable: $e');
    }
  }));

  // 4) Replay anything queued while the app was offline, then refresh config.
  unawaitedSync();

  // 5) AdMob consent (UMP) then the ads SDK. For EU/EEA/UK users the Google
  //    consent form is shown after the first frame (dashboard); until it is
  //    resolved every ad request stays gated off. For India and the rest of
  //    the world no form is shown and ads work immediately.
  unawaited(Future(() async {
    try {
      await ConsentService.instance.initialize();
      await AdService.instance.init();
    } catch (e) {
      debugPrint('AdMob not initialised: $e');
    }
  }));

  runApp(QuizBaazApp(localeProvider: localeProvider));

  // After the first frame is scheduled — never before runApp. Click
  // listener must be up so a killed-app tap is not dropped.
  OneSignalService.onNotificationOpen = AppNavigator.handleOpen;
  NotificationService.onNotificationOpen = AppNavigator.handleOpen;
  unawaited(OneSignalService.instance.bootstrap());
}

/// Fire-and-forget startup sync (never blocks the first frame).
void unawaitedSync() {
  unawaited(Future(() async {
    if (!SyncService.isOnline) return;
    await SyncService.drainPending();
    await SyncService.pullConfig();
  }));
}

class QuizBaazApp extends StatelessWidget {
  final LocaleProvider localeProvider;

  const QuizBaazApp({super.key, required this.localeProvider});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: localeProvider),
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()..initialize()),
        ChangeNotifierProvider(
          create: (ctx) => QuizProvider(ctx.read<UserProvider>()),
        ),
        ChangeNotifierProvider(
          create: (ctx) => BattleProvider(ctx.read<UserProvider>()),
        ),
        ChangeNotifierProvider(create: (_) => RewardsProvider()),
      ],
      // Rebuilds the entire MaterialApp when the language changes. The
      // ValueKey is what makes every cached `S.*` string re-read: without it
      // Flutter would happily keep the old element tree and half the screen
      // would stay in the previous language.
      child: Consumer<LocaleProvider>(
        builder: (context, locale, _) => MaterialApp(
          key: ValueKey('app-${locale.appLanguage}'),
          title: S.appTitle,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.darkThemeFor(locale.appLanguage),
          locale: locale.locale,
          supportedLocales:
              kSupportedLanguageCodes.map((code) => Locale(code)).toList(),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          navigatorKey: AppNavigator.key,
          builder: (context, child) => AppBackground(
            child: child ?? const SizedBox.shrink(),
          ),
          home: const DashboardScreen(),
        ),
      ),
    );
  }
}
