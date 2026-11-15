import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_logo.dart';
import '../data/onboarding_repository.dart';

/// Branded splash. Shows the logo briefly, then opens onboarding on first
/// launch, or skips it for returning users.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  /// How long the splash stays visible (shorter with reduced motion).
  static const Duration displayTime = Duration(milliseconds: 1600);
  static const Duration reducedMotionDisplayTime = Duration(milliseconds: 600);

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
  );
  late final Animation<double> _scale = Tween<double>(begin: 0.92, end: 1)
      .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;

    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion) {
      _controller.value = 1;
    } else {
      unawaited(_controller.forward());
    }
    unawaited(_continue(reduceMotion));
  }

  Future<void> _continue(bool reduceMotion) async {
    await Future<void>.delayed(
      reduceMotion
          ? SplashScreen.reducedMotionDisplayTime
          : SplashScreen.displayTime,
    );
    if (!mounted) return;

    final seen = ref.read(onboardingRepositoryProvider).hasSeenOnboarding;
    context.go(seen ? AppRoutes.afterOnboarding : AppRoutes.onboarding);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: DecoratedBox(
          decoration: const BoxDecoration(gradient: AppColors.backgroundWash),
          child: SafeArea(
            child: SizedBox.expand(
              child: Column(
                children: [
                  const Spacer(),
                  FadeTransition(
                    opacity: _fade,
                    child: ScaleTransition(
                      scale: _scale,
                      child: Column(
                        children: [
                          const AppLogo.icon(size: 104),
                          const SizedBox(height: AppSpacing.xl),
                          const Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(text: 'Golden '),
                                TextSpan(
                                  text: 'Maids',
                                  style: TextStyle(color: AppColors.primary),
                                ),
                              ],
                            ),
                            style: AppTypography.headlineLarge,
                            semanticsLabel: AppConstants.appName,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            AppConstants.tagline,
                            style: AppTypography.bodyLarge.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  FadeTransition(
                    opacity: _fade,
                    child: const Padding(
                      padding: EdgeInsets.fromLTRB(
                        AppSpacing.xl,
                        0,
                        AppSpacing.xl,
                        AppSpacing.xl,
                      ),
                      child: Text(
                        'by ${AppConstants.companyName}',
                        style: AppTypography.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
