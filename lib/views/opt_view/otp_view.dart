import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/routing/app_routes.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../view_models/otp_view_model.dart';
import '../common_widgets/scrollable_centered_body.dart';
import 'widgets/otp_code_field.dart';

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
  bool _initialised = false;

  @override
  void initState() {
    super.initState();
    _viewModel = OtpViewModel();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialised) return;
    _initialised = true;
    // Option B: the login screen only navigates here, passing the email as
    // the route argument. This screen owns sending, so it must know the
    // address even before a code exists (fall back to the pending email for
    // deep-link/restart edge cases where no argument was supplied).
    final Object? argument = ModalRoute.of(context)?.settings.arguments;
    _viewModel.emailArgument = argument is String ? argument : '';
    _viewModel.onInit();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  Future<void> _verify(OtpViewModel viewModel) async {
    await viewModel.verifyEmailOtp();
    if (!mounted || !viewModel.verified) return;
    // C3: a brand-new tourist is routed to profile set-up before the
    // dashboard; everyone else goes straight to the shell.
    Navigator.pushNamedAndRemoveUntil(
      context,
      viewModel.needsProfileSetup
          ? AppRoutes.profileSetUp
          : AppRoutes.mainShell,
      (Route<dynamic> _) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<OtpViewModel>.value(
      value: _viewModel,
      child: Scaffold(
        body: SafeArea(
          child: Consumer<OtpViewModel>(
            builder: (BuildContext context, OtpViewModel viewModel, Widget? _) {
              return ScrollableCenteredBody(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    CircleAvatar(
                      radius: AppSizes.authBadgeRadius,
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.secondaryContainer,
                      child: Icon(
                        Icons.email_outlined,
                        color: Theme.of(context).colorScheme.primary,
                        size: AppSizes.authBadgeIconSize,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Text(
                      'Verify Your Email',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Text.rich(
                      TextSpan(
                        children: <TextSpan>[
                          TextSpan(
                            text:
                                'Enter the 6-digit verification code sent to ',
                          ),
                          // The mock-up bolds the recipient address.
                          TextSpan(
                            text: viewModel.email,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const TextSpan(text: '.'),
                        ],
                      ),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    OtpCodeField(
                      codeLength: OtpViewModel.otpLength,
                      // Locked while the code is being checked: the digits on
                      // screen are the ones the in-flight request carries, so
                      // backspace must not be able to delete one of them (the
                      // request cannot be cancelled).
                      enabled: !viewModel.isVerifying,
                      onChanged: (String code) {
                        viewModel.setToken(code);
                        if (viewModel.canVerify) {
                          _verify(viewModel);
                        }
                      },
                    ),
                    if (viewModel.isVerifying) ...<Widget>[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Verifying your code…',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                    if (viewModel.isSendingCode) ...<Widget>[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Sending your code…',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                    if (viewModel.reusingExistingCode) ...<Widget>[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'A code was already sent to this email — check your '
                        'inbox, you can still use it below.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                    if (viewModel.hasError) ...<Widget>[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        viewModel.errorMessage ?? 'Unable to verify the code.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    Align(
                      alignment: Alignment.centerRight,
                      child: viewModel.canResend
                          ? TextButton(
                              onPressed: viewModel.resendEmailOtp,
                              child: const Text('Resend OTP'),
                            )
                          : Text(
                              'Resend OTP in ${viewModel.resendCooldown}s',
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                            ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Did not receive the email?',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ),
                    Text(
                      '1. Please confirm your email address is correct.\n'
                      '2. Please check if the email was mistakenly marked as spam.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Theme.of(
                            context,
                          ).colorScheme.primary,
                          backgroundColor: AppColors.surface,
                          side: BorderSide(
                            color: Theme.of(
                              context,
                            ).colorScheme.primaryContainer,
                            width: AppSizes.borderWidthStrong,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              AppRadius.authPillRadius,
                            ),
                          ),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
