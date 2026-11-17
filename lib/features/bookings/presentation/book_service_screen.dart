import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/uae.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/haptics/haptics.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_chip.dart';
import '../../../core/widgets/app_icon_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../candidates/presentation/enquiry_sheet.dart';
import '../../hiring/presentation/widgets/hiring_widgets.dart';
import '../../home/data/service_location.dart';
import '../../profile/data/profile_repository.dart';
import '../../services/data/catalog_repository.dart';
import '../../services/domain/catalog.dart';
import '../data/booking_repository.dart';
import '../domain/booking.dart';
import 'widgets/booking_widgets.dart';

/// Booking a home service: when, where, review, confirm.
class BookServiceScreen extends ConsumerWidget {
  const BookServiceScreen({super.key, required this.slug});

  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(serviceProvider(slug));
    final settings = ref.watch(bookingSettingsProvider);

    return PageScaffold(
      title: service.value?.name ?? 'Book a service',
      body: switch ((service, settings)) {
        (AsyncData(value: final s), AsyncData(value: final rules)) =>
          _BookFlow(service: s, settings: rules),
        (AsyncError(:final error), _) || (_, AsyncError(:final error)) =>
          SingleChildScrollView(
            child: ErrorState(
              failure: AppFailure.from(error),
              onRetry: () {
                ref
                  ..invalidate(serviceProvider(slug))
                  ..invalidate(bookingSettingsProvider);
              },
            ),
          ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

enum _Step { when, where, review }

class _BookFlow extends ConsumerStatefulWidget {
  const _BookFlow({required this.service, required this.settings});

  final HomeService service;
  final BookingSettings settings;

  @override
  ConsumerState<_BookFlow> createState() => _BookFlowState();
}

class _BookFlowState extends ConsumerState<_BookFlow> {
  final _formKey = GlobalKey<FormState>();
  final _area = TextEditingController();
  final _building = TextEditingController();
  final _apartment = TextEditingController();
  final _directions = TextEditingController();
  final _instructions = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();

  _Step _step = _Step.when;
  late int _hours = widget.settings.minHours;
  late DateTime _day = _firstOpenDay();
  DateTime? _slot;

  /// The saved address chosen; null = a new address typed in.
  String? _addressId;
  bool _addressTouched = false;
  late String _emirate = ref.read(serviceLocationProvider);
  bool _saveAddress = true;

  PaymentMethod _payment = PaymentMethod.cash;
  bool _submitting = false;
  String? _error;
  final _scroll = ScrollController();
  String? _reference;

  HomeService get _service => widget.service;
  BookingSettings get _settings => widget.settings;
  bool get _isHourly => _service.bookingType == BookingType.hourly;
  bool get _isRequest => _service.bookingType == BookingType.request;
  int? get _bookedHours => _isHourly ? _hours : null;

  (String, String, int?) get _slotsKey =>
      (_service.id, isoDate(_day), _bookedHours);

  DateTime _firstOpenDay() {
    final days = _settings.bookableDays();
    return days.firstWhere(_settings.isOpenOn, orElse: () => days.first);
  }

  @override
  void initState() {
    super.initState();
    // Fill in the customer's details once their profile has loaded.
    ref.listenManual(myProfileProvider, (_, next) {
      final profile = next.value;
      if (profile == null) return;
      void fill(TextEditingController field, String? value) {
        if (field.text.isEmpty && value != null) field.text = value;
      }

      fill(_name, profile.fullName);
      fill(_phone, profile.phone);
    }, fireImmediately: true);
    // Start with the customer's default (first) saved address.
    ref.listenManual(savedAddressesProvider, (_, next) {
      final addresses = next.value;
      if (addresses == null || addresses.isEmpty || _addressTouched) return;
      if (mounted) setState(() => _addressId = addresses.first.id);
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _area.dispose();
    _building.dispose();
    _apartment.dispose();
    _directions.dispose();
    _instructions.dispose();
    _name.dispose();
    _phone.dispose();
    _scroll.dispose();
    super.dispose();
  }

  bool get _canContinue => switch (_step) {
    _Step.when => _slot != null,
    _Step.where || _Step.review => true,
  };

  void _next() {
    if (_step == _Step.where &&
        !(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    setState(() {
      _error = null;
      _step = _Step.values[_step.index + 1];
    });
  }

  void _back() {
    setState(() {
      _error = null;
      _step = _Step.values[_step.index - 1];
    });
  }

  void _chooseDay(DateTime day) {
    setState(() {
      _day = day;
      _slot = null;
    });
  }

  void _chooseHours(int hours) {
    setState(() {
      _hours = hours;
      _slot = null;
    });
  }

  SavedAddress? _savedAddress(List<SavedAddress> addresses) {
    final id = _addressId;
    if (id == null) return null;
    for (final address in addresses) {
      if (address.id == id) return address;
    }
    return null;
  }

  /// The address as it will be stored on the booking.
  AddressInput _addressInput() {
    final saved = _savedAddress(
      ref.read(savedAddressesProvider).value ?? const [],
    );
    if (saved != null) {
      return AddressInput(
        emirate: saved.emirate,
        area: saved.area,
        building: saved.building,
        apartment: saved.apartment,
        notes: saved.instructions,
        label: saved.label,
      );
    }
    return AddressInput(
      emirate: _emirate,
      area: _area.text.trim(),
      building: _building.text.trim(),
      apartment: _apartment.text.trim(),
      notes: _directions.text.trim(),
    );
  }

  Future<void> _confirm() async {
    final slot = _slot;
    if (slot == null || _submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final repository = ref.read(bookingRepositoryProvider);
    try {
      final address = _addressInput();
      var addressId = _savedAddress(
        ref.read(savedAddressesProvider).value ?? const [],
      )?.id;
      if (addressId == null && _saveAddress) {
        final saved = await repository.saveAddress(address);
        addressId = saved.id;
        if (!mounted) return;
        ref.invalidate(savedAddressesProvider);
        // A retry after a failed booking uses the saved address (no
        // duplicate is saved).
        setState(() {
          _addressId = saved.id;
          _addressTouched = true;
        });
      }
      final reference = await repository.createBooking(
        BookingDraft(
          serviceId: _service.id,
          hours: _bookedHours,
          startsAt: slot,
          addressId: addressId,
          address: address,
          instructions: _instructions.text.trim(),
          customerName: _name.text.trim(),
          customerPhone: _phone.text.trim().replaceAll(RegExp(r'[\s-]'), ''),
          paymentMethod: _payment,
        ),
      );
      if (!mounted) return;
      ref.invalidate(myBookingsProvider);
      haptic(context, HapticKind.success);
      setState(() {
        _submitting = false;
        _reference = reference;
      });
    } on Object catch (error) {
      if (!mounted) return;
      haptic(context, HapticKind.error);
      // The slot may have just been taken: refresh the times.
      ref.invalidate(timeSlotsProvider(_slotsKey));
      setState(() {
        _submitting = false;
        _error = AppFailure.from(error).message;
      });
      // The message and "Choose another time" sit at the end of the review:
      // bring them into view.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        unawaited(
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          ),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final reference = _reference;
    if (reference != null) {
      return _Success(reference: reference, isRequest: _isRequest);
    }

    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenPadding,
          ),
          child: _Progress(current: _step.index, total: _Step.values.length),
        ),
        Expanded(
          child: Form(
            key: _formKey,
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenPadding,
                AppSpacing.md,
                AppSpacing.screenPadding,
                AppSpacing.xl,
              ),
              children: switch (_step) {
                _Step.when => _whenStep(),
                _Step.where => _whereStep(),
                _Step.review => _reviewStep(),
              },
            ),
          ),
        ),
        DecoratedBox(
          decoration: const BoxDecoration(
            color: AppColors.white,
            boxShadow: AppShadows.soft,
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.screenPadding,
              AppSpacing.sm,
              AppSpacing.screenPadding,
              bottomInset + AppSpacing.sm,
            ),
            child: Row(
              children: [
                if (_step.index > 0) ...[
                  Expanded(
                    child: AppButton(
                      label: 'Back',
                      variant: AppButtonVariant.outline,
                      onPressed: _submitting ? null : _back,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                ],
                Expanded(
                  child: _step == _Step.review
                      ? AppButton(
                          label: _isRequest ? 'Send request' : 'Confirm booking',
                          isLoading: _submitting,
                          onPressed: _submitting ? null : _confirm,
                        )
                      : AppButton(
                          label: 'Continue',
                          onPressed: _canContinue ? _next : null,
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // --- Step 1: hours, day and time -----------------------------------------

  List<Widget> _whenStep() {
    final duration = _service.durationMinutes;
    return [
      if (_isHourly) ...[
        const _StepHeading('How many hours?'),
        _HoursPicker(
          value: _hours,
          min: _settings.minHours,
          max: _settings.maxHours,
          onChanged: _chooseHours,
        ),
      ] else if (_service.bookingType == BookingType.visit)
        Text(
          'This visit takes about '
          '${Formatters.duration(duration ?? _settings.defaultVisitMinutes)}.',
          style: AppTypography.bodyMedium,
        )
      else
        const Text(
          'Choose a time that suits you. Our team will call you to confirm '
          'the details and the price.',
          style: AppTypography.bodyMedium,
        ),
      const _StepHeading('Day'),
      BookingDayStrip(
        days: _settings.bookableDays(),
        selected: _day,
        isOpen: _settings.isOpenOn,
        onSelect: _chooseDay,
      ),
      _StepHeading(_isRequest ? 'Preferred time' : 'Time'),
      BookingSlotPicker(
        slotsKey: _slotsKey,
        selected: _slot,
        isOpenDay: _settings.isOpenOn(_day),
        onSelect: (slot) => setState(() => _slot = slot),
      ),
      const SizedBox(height: AppSpacing.sm),
      const Text('All times are UAE time.', style: AppTypography.bodySmall),
    ];
  }

  // --- Step 2: address, instructions and contact details -------------------

  List<Widget> _whereStep() {
    final addresses = ref.watch(savedAddressesProvider).value ?? const [];
    final useNew = _savedAddress(addresses) == null;

    return [
      const _StepHeading('Address'),
      for (final address in addresses) ...[
        OptionCard(
          icon: Icons.home_rounded,
          title: address.label,
          subtitle: address.summary,
          selected: _addressId == address.id,
          onTap: () => setState(() {
            _addressId = address.id;
            _addressTouched = true;
          }),
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
      if (addresses.isNotEmpty) ...[
        OptionCard(
          icon: Icons.add_location_alt_rounded,
          title: 'A new address',
          selected: useNew,
          onTap: () => setState(() {
            _addressId = null;
            _addressTouched = true;
          }),
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
      if (useNew) ..._newAddressFields(),
      const _StepHeading('Instructions for our team'),
      AppTextField(
        controller: _instructions,
        label: 'Instructions (optional)',
        hint: 'e.g. focus on the kitchen, bring ironing board',
        maxLines: 3,
        keyboardType: TextInputType.multiline,
        textCapitalization: TextCapitalization.sentences,
        validator: BookingValidators.instructions,
      ),
      const _StepHeading('Your details'),
      AppTextField(
        controller: _name,
        label: 'Full name',
        prefixIcon: Icons.person_rounded,
        textCapitalization: TextCapitalization.words,
        autofillHints: const [AutofillHints.name],
        validator: Validators.fullName,
      ),
      const SizedBox(height: AppSpacing.md),
      AppTextField(
        controller: _phone,
        label: 'Phone number',
        hint: '+971 50 123 4567',
        prefixIcon: Icons.phone_rounded,
        keyboardType: TextInputType.phone,
        autofillHints: const [AutofillHints.telephoneNumber],
        validator: EnquiryValidators.phone,
      ),
    ];
  }

  List<Widget> _newAddressFields() {
    return [
      const SizedBox(height: AppSpacing.xs),
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
          'Save this address for next time',
          style: AppTypography.bodyMedium,
        ),
        value: _saveAddress,
        onChanged: (value) => setState(() => _saveAddress = value ?? false),
      ),
    ];
  }

  // --- Step 3: review and payment ------------------------------------------

  List<Widget> _reviewStep() {
    final slot = _slot!;
    final address = _addressInput();
    final estimate = priceEstimate(_service, _bookedHours);
    final basePrice = _service.basePrice;
    final instructions = _instructions.text.trim();
    final error = _error;
    final addressLine = [
      if (address.apartment.isNotEmpty) address.apartment,
      address.building,
      address.area,
      address.emirate,
    ].join(', ');

    final String priceText;
    if (estimate == null) {
      priceText = 'Confirmed by our team';
    } else if (_isHourly &&
        _service.priceUnit == PriceUnit.perHour &&
        basePrice != null) {
      priceText =
          '${Formatters.aed(estimate)} '
          '(${hoursLabel(_hours)} × ${Formatters.aed(basePrice)})';
    } else {
      priceText = Formatters.aed(estimate);
    }

    return [
      _StepHeading(_isRequest ? 'Review your request' : 'Review your booking'),
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SummaryRow(label: 'Service', value: _service.name),
            if (_isHourly)
              SummaryRow(label: 'Duration', value: hoursLabel(_hours)),
            SummaryRow(
              label: _isRequest ? 'Preferred time' : 'Date and time',
              value: formatUaeDayTime(slot),
            ),
            SummaryRow(label: 'Address', value: addressLine),
            if (address.notes.isNotEmpty)
              SummaryRow(label: 'Directions', value: address.notes),
            if (instructions.isNotEmpty)
              SummaryRow(label: 'Instructions', value: instructions),
            const Divider(height: AppSpacing.lg),
            SummaryRow(label: 'Name', value: _name.text.trim()),
            SummaryRow(label: 'Phone', value: _phone.text.trim()),
            const Divider(height: AppSpacing.lg),
            SummaryRow(label: 'Estimated price', value: priceText),
          ],
        ),
      ),
      const _StepHeading('Payment'),
      const Text(
        'Nothing is charged now. You pay when the job is done.',
        style: AppTypography.bodySmall,
      ),
      const SizedBox(height: AppSpacing.xs),
      Wrap(
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        children: [
          for (final method in PaymentMethod.values)
            AppChip(
              label: method.label,
              icon: method == PaymentMethod.cash
                  ? Icons.payments_rounded
                  : Icons.credit_card_rounded,
              selected: _payment == method,
              onTap: () => setState(() => _payment = method),
            ),
        ],
      ),
      const SizedBox(height: AppSpacing.md),
      Text(
        _isRequest
            ? 'Our team will call you to confirm the time and the final price.'
            : 'Our team will confirm your booking and assign a professional. '
                  'Free cancellation or rescheduling up to '
                  '${_settings.cancelHours} hours before the start.',
        style: AppTypography.bodySmall,
      ),
      if (error != null) ...[
        const SizedBox(height: AppSpacing.md),
        Text(
          error,
          style: AppTypography.bodyMedium.copyWith(color: AppColors.error),
        ),
        if (!_isRequest) ...[
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            label: 'Choose another time',
            variant: AppButtonVariant.outline,
            onPressed: _submitting
                ? null
                : () => setState(() {
                    _error = null;
                    _slot = null;
                    _step = _Step.when;
                  }),
          ),
        ],
      ],
    ];
  }
}

/// Validation for booking-form fields (limits match the database).
abstract final class BookingValidators {
  static const int maxInstructionsLength = 1000;
  static const int maxDirectionsLength = 500;

  static String? area(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Please enter the area.';
    if (text.length < 2 || text.length > 120) {
      return 'Please enter 2 to 120 characters.';
    }
    return null;
  }

  static String? building(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Please enter the building or villa.';
    if (text.length > 120) return 'Please keep it under 120 characters.';
    return null;
  }

  static String? apartment(String? value) {
    if ((value?.trim().length ?? 0) > 40) {
      return 'Please keep it under 40 characters.';
    }
    return null;
  }

  static String? directions(String? value) {
    if ((value?.trim().length ?? 0) > maxDirectionsLength) {
      return 'Please keep it under $maxDirectionsLength characters.';
    }
    return null;
  }

  static String? instructions(String? value) {
    if ((value?.trim().length ?? 0) > maxInstructionsLength) {
      return 'Please keep it under $maxInstructionsLength characters.';
    }
    return null;
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.current, required this.total});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Step ${current + 1} of $total',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Step ${current + 1} of $total',
            style: AppTypography.labelMedium.copyWith(
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          ClipRRect(
            borderRadius: AppRadius.pillAll,
            child: LinearProgressIndicator(
              value: (current + 1) / total,
              minHeight: 6,
              backgroundColor: AppColors.lightBlue,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _StepHeading extends StatelessWidget {
  const _StepHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg, bottom: AppSpacing.xs),
      child: Semantics(
        header: true,
        child: Text(text, style: AppTypography.titleMedium),
      ),
    );
  }
}

/// − / + for the number of hours.
class _HoursPicker extends StatelessWidget {
  const _HoursPicker({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        AppIconButton(
          icon: Icons.remove_rounded,
          tooltip: 'Fewer hours',
          onPressed: value > min ? () => onChanged(value - 1) : null,
        ),
        Expanded(
          child: Text(
            hoursLabel(value),
            style: AppTypography.titleMedium,
            textAlign: TextAlign.center,
          ),
        ),
        AppIconButton(
          icon: Icons.add_rounded,
          tooltip: 'More hours',
          onPressed: value < max ? () => onChanged(value + 1) : null,
        ),
      ],
    );
  }
}

class _Success extends StatelessWidget {
  const _Success({required this.reference, required this.isRequest});

  final String reference;
  final bool isRequest;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        children: [
          const SizedBox(height: AppSpacing.xl),
          Container(
            width: 96,
            height: 96,
            decoration: const BoxDecoration(
              color: AppColors.lightBlue,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_rounded,
              size: 52,
              color: AppColors.success,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            isRequest ? 'Request sent' : 'Booking received',
            style: AppTypography.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Reference $reference',
            style: AppTypography.titleMedium.copyWith(
              color: AppColors.primary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            isRequest
                ? 'Our team will call you to confirm the time and the price.'
                : 'Our team will confirm your booking and let you know who '
                      'is coming. You pay on completion.',
            style: AppTypography.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xl),
          AppButton(
            label: 'View my bookings',
            onPressed: () => context.go(AppRoutes.bookings),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            label: 'Back to Home',
            variant: AppButtonVariant.outline,
            onPressed: () => context.go(AppRoutes.home),
          ),
        ],
      ),
    );
  }
}
