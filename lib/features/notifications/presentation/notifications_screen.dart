import 'package:flutter/material.dart';

import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/page_scaffold.dart';

/// Notifications list. Real notifications (bookings, hiring, visa updates)
/// are delivered from Phase 4.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PageScaffold(
      title: 'Notifications',
      body: SingleChildScrollView(
        child: EmptyState(
          icon: Icons.notifications_none_rounded,
          title: 'No notifications yet',
          message: "We'll let you know about your bookings, hiring requests "
              'and visa updates here.',
        ),
      ),
    );
  }
}
