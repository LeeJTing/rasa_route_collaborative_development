import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/routing/app_routes.dart';
import '../../view_models/login_register_view_model.dart';
import '../common_widgets/scrollable_centered_body.dart';
import 'widgets/auth_text_field.dart';

/// Sign in screen.
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
/// in `login_register_view/widgets/`.
class LoginRegisterView extends StatefulWidget {
  const LoginRegisterView({super.key});

  @override
  State<LoginRegisterView> createState() => _LoginRegisterViewState();
}

class _LoginRegisterViewState extends State<LoginRegisterView>
    with WidgetsBindingObserver {
  late final LoginRegisterViewModel _viewModel;
  bool _navigatedToShell = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _viewModel = LoginRegisterViewModel();
    // The login screen doubles as the entry gate - react to the session check.
    _viewModel.addListener(_onSessionChecked);
    _viewModel.onInit();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _viewModel.removeListener(_onSessionChecked);
    _viewModel.dispose();
    super.dispose();
  }

  /// Once the entry session check has finished and a session exists, skip the
  /// form and open the shell (clearing the stack). A brand-new tourist whose
  /// profile is still empty is routed to the C3 set-up screen first. Guarded
  /// so this only fires once per screen life.
  void _onSessionChecked() {
    if (_navigatedToShell ||
        _viewModel.checkingSession ||
        !_viewModel.signedIn) {
      return;
    }
    _navigatedToShell = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(
        context,
        _viewModel.needsProfileSetup
            ? AppRoutes.profileSetUp
            : AppRoutes.mainShell,
        (Route<dynamic> _) => false,
      );
    });
  }

  /// Google OAuth hands off to the system browser; the app is backgrounded
  /// until the OAuth deep link (`com.rasaroute.app://login-callback`) brings
  /// it back. On resume, finish the flow - Supabase already completed the
  /// exchange, so this resolves the session and provisions the tourist row.
  ///
  /// With no flow in flight, a plain session read is enough: that is what picks
  /// up a deep link which landed late, without ever re-opening the browser.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (_viewModel.googleFlowStarted && !_viewModel.googleSignInComplete) {
      _completeGoogleSignIn();
      return;
    }
    _viewModel.refreshSession();
  }

  /// Option B: the login "Send OTP" button no longer sends a code itself -
  /// it only opens the OTP screen, passing the email along. That screen owns
  /// the decision of whether a fresh code must actually be requested (it
  /// reuses a still-valid pending code and resumes the countdown otherwise).
  void _sendOtp(LoginRegisterViewModel viewModel) {
    Navigator.pushNamed(context, AppRoutes.otp, arguments: viewModel.email);
  }

  Future<void> _signInWithGoogle(LoginRegisterViewModel viewModel) async {
    await viewModel.signInWithGoogle();
    if (!mounted || !viewModel.googleFlowStarted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Continue sign-in in your browser.')),
    );
  }

  /// Finishes a Google sign-in after the browser returns. On success, clears
  /// the stack and lands on the shell (same as the OTP path) - or on the C3
  /// profile set-up screen when the tourist's profile is still empty.
  Future<void> _completeGoogleSignIn() async {
    await _viewModel.completeGoogleSignIn();
    if (!mounted) return;
    if (_viewModel.googleSignInComplete) {
      Navigator.pushNamedAndRemoveUntil(
        context,
        _viewModel.needsProfileSetup
            ? AppRoutes.profileSetUp
            : AppRoutes.mainShell,
        (Route<dynamic> _) => false,
      );
    } else if (_viewModel.hasError) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _viewModel.errorMessage ??
                'Google sign-in did not complete. Please try again.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<LoginRegisterViewModel>.value(
      value: _viewModel,
      child: Scaffold(
        body: SafeArea(
          child: Consumer<LoginRegisterViewModel>(
            builder:
                (
                  BuildContext context,
                  LoginRegisterViewModel viewModel,
                  Widget? _,
                ) {
                  // Entry session check in flight - show a splash rather than
                  // flashing the form to a tourist who is already signed in.
                  if (viewModel.checkingSession) {
                    return const _SessionCheckSplash();
                  }
                  // Keyboard-safe body: centred when there is room, scrollable
                  // when the keyboard + an inline error leave too little.
                  return ScrollableCenteredBody(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Image.asset(
                          'assets/images/logo/logo.webp',
                          width: AppSizes.authAvatarRadius * 2,
                          height: AppSizes.authAvatarRadius * 2,
                        ),
                        const SizedBox(height: AppSpacing.xxl),
                        Text(
                          "Log in or sign up to discover Malaysia's local foods.",
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: AppSpacing.xxl),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Row(
                            children: <Widget>[
                              Icon(
                                Icons.mail_outline,
                                size: AppSizes.iconSmall,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                              const SizedBox(width: AppSpacing.xs),
                              Text(
                                'Email Address',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        AuthTextField(
                          onChanged: viewModel.setEmail,
                          errorText: viewModel.emailError,
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: viewModel.canSendOtp
                                ? () => _sendOtp(viewModel)
                                : null,
                            style: ElevatedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  AppRadius.authPillRadius,
                                ),
                              ),
                            ),
                            child: const Text('Send One-Time Password'),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        const Row(
                          children: <Widget>[
                            Expanded(child: Divider()),
                            Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: AppSpacing.md,
                              ),
                              child: Text('OR'),
                            ),
                            Expanded(child: Divider()),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: viewModel.isBusy
                                ? null
                                : () => _signInWithGoogle(viewModel),
                            icon: Icon(
                              Icons.g_mobiledata,
                              color: AppColors.accentRust,
                            ),
                            label: const Text('Continue With Google'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.accentRust,
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
                          ),
                        ),
                        // Breathing room below the last control so it is never
                        // flush against the bottom edge while scrolled.
                        const SizedBox(height: AppSpacing.xxl),
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

/// The brief splash shown while the entry session check runs (the same brand
/// mark as the sign-in screen, so there's no jarring jump).
class _SessionCheckSplash extends StatelessWidget {
  const _SessionCheckSplash();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Image.asset(
            'assets/images/logo/logo.webp',
            width: AppSizes.authAvatarRadius * 2,
            height: AppSizes.authAvatarRadius * 2,
          ),
          const SizedBox(height: AppSpacing.xl),
          const CircularProgressIndicator(),
        ],
      ),
    );
  }
}
