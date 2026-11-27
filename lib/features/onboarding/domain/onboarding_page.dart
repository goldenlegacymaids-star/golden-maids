import '../../../core/constants/app_assets.dart';

/// Content of one onboarding screen.
class OnboardingPage {
  const OnboardingPage({
    required this.image,
    required this.title,
    required this.description,
  });

  final String image;
  final String title;
  final String description;
}

const List<OnboardingPage> onboardingPages = [
  OnboardingPage(
    image: AppAssets.onboarding1,
    title: 'Hire a Trusted Maid in the UAE.',
    description:
        'Full-time, live-in housemaids, nannies, cooks, drivers and '
        'caregivers for your family.',
  ),
  OnboardingPage(
    image: AppAssets.onboarding2,
    title: 'Find the Right Helping Hands for Your Home.',
    description:
        'Browse maids, nannies and caregivers, compare their experience and '
        'hire with confidence.',
  ),
  OnboardingPage(
    image: AppAssets.onboarding3,
    title: 'On Your Visa or Ours.',
    description:
        'Sponsor your maid on a two-year contract, or hire her on our visa '
        'for a monthly fee. Follow every step in the app.',
  ),
];
