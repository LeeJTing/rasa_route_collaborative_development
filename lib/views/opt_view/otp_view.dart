import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_dimensions.dart';
import '../../view_models/otp_view_model.dart';
import '../common_widgets/app_top_bar.dart';

/// Verify your email screen.
///
/// Placeholder body. What is wired up is the View - ViewModel connection:
///
///   * the ViewModel is built in `initState` with `XViewModel()` - a View knows
///     its ViewModel and nothing else, and nothing is passed in;
///   * it is published to this screen's subtree with a
///     `ChangeNotifierProvider` declared by this View and nobody else;
///   * it is disposed with the screen.
///
/// Build the layout from the Figma frame for this screen, using
/// `Theme.of(context)` and the tokens in `lib/app/theme/`. Reusable pieces go
/// in `opt_view/widgets/`.
class OtpView extends StatefulWidget {
  const OtpView({super.key});

  @override
  State<OtpView> createState() => _OtpViewState();
}

class _OtpViewState extends State<OtpView> {
  late final OtpViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = OtpViewModel();
    _viewModel.onInit();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<OtpViewModel>.value(
      value: _viewModel,
      child: Scaffold(
        appBar: const AppTopBar(title: 'Verify your email'),
        body: SafeArea(
          child: Consumer<OtpViewModel>(
            builder: (BuildContext context, OtpViewModel viewModel, Widget? _) {
              return const Padding(
                padding: AppSpacing.screenPadding,
                child: Center(child: Text('OtpView')),
              );
            },
          ),
        ),
      ),
    );
  }
}
