import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizbaaz/presentation/screens/admin/widgets/admin_toast.dart';

void main() {
  Future<void> pumpHost(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder:
              (context) => Scaffold(
                body: Column(
                  children: [
                    TextButton(
                      onPressed:
                          () => AdminToast.showSuccess(context, 'Saved ok'),
                      child: const Text('success'),
                    ),
                    TextButton(
                      onPressed:
                          () => AdminToast.showError(context, 'Failed badly'),
                      child: const Text('error'),
                    ),
                    TextButton(
                      onPressed:
                          () => AdminToast.showSuccess(
                            context,
                            'Added 3',
                            actionLabel: 'Undo',
                            onAction: () {},
                          ),
                      child: const Text('action'),
                    ),
                  ],
                ),
              ),
        ),
      ),
    );
  }

  testWidgets('toast slides in at the top and auto-dismisses', (tester) async {
    await pumpHost(tester);
    await tester.tap(find.text('success'));
    await tester.pump();

    expect(find.text('Saved ok'), findsOneWidget);
    final top = tester.getTopLeft(find.text('Saved ok')).dy;
    expect(top, lessThan(200));

    await tester.pump(const Duration(milliseconds: 2600));
    expect(find.text('Saved ok'), findsNothing);
  });

  testWidgets('error toast stays longer than success', (tester) async {
    await pumpHost(tester);
    await tester.tap(find.text('error'));
    await tester.pump();

    await tester.pump(const Duration(milliseconds: 2600));
    expect(find.text('Failed badly'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1500));
    expect(find.text('Failed badly'), findsNothing);
  });

  testWidgets('a new toast replaces the current one', (tester) async {
    await pumpHost(tester);
    await tester.tap(find.text('success'));
    await tester.pump();
    expect(find.text('Saved ok'), findsOneWidget);

    await tester.tap(find.text('error'));
    await tester.pump();
    expect(find.text('Saved ok'), findsNothing);
    expect(find.text('Failed badly'), findsOneWidget);
  });

  testWidgets('tap dismisses; action button fires then dismisses', (
    tester,
  ) async {
    var undone = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder:
              (context) => Scaffold(
                body: TextButton(
                  onPressed:
                      () => AdminToast.showSuccess(
                        context,
                        'Added 3',
                        actionLabel: 'Undo',
                        onAction: () => undone = true,
                      ),
                  child: const Text('go'),
                ),
              ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pump();
    expect(find.text('Undo'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect(undone, isTrue);
    expect(find.text('Added 3'), findsNothing);
  });
}
