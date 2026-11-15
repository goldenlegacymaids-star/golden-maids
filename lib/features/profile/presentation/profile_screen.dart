import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_icon_button.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/tab_screen.dart';
import '../../authentication/data/auth_providers.dart';
import '../../authentication/domain/auth_repository.dart';
import '../../authentication/presentation/widgets/sign_in_prompt.dart';
import '../data/profile_repository.dart';
import '../domain/profile.dart';
import 'widgets/profile_menu_tile.dart';

/// Profile tab: account details, shortcuts to the customer's records,
/// help and legal pages, and log out.
///
/// Items without an `onTap` are shown as "Coming soon" until their phase
/// is built.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _confirmLogOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You will need to sign in again to book services.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(authRepositoryProvider).signOut();
      if (context.mounted) context.go(AppRoutes.welcome);
    } on AppFailure catch (failure) {
      if (context.mounted) showErrorSnackBar(context, failure);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user =
        ref.watch(authStateProvider).value ??
        ref.watch(authRepositoryProvider).currentUser;
    final profile = ref.watch(myProfileProvider).value;

    return TabScreen(
      title: 'Profile',
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenPadding,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (user == null)
              const AppCard(
                child: SignInPrompt(
                  icon: Icons.person_rounded,
                  title: 'Sign in to your account',
                  message: 'Manage your bookings, hiring requests, visa '
                      'applications and documents.',
                ),
              )
            else ...[
              _ProfileHeader(user: user, profile: profile),
              const SizedBox(height: AppSpacing.xl),
              _MenuSection(
                title: 'My activity',
                tiles: [
                  ProfileMenuTile(
                    icon: Icons.calendar_today_rounded,
                    title: 'My Bookings',
                    onTap: () => context.go(AppRoutes.bookings),
                  ),
                  ProfileMenuTile(
                    icon: Icons.favorite_rounded,
                    title: 'Saved Maids',
                    onTap: () => unawaited(context.push(AppRoutes.savedMaids)),
                  ),
                  ProfileMenuTile(
                    icon: Icons.assignment_ind_rounded,
                    title: 'My Hiring Requests',
                    onTap: () =>
                        unawaited(context.push(AppRoutes.hiringRequests)),
                  ),
                  const ProfileMenuTile(
                    icon: Icons.flight_rounded,
                    title: 'My Visa Applications',
                  ),
                  const ProfileMenuTile(
                    icon: Icons.description_rounded,
                    title: 'My Contracts',
                  ),
                  const ProfileMenuTile(
                    icon: Icons.folder_rounded,
                    title: 'My Documents',
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              const _MenuSection(
                title: 'Account',
                tiles: [
                  ProfileMenuTile(
                    icon: Icons.location_on_rounded,
                    title: 'Saved Addresses',
                  ),
                  ProfileMenuTile(
                    icon: Icons.credit_card_rounded,
                    title: 'Payment Methods',
                  ),
                  ProfileMenuTile(
                    icon: Icons.notifications_rounded,
                    title: 'Notifications',
                  ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            _MenuSection(
              title: 'Support',
              tiles: [
                const ProfileMenuTile(
                  icon: Icons.help_rounded,
                  title: 'Help Centre',
                ),
                const ProfileMenuTile(
                  icon: Icons.privacy_tip_rounded,
                  title: 'Privacy Policy',
                ),
                const ProfileMenuTile(
                  icon: Icons.gavel_rounded,
                  title: 'Terms and Conditions',
                ),
                ProfileMenuTile(
                  icon: Icons.info_rounded,
                  title: 'Open-source licences',
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: AppConstants.appName,
                    applicationLegalese: AppConstants.companyName,
                  ),
                ),
              ],
            ),
            if (user != null) ...[
              const SizedBox(height: AppSpacing.xl),
              AppButton(
                label: 'Log Out',
                icon: Icons.logout_rounded,
                variant: AppButtonVariant.outline,
                onPressed: () => _confirmLogOut(context, ref),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            const Text(
              '${AppConstants.appName} · by ${AppConstants.companyName}',
              style: AppTypography.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.user, required this.profile});

  final AppUser user;
  final Profile? profile;

  String get _name => profile?.fullName ?? user.fullName ?? 'Your account';

  String? get _contact =>
      profile?.phone ?? profile?.email ?? user.phone ?? user.email;

  String get _initials {
    final parts = _name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty);
    return parts.take(2).map((part) => part[0].toUpperCase()).join();
  }

  @override
  Widget build(BuildContext context) {
    final contact = _contact;

    return AppCard(
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: AppColors.lightBlue,
            child: Text(
              _initials,
              style: AppTypography.titleLarge.copyWith(
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _name,
                  style: AppTypography.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (contact != null)
                  Text(
                    // Supabase stores phone numbers without the "+".
                    contact.contains('@') || contact.startsWith('+')
                        ? contact
                        : '+$contact',
                    style: AppTypography.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          AppIconButton(
            icon: Icons.edit_rounded,
            tooltip: 'Edit profile',
            size: 40,
            onPressed: () => unawaited(context.push(AppRoutes.editProfile)),
          ),
        ],
      ),
    );
  }
}

class _MenuSection extends StatelessWidget {
  const _MenuSection({required this.title, required this.tiles});

  final String title;
  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.xxs,
            bottom: AppSpacing.xs,
          ),
          child: Text(title, style: AppTypography.titleSmall),
        ),
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
          child: Column(
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                if (i > 0) const Divider(indent: 72),
                tiles[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}
