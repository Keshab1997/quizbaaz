import 'dart:async';

import 'package:admin_api_key_manager/admin_api_key_manager.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
// kIsWeb/kDebugMode for the App Check provider choice below. material.dart
// does not re-export them, so the import has to be explicit like everywhere
// else in the repo.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:smart_ocr_ai_bridge/smart_ocr_ai_bridge.dart';

import 'core/theme/app_theme.dart';
import 'data/providers/auth_provider.dart';
import 'data/providers/battle_provider.dart';
import 'data/providers/book_buddy_provider.dart';
import 'data/providers/locale_provider.dart';
import 'data/providers/quiz_provider.dart';
import 'data/providers/rewards_provider.dart';
import 'data/providers/user_provider.dart';
import 'data/services/ad_service.dart';
import 'data/services/app_version.dart';
import 'data/services/consent_service.dart';
import 'data/services/firebase_options.dart';
import 'data/services/hive_service.dart';
import 'data/services/notification_service.dart';
import 'data/services/onesignal_service.dart';
import 'data/services/sound_service.dart';
import 'data/services/sync_service.dart';
import 'l10n/app_strings.dart';
import 'presentation/app_navigator.dart';
import 'presentation/screens/battle/battle_screen.dart';
import 'presentation/screens/battle/online_battle_screen.dart';
import 'presentation/screens/splash/splash_screen.dart';
import 'presentation/widgets/app_background.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 0) A widget that throws while building is painted, in a release build, as a
  //    featureless grey rectangle: no text, no stack, nothing to report. The
  //    Free models page did exactly that on the phone and it cost a whole build
  //    cycle of guessing. Paint the exception itself instead.
  ErrorWidget.builder = (details) => VisibleErrorPanel(details: details);

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
  unawaited(AppVersion.load());

  // 2) Firebase is optional: the whole app works offline without it.
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(const Duration(seconds: 8));

    // 2b) App Check — every trusted callable (functions/, region asia-south1)
    //     enforces App Check, so the client must attest before those calls are
    //     accepted. Debug builds use the debug provider (register the printed
    //     token under Firebase console → App Check → Manage debug tokens);
    //     release builds use Play Integrity / Device Check. Web needs a
    //     reCAPTCHA v3 site key (`webProvider: ReCaptchaV3Provider('<key>')`)
    //     and is skipped here so the marketing web preview keeps working.
    try {
      if (!kIsWeb) {
        await FirebaseAppCheck.instance.activate(
          // ignore: deprecated_member_use — still supported and version-stable.
          androidProvider:
              kDebugMode
                  ? AndroidProvider.debug
                  : AndroidProvider.playIntegrity,
          // ignore: deprecated_member_use
          appleProvider:
              kDebugMode ? AppleProvider.debug : AppleProvider.deviceCheck,
        );
      }
    } catch (e) {
      debugPrint('App Check not activated: $e');
    }
  } catch (e) {
    debugPrint('Firebase not configured yet: $e');
  }

  // 3) LLM key pool for the admin question generator & AI Book Buddy.
  //    Non-blocking — a failure here must never stop the app for a student.
  unawaited(
    Future(() async {
      try {
        await KeyCache.init().timeout(const Duration(seconds: 5));
        ApiKeyManager.instance.initialize();
        SmartOcrAiBridge.instance.bindApiKeyManager(ApiKeyManager.instance);
      } catch (e) {
        debugPrint('API key manager unavailable: $e');
      }
    }),
  );

  // 4) Replay anything queued while the app was offline, then refresh config.
  unawaitedSync();

  // 5) AdMob consent (UMP) then the ads SDK. For EU/EEA/UK users the Google
  //    consent form is shown after the first frame (dashboard); until it is
  //    resolved every ad request stays gated off. For India and the rest of
  //    the world no form is shown and ads work immediately.
  unawaited(
    Future(() async {
      try {
        await ConsentService.instance.initialize();
        await AdService.instance.init();
      } catch (e) {
        debugPrint('AdMob not initialised: $e');
      }
    }),
  );

  runApp(QuizBaazApp(localeProvider: localeProvider));

  // After the first frame is scheduled — never before runApp. Click
  // listener must be up so a killed-app tap is not dropped.
  OneSignalService.onNotificationOpen = AppNavigator.handleOpen;
  NotificationService.onNotificationOpen = AppNavigator.handleOpen;
  unawaited(OneSignalService.instance.bootstrap());
}

