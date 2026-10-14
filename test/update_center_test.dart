import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:quizbaaz/data/models/app_config.dart';
import 'package:quizbaaz/data/services/app_update_service.dart';
import 'package:quizbaaz/data/services/app_version.dart';
import 'package:quizbaaz/data/services/hive_service.dart';
import 'package:quizbaaz/data/services/whats_new_catalog.dart';
import 'package:quizbaaz/data/services/update_banner_target.dart';
import 'package:quizbaaz/l10n/app_strings.dart';
import 'package:quizbaaz/presentation/screens/update/update_center_screen.dart';
import 'package:quizbaaz/presentation/widgets/update_banner.dart';

/// The update flow's two promises:
///
///  * the changelog banner appears exactly once per version (never as a
///    surprise modal), and
///  * the Update Center — the banner's destination — always shows the notes
///    plus an update path.
///
/// `checkAfterDashboardReady` is safe to call in tests: on the VM the Play
/// backend answers "nothing available" without touching a platform channel.
void main() {
  late Directory tempDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = await Directory.systemTemp.createTemp('quizbaaz_update_test_');
    Hive.init(tempDir.path);
    await HiveService.initialize();
    S.load('en');
  });

  tearDownAll(() async {
    AppUpdateService.instance.debugReset();
    // A Hive write started inside a testWidgets fake zone can outlive its
    // test, leaving `close()` waiting forever. Drain with a real-clock
    // deadline instead of Future.timeout (whose generic has bitten us
    // across Hive signatures), and clean the temp dir either way.
    final closing = Hive.close();
    var done = false;
    closing.whenComplete(() {
      done = true;
    });
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (!done && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (done) await closing;
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    AppUpdateService.instance.debugReset();
    AppVersion.instance.version = '';
    AppVersion.instance.buildNumber = '';
    await HiveService.setMeta(AppUpdateService.metaLastSeenVersion, null);
    await HiveService.setMeta(AppUpdateService.metaDismissedUpdateCode, null);
  });

  group('shouldOfferChangelog', () {
    test('fresh install never lectures a new student', () {
      expect(
        AppUpdateService.shouldOfferChangelog(
          lastSeenVersion: null,
          currentVersion: '1.0.13',
          bullets: ['new'],
        ),
        isFalse,
      );
    });

    test('same version → nothing to offer', () {
      expect(
        AppUpdateService.shouldOfferChangelog(
          lastSeenVersion: '1.0.13',
          currentVersion: '1.0.13',
          bullets: ['new'],
        ),
        isFalse,
      );
    });

    test('version moved and notes exist → offer', () {
      expect(
        AppUpdateService.shouldOfferChangelog(
          lastSeenVersion: '1.0.12',
          currentVersion: '1.0.13',
          bullets: ['new'],
        ),
        isTrue,
      );
    });

    test('version moved but no notes → stay quiet', () {
      expect(
        AppUpdateService.shouldOfferChangelog(
          lastSeenVersion: '1.0.12',
          currentVersion: '1.0.13',
          bullets: const [],
        ),
        isFalse,
      );
    });

    test('unknown current version → stay quiet', () {
      expect(
        AppUpdateService.shouldOfferChangelog(
          lastSeenVersion: '1.0.12',
          currentVersion: '',
          bullets: ['new'],
        ),
        isFalse,
      );
    });
  });

  group('upcoming release notes (remote config)', () {
    // Regression: on 1.0.20 with a Play update waiting, the Update Center
    // titled its card with the *installed* build and listed 1.0.20's notes,
    // so the incoming update looked like the previous one. The incoming
    // notes now come from `config/app`; these pin the decision rules.
    test('remote notes for a newer release are offered', () {
      expect(
        WhatsNewCatalog.upcomingBullets(
          installedVersion: '1.0.20',
          remoteVersion: '1.0.21',
          remoteNotes: const {
            'en': ['New thing'],
          },
        ),
        ['New thing'],
      );
    });

    test('remote notes equal to installed are not "upcoming"', () {
      expect(
        WhatsNewCatalog.upcomingBullets(
          installedVersion: '1.0.21',
          remoteVersion: '1.0.21',
          remoteNotes: const {
            'en': ['Same thing'],
          },
        ),
        isEmpty,
      );
    });

    test('nothing published remotely → empty, never the old notes', () {
      expect(
        WhatsNewCatalog.upcomingBullets(
          installedVersion: '1.0.20',
          remoteVersion: '',
          remoteNotes: const {},
        ),
        isEmpty,
      );
    });

    test('AppConfig parses the published notes (list and pasted text)', () {
      final fromLists = AppConfig.fromJson(const {
        'latest_release_version': '1.0.21',
        'latest_release_notes': {
          'en': ['One', 'Two'],
          'bn': ['এক'],
        },
      });
      expect(fromLists.latestReleaseVersion, '1.0.21');
      expect(fromLists.latestNotesFor('en'), ['One', 'Two']);
      expect(fromLists.latestNotesFor('bn'), ['এক']);
      // Unknown language falls back to English.
      expect(fromLists.latestNotesFor('hi'), ['One', 'Two']);

      final fromText = AppConfig.fromJson(const {
        'latest_release_version': '1.0.21',
        'latest_release_notes': {'en': "• One\n• Two\n"},
      });
      expect(fromText.latestNotesFor('en'), ['One', 'Two']);

      const untouched = AppConfig();
      expect(untouched.latestReleaseVersion, '');
      expect(untouched.latestNotesFor('en'), isEmpty);
    });
  });

  group('banner flow', () {
    test(
      'after an update the banner offers the changelog exactly once',
      () async {
        AppVersion.instance.version = '1.0.13';
        await HiveService.setMeta(
          AppUpdateService.metaLastSeenVersion,
          '1.0.12',
        );

        await AppUpdateService.instance.checkAfterDashboardReady();
        expect(AppUpdateService.instance.banner, UpdateBannerTarget.whatsNew);

        await AppUpdateService.instance.markChangelogSeen();
        expect(AppUpdateService.instance.banner, UpdateBannerTarget.none);
        expect(
          HiveService.getMeta<String>(AppUpdateService.metaLastSeenVersion),
          '1.0.13',
        );

        // Next readiness check stays quiet for the same version.
        await AppUpdateService.instance.checkAfterDashboardReady();
        expect(AppUpdateService.instance.banner, UpdateBannerTarget.none);
      },
    );

    test('dismissing the banner also marks the version seen', () async {
      AppVersion.instance.version = '1.0.13';
      await HiveService.setMeta(AppUpdateService.metaLastSeenVersion, '1.0.12');

      await AppUpdateService.instance.checkAfterDashboardReady();
      expect(AppUpdateService.instance.banner, UpdateBannerTarget.whatsNew);

      await AppUpdateService.instance.dismissBanner();
      expect(AppUpdateService.instance.banner, UpdateBannerTarget.none);
      expect(
        HiveService.getMeta<String>(AppUpdateService.metaLastSeenVersion),
        '1.0.13',
      );
    });

    test('first launch after a fresh install shows no banner', () async {
      AppVersion.instance.version = '1.0.13';
      await AppUpdateService.instance.checkAfterDashboardReady();
      expect(AppUpdateService.instance.banner, UpdateBannerTarget.none);
    });
  });

  group('UpdateBanner widget', () {
    testWidgets('slides in with the changelog copy and dismisses on ×', (
      tester,
    ) async {
      // Seeding talks to platform channels (PackageInfo fails soft) and Hive
      // file IO — both must run outside the fake-async zone or the awaits
      // deadlock before the first frame.
      await tester.runAsync(() async {
        AppVersion.instance.version = '1.0.13';
        await HiveService.setMeta(
          AppUpdateService.metaLastSeenVersion,
          '1.0.12',
        );
        await AppUpdateService.instance.checkAfterDashboardReady();
      });

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: UpdateBanner())),
      );
      // Post-frame enter flip, then the slide/fade animation.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text(S.whatsNewTitle(v: '1.0.13')), findsOneWidget);
      expect(find.text(S.updateBannerCtaWhatsNew), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);

      // Flip the service back to none through the same listener path the ×
      // tap takes. The tap itself is not driven here: a Hive write started
      // inside the fake-async zone jams the box for later tests, and
      // persistence is already covered by the `banner flow` group above.
      AppUpdateService.instance.debugReset();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text(S.whatsNewTitle(v: '1.0.13')), findsNothing);
    });
  });

  group('UpdateCenterScreen', () {
    testWidgets('shows status, notes and the Play Store action', (
      tester,
    ) async {
      await tester.runAsync(() async {
        AppVersion.instance.version = '1.0.13';
        AppVersion.instance.buildNumber = '14';
        await HiveService.setMeta(
          AppUpdateService.metaLastSeenVersion,
          '1.0.12',
        );
      });

      await tester.binding.setSurfaceSize(const Size(400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const MaterialApp(home: UpdateCenterScreen()));
      // _load() chains the package channel, the Play availability
      // check and a Hive write; each await resolves across pumped frames.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text(S.updateCenterTitle), findsOneWidget);
      expect(find.text(S.updateCenterUpToDate), findsOneWidget);
      expect(find.text(S.whatsNewTitle(v: '1.0.13+14')), findsOneWidget);
      expect(find.text(S.updateCenterOpenStore), findsOneWidget);
      // Opening the screen counts as having seen the changelog — let the
      // real Hive write land, then pump so its fake-zone continuation runs
      // and the write queue is clean for tearDownAll's close.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 250)),
      );
      await tester.pump();
      expect(
        HiveService.getMeta<String>(AppUpdateService.metaLastSeenVersion),
        '1.0.13',
      );
      expect(AppUpdateService.instance.banner, UpdateBannerTarget.none);
    });
  });
}
