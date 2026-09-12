import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/app/theme/app_dimensions.dart';
import 'package:rasa_route_collaborative_development/app/theme/app_theme.dart';
import 'package:rasa_route_collaborative_development/views/common_widgets/add_landmark_reminder_dialog.dart';

/// `showAddLandmarkReminderDialog` gates the Add Landmark form: the tourist
/// must ACKNOWLEDGE the "stay at the restaurant" rule before the form opens.
/// These tests pin the wording, the two outcomes, and that the aligned layout
/// survives a narrow phone with large text.
void main() {
  /// One button that opens the dialog and records what it returned - true
  /// only on "I Understand", false on "Not Now" (or a swipe/back dismissal).
  Widget host(List<bool> outcomes) => MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: Builder(
        builder: (BuildContext context) => Center(
          child: ElevatedButton(
            onPressed: () async {
              outcomes.add(await showAddLandmarkReminderDialog(context));
            },
            child: const Text('Add New Landmark'),
          ),
        ),
      ),
    ),
  );

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('Add New Landmark'));
    await tester.pumpAndSettle();
  }

  testWidgets('states the rule and returns true only when acknowledged', (
    WidgetTester tester,
  ) async {
    final List<bool> outcomes = <bool>[];
    await tester.pumpWidget(host(outcomes));
    await open(tester);

    expect(find.text('Before you start'), findsOneWidget);
    expect(
      find.text(
        'New landmarks can only be added while you are at the restaurant.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Fill in and submit the form within the restaurant range.'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Leaving early? Save your progress - it is kept for 24 hours. '
        'Check the Profile screen to continue later.',
      ),
      findsOneWidget,
    );

    await tester.ensureVisible(find.text('I Understand'));
    await tester.tap(find.text('I Understand'));
    await tester.pumpAndSettle();

    expect(outcomes, <bool>[true]);
  });

  testWidgets('aligns the badge, rules and actions on one column', (
    WidgetTester tester,
  ) async {
    final List<bool> outcomes = <bool>[];
    await tester.pumpWidget(host(outcomes));
    await open(tester);

    final Finder dialog = find.byType(Dialog);
    Finder inDialog(Finder matching) =>
        find.descendant(of: dialog, matching: matching);

    // Badge and heading share the dialog's centre line.
    expect(
      tester.getRect(find.byIcon(Icons.storefront_rounded)).center.dx,
      moreOrLessEquals(tester.getRect(find.text('Before you start')).center.dx),
    );

    // Both rule texts start on the same edge...
    expect(
      tester
          .getRect(
            find.text(
              'Fill in and submit the form within the restaurant range.',
            ),
          )
          .left,
      moreOrLessEquals(
        tester
            .getRect(
              find.text(
                'Leaving early? Save your progress - it is kept for 24 hours. '
                'Check the Profile screen to continue later.',
              ),
            )
            .left,
      ),
    );

    // ...and the two actions stretch across the same padded column.
    final Rect scroll = tester.getRect(
      inDialog(find.byType(SingleChildScrollView)),
    );
    final Rect primary = tester.getRect(inDialog(find.byType(ElevatedButton)));
    final Rect secondary = tester.getRect(inDialog(find.byType(TextButton)));
    expect(primary.left, moreOrLessEquals(scroll.left + AppSpacing.xl));
    expect(primary.width, moreOrLessEquals(scroll.width - 2 * AppSpacing.xl));
    expect(secondary.left, moreOrLessEquals(primary.left));
    expect(secondary.width, moreOrLessEquals(primary.width));
  });

  testWidgets('"Not Now" dismisses without acknowledging', (
    WidgetTester tester,
  ) async {
    final List<bool> outcomes = <bool>[];
    await tester.pumpWidget(host(outcomes));
    await open(tester);

    await tester.ensureVisible(find.text('Not Now'));
    await tester.tap(find.text('Not Now'));
    await tester.pumpAndSettle();

    expect(outcomes, <bool>[false]);
  });

  testWidgets('fits a narrow phone with large text without overflowing', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final List<bool> outcomes = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        builder: (BuildContext context, Widget? child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  outcomes.add(await showAddLandmarkReminderDialog(context));
                },
                child: const Text('Add New Landmark'),
              ),
            ),
          ),
        ),
      ),
    );
    await open(tester);

    // The dialog scrolls rather than clipping, and both actions stay
    // reachable.
    expect(tester.takeException(), isNull);
    expect(find.text('I Understand'), findsOneWidget);
    expect(find.text('Not Now'), findsOneWidget);
  });
}
