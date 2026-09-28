import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:quizbaaz/data/providers/user_provider.dart';
import 'package:quizbaaz/data/services/hive_service.dart';
import 'package:quizbaaz/l10n/app_strings.dart';
import 'package:quizbaaz/presentation/screens/profile/avatar_selection_screen.dart';

/// Regression tests for the avatar picker layout on small screens
/// (the category tabs once overflowed their row on a ~340 dp window).
void main() {
  late Directory tempDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = await Directory.systemTemp.createTemp('quizbaaz_avatar_test_');
    Hive.init(tempDir.path);
    await HiveService.initialize();
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Widget host(UserProvider provider) =>
      ChangeNotifierProvider<UserProvider>.value(
        value: provider,
        child: const MaterialApp(home: AvatarSelectionScreen()),
      );

  testWidgets('category tabs fit without overflowing on a narrow screen',
      (tester) async {
    S.load('en');
    await tester.binding.setSurfaceSize(const Size(340, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(host(UserProvider()));
    await tester.pump();

    expect(tester.takeException(), isNull);
    // All three tabs are still reachable.
    expect(find.text('👦 Male'), findsOneWidget);
    expect(find.text('👧 Female'), findsOneWidget);
    expect(find.text('👑 Premium'), findsOneWidget);
  });
}
