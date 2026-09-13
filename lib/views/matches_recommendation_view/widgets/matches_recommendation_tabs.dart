import 'package:flutter/material.dart';

import '../../../domain_model/matches_recommendation_tab.dart';

class MatchesRecommendationTabs extends StatelessWidget {
  const MatchesRecommendationTabs({
    super.key,
    required this.selectedTab,
    required this.onChanged,
  });

  final MatchesRecommendationTab selectedTab;
  final ValueChanged<MatchesRecommendationTab> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<MatchesRecommendationTab>(
      segments: const <ButtonSegment<MatchesRecommendationTab>>[
        ButtonSegment<MatchesRecommendationTab>(
          value: MatchesRecommendationTab.restaurants,
          icon: Icon(Icons.restaurant_outlined),
          label: Text('Restaurants'),
        ),
        ButtonSegment<MatchesRecommendationTab>(
          value: MatchesRecommendationTab.submittedLandmarks,
          icon: Icon(Icons.add_location_alt_outlined),
          label: Text('Submitted Landmarks'),
        ),
      ],
      selected: <MatchesRecommendationTab>{selectedTab},
      style: ButtonStyle(
        textStyle: WidgetStatePropertyAll<TextStyle?>(
          Theme.of(context).textTheme.labelMedium,
        ),
        visualDensity: VisualDensity.compact,
      ),
      onSelectionChanged: (Set<MatchesRecommendationTab> selection) {
        onChanged(selection.first);
      },
    );
  }
}