/// Fire-and-forget startup sync (never blocks the first frame).
void unawaitedSync() {
  unawaited(
    Future(() async {
      if (!SyncService.isOnline) return;
      await SyncService.drainPending();
      await SyncService.pullConfig();
    }),
  );
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
        ChangeNotifierProvider(create: (_) => BookBuddyProvider()),
      ],
      // Rebuilds the entire MaterialApp when the language changes. The
      // ValueKey is what makes every cached `S.*` string re-read: without it
      // Flutter would happily keep the old element tree and half the screen
      // would stay in the previous language.
      child: Consumer<LocaleProvider>(
        builder:
            (context, locale, _) => MaterialApp(
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
              builder:
                  (context, child) =>
                      AppBackground(child: child ?? const SizedBox.shrink()),
              // Named routes are registered as a safety net: the arena used to be
              // opened with `pushNamed('/battle')` while MaterialApp had no
              // `routes` table and no `onGenerateRoute`, so a challenge accept
              // died with "Could not find a generator for route /battle" (R10).
              // The screens now push typed MaterialPageRoutes; these names keep
              // deep links (and any older call site) working.
              onGenerateRoute: (settings) {
                switch (settings.name) {
                  case '/battle':
                    return MaterialPageRoute<void>(
                      settings: settings,
                      builder: (_) => const BattleScreen(),
                    );
                  case '/online_battle':
                    return MaterialPageRoute<void>(
                      settings: settings,
                      builder: (_) => const OnlineBattleScreen(),
                    );
                  default:
                    // Never throw for an unknown name — a notification payload is
                    // not worth losing the app over. Land on the home screen.
                    debugPrint(
                      'QuizBaaz: no route for "${settings.name}" — opening home.',
                    );
                    return MaterialPageRoute<void>(
                      settings: settings,
                      builder: (_) => const SplashScreen(),
                    );
                }
              },
              home: const SplashScreen(),
            ),
      ),
    );
  }
}


/// The replacement for Flutter's grey box.
///
/// Flutter's default `ErrorWidget` in a release build is a plain grey
/// rectangle — it deliberately hides the exception, which turns "the page is
/// blank" into a guessing game with no way to report anything. This paints the
/// exception text and the top of the stack, with a Copy button, so the phone can
/// hand back a real bug report.
///
/// Deliberately built from the most basic widgets only: this is what runs when
/// the theme, the provider tree or the whole app already failed to build.
class VisibleErrorPanel extends StatefulWidget {
  const VisibleErrorPanel({super.key, required this.details});

  final FlutterErrorDetails details;

  @override
  State<VisibleErrorPanel> createState() => _VisibleErrorPanelState();
}

class _VisibleErrorPanelState extends State<VisibleErrorPanel> {
  bool _copied = false;

  String get _report {
    final buffer = StringBuffer()..writeln(widget.details.exceptionAsString());
    final context = widget.details.context?.toString();
    if (context != null && context.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('while: $context');
    }
    final stack = widget.details.stack?.toString() ?? '';
    if (stack.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln(stack.split('\n').take(14).join('\n'));
    }
    // A crash report gets pasted into a chat; an API key must never ride along.
    final text = buffer
        .toString()
        .replaceAll(RegExp(r'sk-[A-Za-z0-9_\-]{6,}'), 'sk-***');
    return text.length <= 4000 ? text : '${text.substring(0, 4000)}\n…';
  }

  @override
  Widget build(BuildContext context) {
    const mono = TextStyle(
      fontFamily: 'monospace',
      fontSize: 11,
      height: 1.45,
      color: Color(0xFFF3F4F6),
    );
    return Material(
      color: const Color(0xFF1F1B24),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'This part of the screen failed to draw',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFFCA5A5),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Send this text back and the cause is fixable without guessing.',
                style: TextStyle(fontSize: 11, color: Color(0xFFD1D5DB)),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF14111A),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF3F3A4A)),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(_report, style: mono),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              FilledButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _report));
                  setState(() => _copied = true);
                },
                child: Text(_copied ? 'Copied' : 'Copy error'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
