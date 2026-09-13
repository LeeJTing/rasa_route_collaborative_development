import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/app/theme/app_colors.dart';
import 'package:rasa_route_collaborative_development/app/theme/app_dimensions.dart';
import 'package:rasa_route_collaborative_development/views/common_widgets/preference_option_card.dart';

/// The option card draws a full-colour photo now, so selection can no longer be
/// shown by tinting the artwork the way the old SVG icons were. It has to be
/// visible on the box itself: a frame over the photo, a neutral rim around the
/// photo so the frame has contrast, and a glow under the box.
void main() {
  Widget host({required bool isSelected, String? iconAsset}) {
    return MaterialApp(
      home: Scaffold(
        body: PreferenceOptionCard(
          label: 'Sweet',
          isSelected: isSelected,
          onTap: _noop,
          iconAsset: iconAsset,
        ),
      ),
    );
  }

  /// The card's own box - the only Container it builds.
  Container box(WidgetTester tester) {
    return tester.widget<Container>(
      find.descendant(
        of: find.byType(PreferenceOptionCard),
        matching: find.byType(Container),
      ),
    );
  }

  /// The decoration under the photo: the neutral fill and the glow.
  BoxDecoration underDecoration(WidgetTester tester) =>
      box(tester).decoration! as BoxDecoration;

  /// The frame over the photo: the border that must stay visible.
  BoxDecoration frameDecoration(WidgetTester tester) =>
      box(tester).foregroundDecoration! as BoxDecoration;

  testWidgets('renders a bundled photo asset without error', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      host(isSelected: false, iconAsset: 'assets/images/profile/sweet.png'),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Sweet'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('the photo is inset by a neutral rim so the frame shows', (
    WidgetTester tester,
  ) async {
    // A 1pt frame lying directly on photo pixels has nothing to contrast
    // with, so the photo sits inside a sliver of the box's own fill.
    await tester.pumpWidget(
      host(isSelected: false, iconAsset: 'assets/images/profile/sweet.png'),
    );
    await tester.pump();

    final ClipRRect photoClip = tester.widget<ClipRRect>(
      find.descendant(
        of: find.byType(PreferenceOptionCard),
        matching: find.byType(ClipRRect),
      ),
    );
    expect(
      photoClip.borderRadius,
      BorderRadius.circular(AppRadius.lg - AppSizes.profileOptionPhotoInset),
    );

    // The rim itself. Found by value rather than as "the only Padding":
    // Container also wraps its decoration in a zero Padding of its own.
    expect(
      find.byWidgetPredicate(
        (Widget widget) =>
            widget is Padding &&
            widget.padding ==
                const EdgeInsets.all(AppSizes.profileOptionPhotoInset),
      ),
      findsOneWidget,
    );
  });

  testWidgets('an unselected box is framed with the neutral outline', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(host(isSelected: false));

    final BoxDecoration frame = frameDecoration(tester);
    final Border border = frame.border! as Border;

    expect(border.top.color, AppColors.outline);
    expect(border.top.width, AppSizes.borderWidth);
    expect(underDecoration(tester).boxShadow, isNull);
    // Behind the photo the ring would be invisible (and leak at the edges), so
    // it must stay out of the decoration underneath.
    expect(underDecoration(tester).border, isNull);
  });

  testWidgets('selection is carried by the green border and its glow', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(host(isSelected: true));

    final BoxDecoration frame = frameDecoration(tester);
    final Border border = frame.border! as Border;

    expect(border.top.color, AppColors.success);
    expect(border.top.width, AppSizes.borderWidthStrong);

    final BoxDecoration under = underDecoration(tester);
    expect(under.boxShadow, isNotNull);
    expect(under.boxShadow!.single.color, AppColors.profileOptionSelectedGlow);
    // Frame and clipped photo must share one corner radius, or the glowing
    // ring would sit on a different curve than the photo it frames.
    expect(frame.borderRadius, under.borderRadius);
  });

  testWidgets('an option with no photo falls back to the glyph, no error', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(host(isSelected: false));

    expect(tester.takeException(), isNull);
    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(Icons.local_dining), findsOneWidget);
  });
}

void _noop() {}
