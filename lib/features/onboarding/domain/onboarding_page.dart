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
    title: 'Clean Space, Clear Mind, Peaceful Life Always.',
    description:
        'Professional cleaners, maids and caregivers for every part of your '
        'home.',
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
    title: 'Book Your Favourite Home Services in Minutes.',
    description:
        "Choose a service, pick a time that suits you and we'll take care of "
        'the rest.',
  ),
];
