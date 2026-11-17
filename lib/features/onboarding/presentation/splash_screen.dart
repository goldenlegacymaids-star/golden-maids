import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
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
import '../../authentication/data/auth_providers.dart';
import '../../services/data/catalog_repository.dart';
import '../../services/domain/catalog.dart';
import '../data/onboarding_repository.dart';

/// Branded splash. Shows the logo briefly, then opens onboarding on first
/// launch; returning users go home if signed in, otherwise to Welcome.
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
    unawaited(_prefetchHome());
    unawaited(_continue(reduceMotion));
  }

  /// Starts loading Home's banners and Hire a Maid photos (and their
  /// pictures) while the splash is showing, so Home opens ready.
  Future<void> _prefetchHome() async {
    final catalog = ref.read(catalogRepositoryProvider);
    try {
      final results = await Future.wait<Object>([
        ref.read(promotionsProvider.future),
        ref.read(hireCardPhotosProvider.future),
      ]);
      if (!mounted) return;
      final promotions = results[0] as List<Promotion>;
      final cards = results[1] as Map<String, String>;
      final urls = [
        for (final p in promotions) catalog.imageUrl(p.imagePath),
        for (final path in cards.values) catalog.imageUrl(path),
      ].whereType<String>();
      for (final url in urls) {
        unawaited(
          precacheImage(
            CachedNetworkImageProvider(url),
            context,
            onError: (_, _) {},
          ),
        );
      }
    } on Object {
      // Home shows its own loading and error states.
    }
  }

  Future<void> _continue(bool reduceMotion) async {
    await Future<void>.delayed(
      reduceMotion
          ? SplashScreen.reducedMotionDisplayTime
          : SplashScreen.displayTime,
    );
    if (!mounted) return;

    final seen = ref.read(onboardingRepositoryProvider).hasSeenOnboarding;
    final signedIn = ref.read(authRepositoryProvider).currentUser != null;
    context.go(
      !seen
          ? AppRoutes.onboarding
          : signedIn
          ? AppRoutes.home
          : AppRoutes.afterOnboarding,
    );
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
