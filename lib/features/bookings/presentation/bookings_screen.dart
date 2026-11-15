import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/tab_screen.dart';
import '../../authentication/data/auth_providers.dart';
import '../../authentication/presentation/widgets/sign_in_prompt.dart';

/// Bookings tab. Real bookings are connected in Phase 3.
class BookingsScreen extends ConsumerWidget {
  const BookingsScreen({super.key});

  static const List<(String, String)> _tabs = [
    ('Upcoming', 'upcoming'),
    ('Active', 'active'),
    ('Completed', 'completed'),
    ('Cancelled', 'cancelled'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user =
        ref.watch(authStateProvider).value ??
        ref.watch(authRepositoryProvider).currentUser;

    if (user == null) {
      return const TabScreen(
        title: 'Bookings',
        child: SignInPrompt(
          icon: Icons.calendar_today_rounded,
          title: 'Sign in to see your bookings',
          message: 'Track upcoming, active and past home-service bookings '
              'in one place.',
        ),
      );
    }

    return TabScreen(
      title: 'Bookings',
      scrollable: false,
      child: DefaultTabController(
        length: _tabs.length,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screenPadding - AppSpacing.md,
              ),
              child: TabBar(
                isScrollable: true,
                tabs: [for (final (label, _) in _tabs) Tab(text: label)],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  for (final (_, status) in _tabs)
                    SingleChildScrollView(
                      child: EmptyState(
                        icon: Icons.event_available_rounded,
                        title: 'No $status bookings',
                        message: status == 'upcoming'
                            ? 'When you book a home service, it will appear '
                                  'here.'
                            : 'Your $status bookings will appear here.',
                        actionLabel: status == 'upcoming'
                            ? 'Browse services'
                            : null,
                        onAction: status == 'upcoming'
                            ? () => context.go(AppRoutes.home)
                            : null,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
