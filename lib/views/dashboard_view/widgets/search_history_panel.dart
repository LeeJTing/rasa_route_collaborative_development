import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';
import '../../../app/theme/app_text_styles.dart';

/// A15 / REQ102_104 - what this device searched for recently, offered the
/// moment the search box is opened on an empty field.
///
/// It takes the place the result list would take and wears the same card, so
/// the box has one panel under it at a time: history while the field is empty,
/// results the moment a character is typed. Nothing here searches - tapping an
/// entry hands the term back and the existing search runs on it unchanged.
///
/// Widgets in a `widgets/` folder are driven entirely by constructor
/// parameters and callbacks - they never read a ViewModel themselves, and they
/// style from the theme rather than raw values.
class SearchHistoryPanel extends StatelessWidget {
  const SearchHistoryPanel({
    super.key,
    required this.terms,
    required this.onSelected,
    required this.onClear,
  });

  /// Most recent first. The panel is not built at all when this is empty.
  final List<String> terms;

  final ValueChanged<String> onSelected;

  /// A15-1 - forgets every entry.
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(
        maxHeight: AppSizes.searchSuggestionsMaxHeight,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(color: AppColors.outline),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _heading(),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              children: <Widget>[
                for (final String term in terms)
                  _HistoryTile(term: term, onTap: () => onSelected(term)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _heading() => Container(
    width: double.infinity,
    color: AppColors.surfaceVariant,
    padding: const EdgeInsets.only(left: AppSpacing.md),
    child: Row(
      children: <Widget>[
        Expanded(
          child: Text('RECENT SEARCHES', style: AppTextStyles.labelSmall),
        ),
        InkWell(
          onTap: onClear,
          child: const Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            child: _ClearLabel(),
          ),
        ),
      ],
    ),
  );
}

/// Pulled out so the tap target above can stay `const`.
class _ClearLabel extends StatelessWidget {
  const _ClearLabel();

  @override
  Widget build(BuildContext context) => Text(
    'CLEAR',
    style: AppTextStyles.labelSmall.copyWith(color: AppColors.primary),
  );
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.term, required this.onTap});

  final String term;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.history,
            size: 20,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              term,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.titleSmall,
            ),
          ),
          const Icon(
            Icons.north_west,
            size: 18,
            color: AppColors.textSecondary,
          ),
        ],
      ),
    ),
  );
}
