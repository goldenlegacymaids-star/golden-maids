import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon_button.dart';
import '../../../core/widgets/page_indicator.dart';
import '../data/onboarding_repository.dart';
import '../domain/onboarding_page.dart';

/// Three introduction screens shown on first launch.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  static const double _controlsHeight = 56;

  final _pageController = PageController();
  int _page = 0;

  bool get _isLastPage => _page == onboardingPages.length - 1;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _next() {
    unawaited(
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  Future<void> _finish() async {
    await ref.read(onboardingRepositoryProvider).markSeen();
    if (!mounted) return;
    context.go(AppRoutes.afterOnboarding);
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final panelHeight = (height * 0.42).clamp(300.0, 380.0) + bottomInset;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: AppColors.lightBlue,
        body: Stack(
          children: [
            PageView.builder(
              controller: _pageController,
              itemCount: onboardingPages.length,
              onPageChanged: (index) => setState(() => _page = index),
              itemBuilder: (context, index) => _OnboardingPageView(
                page: onboardingPages[index],
                panelHeight: panelHeight,
                bottomReserved:
                    _controlsHeight + AppSpacing.xl * 2 + bottomInset,
              ),
            ),
            // Skip (hidden on the last page).
            Positioned(
              top: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: AnimatedOpacity(
                    opacity: _isLastPage ? 0 : 1,
                    duration: const Duration(milliseconds: 200),
                    child: IgnorePointer(
                      ignoring: _isLastPage,
                      child: DecoratedBox(
                        decoration: const BoxDecoration(
                          color: Color(0xE6FFFFFF),
                          borderRadius: AppRadius.pillAll,
                        ),
                        child: AppButton(
                          label: 'Skip',
                          variant: AppButtonVariant.text,
                          compact: true,
                          expand: false,
                          onPressed: _finish,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Page dots + Next / Get Started.
            Positioned(
              left: AppSpacing.xl,
              right: AppSpacing.xl,
              bottom: AppSpacing.xl + bottomInset,
              child: SizedBox(
                height: _controlsHeight,
                child: Row(
                  children: [
                    PageIndicator(
                      count: onboardingPages.length,
                      index: _page,
                    ),
                    const Spacer(),
                    if (_isLastPage)
                      AppButton(
                        label: 'Get Started',
                        icon: Icons.arrow_forward_rounded,
                        expand: false,
                        onPressed: _finish,
                      )
                    else
                      AppIconButton(
                        icon: Icons.arrow_forward_rounded,
                        tooltip: 'Next',
                        style: AppIconButtonStyle.primary,
                        size: _controlsHeight,
                        onPressed: _next,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingPageView extends StatelessWidget {
  const _OnboardingPageView({
    required this.page,
    required this.panelHeight,
    required this.bottomReserved,
  });

  final OnboardingPage page;
  final double panelHeight;

  /// Space at the bottom of the panel kept free for the fixed controls.
  final double bottomReserved;

  @override
  Widget build(BuildContext context) {
    const overlap = AppRadius.xl + 8;

    return Stack(
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          bottom: panelHeight - overlap,
          child: Image.asset(
            page.image,
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            excludeFromSemantics: true,
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: panelHeight,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(AppRadius.xl + 8),
              ),
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.xxl,
                AppSpacing.xl,
                bottomReserved,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    page.title,
                    style: AppTypography.headlineMedium,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Flexible(
                    child: Text(
                      page.description,
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      overflow: TextOverflow.fade,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
