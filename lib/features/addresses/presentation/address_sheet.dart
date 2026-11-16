import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/uae.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_chip.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../bookings/data/booking_repository.dart';
import '../../bookings/domain/booking.dart';
import '../../bookings/presentation/book_service_screen.dart';
import '../../home/data/service_location.dart';

/// The labels a customer can give an address.
const List<String> addressLabels = ['Home', 'Work', 'Other'];

/// Add ([address] null) or edit a saved address. Returns true when saved.
Future<bool?> showAddressSheet(BuildContext context, {SavedAddress? address}) {
  return showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (context) => AddressSheet(address: address),
  );
}

class AddressSheet extends ConsumerStatefulWidget {
  const AddressSheet({super.key, this.address});

  /// The address being edited; null to add one.
  final SavedAddress? address;

  @override
  ConsumerState<AddressSheet> createState() => _AddressSheetState();
}

class _AddressSheetState extends ConsumerState<AddressSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _area;
  late final TextEditingController _building;
  late final TextEditingController _apartment;
  late final TextEditingController _directions;
  late String _label;
  late String _emirate;
  late bool _isDefault;
  bool _saving = false;

  /// Shown above the Save button (a snackbar would be hidden by the sheet).
  String? _error;

  bool get _isEditing => widget.address != null;

  @override
  void initState() {
    super.initState();
    final address = widget.address;
    _area = TextEditingController(text: address?.area);
    _building = TextEditingController(text: address?.building);
    _apartment = TextEditingController(text: address?.apartment);
    _directions = TextEditingController(text: address?.instructions);
    _label = address != null && addressLabels.contains(address.label)
        ? address.label
        : address == null
        ? addressLabels.first
        : 'Other';
    _emirate = address?.emirate ?? ref.read(serviceLocationProvider);
    _isDefault =
        address?.isDefault ??
        (ref.read(savedAddressesProvider).value?.isEmpty ?? true);
  }

  @override
  void dispose() {
    _area.dispose();
    _building.dispose();
    _apartment.dispose();
    _directions.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !(_formKey.currentState?.validate() ?? false)) return;
    final input = AddressInput(
      emirate: _emirate,
      area: _area.text.trim(),
      building: _building.text.trim(),
      apartment: _apartment.text.trim(),
      notes: _directions.text.trim(),
      label: _label,
      isDefault: _isDefault,
    );
    setState(() {
      _saving = true;
      _error = null;
    });
    final repository = ref.read(bookingRepositoryProvider);
    try {
      final address = widget.address;
      if (address == null) {
        await repository.saveAddress(input);
      } else {
        await repository.updateAddress(address.id, input);
      }
      if (!mounted) return;
      ref.invalidate(savedAddressesProvider);
      Navigator.of(context).pop(true);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = AppFailure.from(error).message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final error = _error;

    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.9,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              0,
              AppSpacing.xl,
              AppSpacing.lg,
            ),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _isEditing ? 'Edit address' : 'Add an address',
                    style: AppTypography.titleLarge,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const Text('Label', style: AppTypography.titleSmall),
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: [
                      for (final label in addressLabels)
                        AppChip(
                          label: label,
                          selected: _label == label,
                          onTap: () => setState(() => _label = label),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const Text('Emirate', style: AppTypography.titleSmall),
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: [
                      for (final emirate in UaeEmirates.all)
                        AppChip(
                          label: emirate,
                          selected: _emirate == emirate,
                          onTap: () => setState(() => _emirate = emirate),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppTextField(
                    controller: _area,
                    label: 'Area',
                    hint: 'e.g. Jumeirah Lake Towers',
                    prefixIcon: Icons.map_rounded,
                    textCapitalization: TextCapitalization.words,
                    validator: BookingValidators.area,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppTextField(
                    controller: _building,
                    label: 'Building or villa',
                    hint: 'e.g. Cluster X, Tower 1',
                    prefixIcon: Icons.apartment_rounded,
                    textCapitalization: TextCapitalization.words,
                    validator: BookingValidators.building,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppTextField(
                    controller: _apartment,
                    label: 'Apartment or villa number (optional)',
                    prefixIcon: Icons.door_front_door_rounded,
                    validator: BookingValidators.apartment,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppTextField(
                    controller: _directions,
                    label: 'Directions (optional)',
                    hint: 'e.g. parking, gate code, landmark',
                    maxLines: 2,
                    keyboardType: TextInputType.multiline,
                    textCapitalization: TextCapitalization.sentences,
                    validator: BookingValidators.directions,
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text(
                      'Use as my default address',
                      style: AppTypography.bodyMedium,
                    ),
                    value: _isDefault,
                    onChanged: (value) =>
                        setState(() => _isDefault = value ?? false),
                  ),
                  if (error != null) ...[
                    Text(
                      error,
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.error,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  const SizedBox(height: AppSpacing.xs),
                  AppButton(
                    label: _isEditing ? 'Save changes' : 'Save address',
                    isLoading: _saving,
                    onPressed: _saving ? null : _save,
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
