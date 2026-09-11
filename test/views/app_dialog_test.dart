import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/app/theme/app_dimensions.dart';
import 'package:rasa_route_collaborative_development/app/theme/app_theme.dart';
import 'package:rasa_route_collaborative_development/views/common_widgets/app_dialog.dart';

/// [AppDialog] is the frame behind the Add-Landmark flow's modals - the
/// "Before you start" reminder and the "Leave this form?" confirmation. A
/// plain `AlertDialog` scattered the actions (the app's button theme is
/// full-width), so these tests pin the frame's single aligned column and its
/// graceful behaviour on small screens.
void main() {
  Widget host(List<String> taps) => MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: Builder(
        builder: (BuildContext context) => Center(
          child: ElevatedButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => AppDialog(
                icon: Icons.exit_to_app_rounded,
                title: 'Leave this form?',
                message: 'You can save what you have entered.',
                actions: <Widget>[
                  ElevatedButton(
                    onPressed: () => taps.add('primary'),
                    child: const Text('Save & leave'),
                  ),
                  TextButton(
                    onPressed: () => taps.add('keep'),
                    child: const Text('Keep editing'),
                  ),
                  TextButton(
                    onPressed: () => taps.add('discard'),
                    child: const Text('Discard'),
                  ),
                ],
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );

  testWidgets('centres the badge and heading over one stacked action column', (
    WidgetTester tester,
  ) async {
    final List<String> taps = <String>[];
    await tester.pumpWidget(host(taps));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Leave this form?'), findsOneWidget);
    expect(find.text('You can save what you have entered.'), findsOneWidget);

    // Badge and heading share the dialog's centre line.
    expect(
      tester.getRect(find.byIcon(Icons.exit_to_app_rounded)).center.dx,
      moreOrLessEquals(tester.getRect(find.text('Leave this form?')).center.dx),
    );

    // Every action stretches across the same padded column - one left edge,
    // one width - the thing the old AlertDialog could not do.
    final Finder dialog = find.byType(Dialog);
    Finder inDialog(Finder matching) =>
        find.descendant(of: dialog, matching: matching);

    final Rect scroll = tester.getRect(
      inDialog(find.byType(SingleChildScrollView)),
    );
    final Rect primary = tester.getRect(inDialog(find.byType(ElevatedButton)));
    final Rect keep = tester.getRect(find.text('Keep editing'));
    final Rect discard = tester.getRect(find.text('Discard'));
    expect(primary.left, moreOrLessEquals(scroll.left + AppSpacing.xl));
    expect(primary.width, moreOrLessEquals(scroll.width - 2 * AppSpacing.xl));
    expect(
      tester.getRect(inDialog(find.byType(TextButton)).at(0)).left,
      moreOrLessEquals(primary.left),
    );
    expect(
      tester.getRect(inDialog(find.byType(TextButton)).at(1)).left,
      moreOrLessEquals(primary.left),
    );
    // The quieter choices sit under the primary action, left edges aligned
    // by their own padded width.
    expect(keep.width, lessThanOrEqualTo(primary.width));
    expect(discard.width, lessThanOrEqualTo(primary.width));

    // All three actions are live.
    await tester.tap(find.text('Save & leave'));
    await tester.tap(find.text('Keep editing'));
    await tester.tap(find.text('Discard'));
    expect(taps, <String>['primary', 'keep', 'discard']);
  });

  testWidgets('fits a narrow phone with large text without overflowing', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final List<String> taps = <String>[];
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
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => AppDialog(
                    icon: Icons.exit_to_app_rounded,
                    title: 'Leave this form?',
                    message: 'You can save what you have entered.',
                    actions: <Widget>[
                      ElevatedButton(
                        onPressed: () => taps.add('primary'),
                        child: const Text('Save & leave'),
                      ),
                      TextButton(
                        onPressed: () => taps.add('keep'),
                        child: const Text('Keep editing'),
                      ),
                    ],
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // The card scrolls rather than clipping, and every action stays
    // reachable by scrolling.
    expect(tester.takeException(), isNull);
    for (final String label in <String>[
      'Leave this form?',
      'Save & leave',
      'Keep editing',
    ]) {
      await tester.scrollUntilVisible(
        find.text(label),
        120,
        scrollable: find.byType(Scrollable),
      );
      expect(find.text(label), findsOneWidget);
    }
  });
}
