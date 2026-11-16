import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../bookings/data/booking_repository.dart';
import '../../bookings/domain/booking.dart';
import 'address_sheet.dart';

/// Profile → Saved Addresses: add, edit, delete and choose the default.
class SavedAddressesScreen extends ConsumerWidget {
  const SavedAddressesScreen({super.key});

  Future<void> _add(BuildContext context) async {
    final saved = await showAddressSheet(context);
    if (saved == true && context.mounted) {
      showAppSnackBar(context, 'Address saved.');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final addresses = ref.watch(savedAddressesProvider);
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return PageScaffold(
      title: 'Saved Addresses',
      body: addresses.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => SingleChildScrollView(
          child: ErrorState(
            failure: AppFailure.from(error),
            onRetry: () => ref.invalidate(savedAddressesProvider),
          ),
        ),
        data: (list) {
          if (list.isEmpty) {
            return SingleChildScrollView(
              child: EmptyState(
                icon: Icons.location_on_outlined,
                title: 'No saved addresses',
                message:
                    'Save your home or work address to book home services '
                    'faster.',
                actionLabel: 'Add an address',
                onAction: () => _add(context),
              ),
            );
          }
          return ListView(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.screenPadding,
              AppSpacing.xs,
              AppSpacing.screenPadding,
              bottomInset + AppSpacing.xl,
            ),
            children: [
              for (final address in list) ...[
                _AddressCard(address: address),
                const SizedBox(height: AppSpacing.sm),
              ],
              const SizedBox(height: AppSpacing.sm),
              AppButton(
                label: 'Add an address',
                icon: Icons.add_location_alt_rounded,
                variant: AppButtonVariant.outline,
                onPressed: () => _add(context),
              ),
            ],
          );
        },
      ),
    );
  }
}

enum _AddressAction { edit, makeDefault, delete }

class _AddressCard extends ConsumerWidget {
  const _AddressCard({required this.address});

  final SavedAddress address;

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    _AddressAction action,
  ) async {
    final repository = ref.read(bookingRepositoryProvider);
    switch (action) {
      case _AddressAction.edit:
        final saved = await showAddressSheet(context, address: address);
        if (saved == true && context.mounted) {
          showAppSnackBar(context, 'Address updated.');
        }
        return;
      case _AddressAction.makeDefault:
        try {
          await repository.setDefaultAddress(address.id);
          if (!context.mounted) return;
          ref.invalidate(savedAddressesProvider);
          showAppSnackBar(context, '${address.label} is now your default.');
        } on Object catch (error) {
          if (context.mounted) showErrorSnackBar(context, error);
        }
        return;
      case _AddressAction.delete:
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete this address?'),
            content: Text(
              '${address.summary}\n\nYour bookings keep their own copy of '
              'the address.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Keep'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: TextButton.styleFrom(foregroundColor: AppColors.error),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
        try {
          await repository.deleteAddress(address.id);
          if (!context.mounted) return;
          ref.invalidate(savedAddressesProvider);
          showAppSnackBar(context, 'Address deleted.');
        } on Object catch (error) {
          if (context.mounted) showErrorSnackBar(context, error);
        }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            switch (address.label) {
              'Home' => Icons.home_rounded,
              'Work' => Icons.work_rounded,
              _ => Icons.location_on_rounded,
            },
            color: AppColors.primary,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        address.label,
                        style: AppTypography.titleSmall,
                      ),
                    ),
                    if (address.isDefault) ...[
                      const SizedBox(width: AppSpacing.xs),
                      const _DefaultBadge(),
                    ],
                  ],
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(address.summary, style: AppTypography.bodyMedium),
                if (address.instructions.isNotEmpty)
                  Text(address.instructions, style: AppTypography.bodySmall),
              ],
            ),
          ),
          PopupMenuButton<_AddressAction>(
            tooltip: 'Address options',
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (action) => _run(context, ref, action),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: _AddressAction.edit,
                child: Text('Edit'),
              ),
              if (!address.isDefault)
                const PopupMenuItem(
                  value: _AddressAction.makeDefault,
                  child: Text('Make default'),
                ),
              const PopupMenuItem(
                value: _AddressAction.delete,
                child: Text('Delete'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DefaultBadge extends StatelessWidget {
  const _DefaultBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 2),
      decoration: const BoxDecoration(
        color: AppColors.veryLightBlue,
        borderRadius: AppRadius.pillAll,
      ),
      child: Text(
        'Default',
        style: AppTypography.labelSmall.copyWith(color: AppColors.primary),
      ),
    );
  }
}
