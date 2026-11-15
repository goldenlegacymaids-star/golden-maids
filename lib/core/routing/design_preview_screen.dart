import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../errors/app_failure.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/app_button.dart';
import '../widgets/app_card.dart';
import '../widgets/app_chip.dart';
import '../widgets/app_icon_button.dart';
import '../widgets/app_logo.dart';
import '../widgets/app_network_image.dart';
import '../widgets/app_search_bar.dart';
import '../widgets/app_text_field.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_state.dart';
import '../widgets/section_header.dart';
import '../widgets/skeleton.dart';

/// TEMPORARY screen showing every design-system component for review.
///
/// Deleted in Step 1.4, when the splash screen becomes the first route.
class DesignPreviewScreen extends StatefulWidget {
  const DesignPreviewScreen({super.key});

  @override
  State<DesignPreviewScreen> createState() => _DesignPreviewScreenState();
}

class _DesignPreviewScreenState extends State<DesignPreviewScreen> {
  static const _categories = [
    'All',
    'Cleaning',
    'Laundry',
    'Nanny',
    'Elderly Care',
  ];

  final _formKey = GlobalKey<FormState>();
  String _selectedCategory = _categories.first;

  void _showMessage(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Email is required';
    if (!email.contains('@') || !email.contains('.')) {
      return 'Enter a valid email address';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if ((value ?? '').length < 8) return 'Use at least 8 characters';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppColors.backgroundWash),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenPadding,
              AppSpacing.md,
              AppSpacing.screenPadding,
              AppSpacing.xxxl,
            ),
            children: [
              _header(),
              _section('Logo', _logos()),
              _section('Colours', _colours()),
              _section('Typography', _typography()),
              _section('Buttons', _buttons()),
              _section('Icon buttons', _iconButtons()),
              _section('Search & categories', _searchAndChips()),
              _section('Form fields', _form()),
              _section('Cards & images', _cards()),
              _section('Empty & error states', _states()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        const AppLogo.icon(size: 48),
        const SizedBox(width: AppSpacing.sm),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Design System', style: AppTypography.labelSmall),
              Text(AppConstants.appName, style: AppTypography.titleLarge),
            ],
          ),
        ),
        AppIconButton(
          icon: Icons.notifications_none_rounded,
          tooltip: 'Notifications',
          showBadge: true,
          onPressed: () => _showMessage('Notifications tapped'),
        ),
      ],
    );
  }

  Widget _section(String title, Widget child) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(title: title),
          const SizedBox(height: AppSpacing.sm),
          child,
        ],
      ),
    );
  }

  Widget _logos() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AppCard(child: Center(child: AppLogo.full())),
        const SizedBox(height: AppSpacing.sm),
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: const BoxDecoration(
            color: AppColors.primary,
            borderRadius: AppRadius.lgAll,
          ),
          child: const Center(child: AppLogo.full(onDark: true)),
        ),
      ],
    );
  }

  Widget _colours() {
    const swatches = [
      ('Primary', AppColors.primary, '#398FF2'),
      ('Secondary', AppColors.secondary, '#2F83E8'),
      ('Light Blue', AppColors.lightBlue, '#EAF3FF'),
      ('Very Light', AppColors.veryLightBlue, '#F4F8FF'),
      ('Text', AppColors.textPrimary, '#202631'),
      ('Text 2', AppColors.textSecondary, '#7B8491'),
      ('Border', AppColors.border, '#E5EAF1'),
      ('Success', AppColors.success, '#25B875'),
      ('Warning', AppColors.warning, '#F3B642'),
      ('Error', AppColors.error, '#E65353'),
    ];

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final (name, color, hex) in swatches)
          SizedBox(
            width: 96,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 56,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: AppRadius.smAll,
                    border: Border.all(color: AppColors.border),
                  ),
                ),
                const SizedBox(height: 4),
                Text(name, style: AppTypography.labelMedium),
                Text(hex, style: AppTypography.labelSmall),
              ],
            ),
          ),
      ],
    );
  }

  Widget _typography() {
    return const AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What Services do you want to Use?',
            style: AppTypography.headlineMedium,
          ),
          SizedBox(height: AppSpacing.xs),
          Text('Featured Maids', style: AppTypography.headlineSmall),
          Text('Hattie Carson', style: AppTypography.titleMedium),
          SizedBox(height: AppSpacing.xs),
          Text(
            'Body text in Inter. Professional, verified domestic workers for '
            'your home in the UAE.',
            style: AppTypography.bodyMedium,
          ),
          Text(
            'Secondary text · 5 years experience',
            style: AppTypography.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buttons() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppButton(
          label: 'Book Now (tap to test loading)',
          onPressed: () async {
            await Future<void>.delayed(const Duration(seconds: 2));
            if (!mounted) return;
            _showMessage('Done – repeat taps were ignored');
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        AppButton(
          label: 'Request More Information',
          variant: AppButtonVariant.outline,
          onPressed: () => _showMessage('Outline tapped'),
        ),
        const SizedBox(height: AppSpacing.sm),
        AppButton(
          label: 'Hire Now',
          icon: Icons.person_add_alt_1_rounded,
          onPressed: () => _showMessage('Icon button tapped'),
        ),
        const SizedBox(height: AppSpacing.sm),
        const AppButton(label: 'Disabled', onPressed: null),
        const SizedBox(height: AppSpacing.sm),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AppButton(
              label: 'Skip',
              variant: AppButtonVariant.text,
              expand: false,
              onPressed: () => _showMessage('Skip tapped'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        _promoBanner(),
      ],
    );
  }

  Widget _promoBanner() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: const BoxDecoration(
        color: AppColors.primary,
        borderRadius: AppRadius.xlAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '30% OFF',
            style: AppTypography.headlineLarge.copyWith(
              color: AppColors.white,
            ),
          ),
          Text(
            'Best Cleaning Service',
            style: AppTypography.bodyLarge.copyWith(color: AppColors.white),
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            label: 'Book Now',
            variant: AppButtonVariant.dark,
            compact: true,
            expand: false,
            onPressed: () => _showMessage('Banner button tapped'),
          ),
        ],
      ),
    );
  }

  Widget _iconButtons() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: const BoxDecoration(
        color: AppColors.lightBlue,
        borderRadius: AppRadius.lgAll,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          AppIconButton(
            icon: Icons.arrow_back_rounded,
            tooltip: 'Back',
            onPressed: () => _showMessage('Back tapped'),
          ),
          AppIconButton(
            icon: Icons.tune_rounded,
            tooltip: 'Filters',
            style: AppIconButtonStyle.primary,
            onPressed: () => _showMessage('Filters tapped'),
          ),
          AppIconButton(
            icon: Icons.arrow_back_rounded,
            tooltip: 'Back (on photo)',
            style: AppIconButtonStyle.translucent,
            onPressed: () => _showMessage('Translucent tapped'),
          ),
          AppIconButton(
            icon: Icons.arrow_forward_rounded,
            tooltip: 'Next',
            style: AppIconButtonStyle.primary,
            size: 56,
            onPressed: () => _showMessage('Next tapped'),
          ),
        ],
      ),
    );
  }

  Widget _searchAndChips() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSearchBar(onFilterPressed: () => _showMessage('Filters tapped')),
        const SizedBox(height: AppSpacing.md),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          child: Row(
            children: [
              for (final category in _categories)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.xs),
                  child: AppChip(
                    label: category,
                    selected: category == _selectedCategory,
                    onTap: () => setState(() => _selectedCategory = category),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _form() {
    return AppCard(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextField(
              label: 'Email address',
              hint: 'name@example.com',
              prefixIcon: Icons.mail_outline_rounded,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              validator: _validateEmail,
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              label: 'Password',
              prefixIcon: Icons.lock_outline_rounded,
              obscureText: true,
              validator: _validatePassword,
            ),
            const SizedBox(height: AppSpacing.lg),
            AppButton(
              label: 'Validate form',
              onPressed: () {
                final valid = _formKey.currentState?.validate() ?? false;
                _showMessage(valid ? 'Form is valid' : 'Please fix the errors');
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _cards() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          onTap: () => _showMessage('Card tapped'),
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Row(
            children: [
              const AppNetworkImage(
                url: null,
                width: 96,
                height: 96,
                borderRadius: AppRadius.mdAll,
                semanticLabel: 'Candidate photo',
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('GM-00123', style: AppTypography.titleMedium),
                    const Text('Housekeeper', style: AppTypography.bodySmall),
                    const SizedBox(height: AppSpacing.xs),
                    Row(
                      children: [
                        const Icon(
                          Icons.star_rounded,
                          size: 18,
                          color: AppColors.gold,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Rating shown only when real',
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        const AppCard(
          padding: EdgeInsets.all(AppSpacing.sm),
          child: Skeleton(
            child: Row(
              children: [
                SkeletonBox(width: 96, height: 96, borderRadius: AppRadius.mdAll),
                SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(width: 140, height: 16),
                      SizedBox(height: AppSpacing.xs),
                      SkeletonBox(width: 90, height: 12),
                      SizedBox(height: AppSpacing.sm),
                      SkeletonBox(width: 120, height: 12),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _states() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          child: EmptyState(
            icon: Icons.calendar_today_rounded,
            title: 'No bookings yet',
            message: 'Your upcoming bookings will appear here.',
            actionLabel: 'Book a service',
            onAction: () => _showMessage('Empty-state action tapped'),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        AppCard(
          child: ErrorState(
            failure: const NetworkFailure(),
            onRetry: () async {
              await Future<void>.delayed(const Duration(seconds: 1));
              if (!mounted) return;
              _showMessage('Retried');
            },
          ),
        ),
      ],
    );
  }
}
