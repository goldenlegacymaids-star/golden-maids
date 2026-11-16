import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/uae.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/phone_number.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_chip.dart';
import '../../../core/widgets/app_icon_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../candidates/data/candidate_repository.dart';
import '../../candidates/domain/candidate.dart';
import '../../candidates/domain/candidate_profile.dart';
import '../../candidates/presentation/enquiry_sheet.dart';
import '../../candidates/presentation/widgets/candidate_cards.dart';
import '../../candidates/presentation/widgets/nationality_flag.dart';
import '../../documents/presentation/documents_checklist.dart';
import '../../home/data/service_location.dart';
import '../../profile/data/profile_repository.dart';
import '../data/hiring_repository.dart';
import '../domain/hiring_request.dart';
import 'widgets/hiring_widgets.dart';

enum _Step { package, maid, details, review }

/// Hiring request form.
///
/// Started from a maid's profile ([candidateId] set: only her packages are
/// offered and the maid step is skipped) or from "Find a Maid" (package
/// first, then a maid offering it, or "let the agency recommend").
class HireScreen extends ConsumerWidget {
  const HireScreen({super.key, this.candidateId});

  final String? candidateId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = candidateId;

    if (id == null) {
      final packages = ref.watch(recruitmentPackagesProvider);
      return PageScaffold(
        title: 'Hire a Maid',
        body: packages.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => SingleChildScrollView(
            child: ErrorState(
              failure: AppFailure.from(error),
              onRetry: () => ref.invalidate(recruitmentPackagesProvider),
            ),
          ),
          data: (list) => _HireFlow(packages: list),
        ),
      );
    }

    final profile = ref.watch(candidateProfileProvider(id));
    return PageScaffold(
      title: 'Hire ${profile.value?.candidate.title ?? 'a Maid'}',
      body: profile.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => SingleChildScrollView(
          child: ErrorState(
            failure: AppFailure.from(error),
            onRetry: () => ref.invalidate(candidateProfileProvider(id)),
          ),
        ),
        data: (data) {
          final candidate = data.candidate;
          if (candidate.availability != CandidateAvailability.available ||
              data.packages.isEmpty) {
            return SingleChildScrollView(
              child: EmptyState(
                icon: Icons.event_busy_rounded,
                title: '${candidate.title} is not available right now',
                message:
                    'Browse other maids, or send us a request and we will '
                    'recommend someone similar.',
                actionLabel: 'Find a Maid',
                onAction: () => context.go(AppRoutes.maids),
              ),
            );
          }
          return _HireFlow(packages: data.packages, candidate: candidate);
        },
      ),
    );
  }
}

class _HireFlow extends ConsumerStatefulWidget {
  const _HireFlow({required this.packages, this.candidate});

  final List<RecruitmentPackage> packages;

  /// Pre-selected maid (started from her profile).
  final Candidate? candidate;

  @override
  ConsumerState<_HireFlow> createState() => _HireFlowState();
}

class _HireFlowState extends ConsumerState<_HireFlow> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _household = TextEditingController();
  final _requirements = TextEditingController();

  _Step _step = _Step.package;
  String? _visaType;
  RecruitmentPackage? _package;
  int? _months;
  String? _sponsorNationality;
  Candidate? _candidate;
  bool _recommend = false;

  /// Asked for when the agency recommends a maid and the price depends on
  /// her nationality.
  String? _preferredNationality;

  /// In or outside the UAE, when the agency recommends the maid.
  MaidLocation? _preferredLocation;
  late String _emirate = ref.read(serviceLocationProvider);
  bool _children = false;
  bool _elderly = false;
  bool _pets = false;
  DateTime? _startDate;
  ContactMethod _contactMethod = ContactMethod.phone;
  String? _error;
  String? _reference;

  bool get _maidPreselected => widget.candidate != null;

  List<_Step> get _steps => [
    _Step.package,
    if (!_maidPreselected) _Step.maid,
    _Step.details,
    _Step.review,
  ];

  @override
  void initState() {
    super.initState();
    _candidate = widget.candidate;
    // Fill in the customer's details once their profile has loaded.
    ref.listenManual(myProfileProvider, (_, next) {
      final profile = next.value;
      if (profile == null) return;
      void fill(TextEditingController field, String? value) {
        if (field.text.isEmpty && value != null) field.text = value;
      }

      fill(_name, profile.fullName);
      fill(_phone, profile.phone);
      fill(_email, profile.email);
    }, fireImmediately: true);
    // Only one visa type on offer (e.g. this maid is company visa only).
    final types = _visaTypes;
    if (types.length == 1) _chooseVisaType(types.single);
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _household.dispose();
    _requirements.dispose();
    super.dispose();
  }

  List<String> get _visaTypes => [
    for (final type in const ['company', 'sponsor'])
      if (widget.packages.any((p) => p.visaType == type)) type,
  ];

  List<RecruitmentPackage> get _packagesForVisa => [
    for (final p in widget.packages)
      if (p.visaType == _visaType) p,
  ];

  void _chooseVisaType(String type) {
    _visaType = type;
    _package = null;
    _months = null;
    _sponsorNationality = null;
    final packages = _packagesForVisa;
    if (packages.length == 1) _choosePackage(packages.single);
  }

  void _choosePackage(RecruitmentPackage package) {
    _package = package;
    final options = durationOptions(package);
    _months = options.length == 1 ? options.single : null;
    if (!package.requiresSponsorNationality) _sponsorNationality = null;
    _preferredNationality = null;
    _preferredLocation = null;
    // A maid chosen for another package may not offer this one.
    if (!_maidPreselected) {
      _candidate = null;
      _recommend = false;
    }
  }

  bool get _packageStepDone {
    final package = _package;
    return package != null &&
        _months != null &&
        (!package.requiresSponsorNationality || _sponsorNationality != null);
  }

  bool get _canContinue => switch (_step) {
    _Step.package => _packageStepDone,
    _Step.maid =>
      _candidate != null ||
          (_recommend &&
              _preferredLocation != null &&
              (!_package!.priceByNationality ||
                  _preferredNationality != null)),
    _Step.details || _Step.review => true,
  };

  void _next() {
    if (_step == _Step.details &&
        !(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final steps = _steps;
    setState(() {
      _error = null;
      _step = steps[steps.indexOf(_step) + 1];
    });
  }

  void _back() {
    final steps = _steps;
    setState(() {
      _error = null;
      _step = steps[steps.indexOf(_step) - 1];
    });
  }

  HiringDraft _draft() {
    final email = _email.text.trim();
    final household = _household.text.trim();
    return HiringDraft(
      packageId: _package!.id,
      durationMonths: _months!,
      sponsorNationality: _sponsorNationality,
      candidateId: _recommend ? null : _candidate?.id,
      // A chosen maid's nationality is filled in by the database.
      preferredNationality: _recommend ? _preferredNationality : null,
      maidLocation: _recommend ? _preferredLocation : null,
      name: _name.text.trim(),
      phone: _phone.text.trim(),
      email: email.isEmpty ? null : email,
      emirate: _emirate,
      householdSize: household.isEmpty ? null : int.parse(household),
      hasChildren: _children,
      hasElderly: _elderly,
      hasPets: _pets,
      preferredStartDate: _startDate,
      requirements: _requirements.text.trim(),
      contactMethod: _contactMethod,
    );
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    try {
      final reference = await ref
          .read(hiringRepositoryProvider)
          .submit(_draft());
      if (!mounted) return;
      ref.invalidate(myHiringRequestsProvider);
      setState(() => _reference = reference);
    } on Object catch (error) {
      if (mounted) setState(() => _error = AppFailure.from(error).message);
    }
  }

  Future<void> _pickStartDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? today.add(const Duration(days: 7)),
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
      helpText: 'Preferred start date',
    );
    if (picked != null && mounted) setState(() => _startDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    final reference = _reference;
    if (reference != null) return _Success(reference: reference);

    final steps = _steps;
    final index = steps.indexOf(_step);
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenPadding,
          ),
          child: _Progress(current: index, total: steps.length),
        ),
        Expanded(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenPadding,
                AppSpacing.md,
                AppSpacing.screenPadding,
                AppSpacing.xl,
              ),
              children: switch (_step) {
                _Step.package => _packageStep(),
                _Step.maid => [
                  _MaidStep(
                    package: _package!,
                    selected: _candidate,
                    recommend: _recommend,
                    onRecommend: () => setState(() {
                      _recommend = true;
                      _candidate = null;
                    }),
                    onSelect: (candidate) => setState(() {
                      _recommend = false;
                      _candidate = candidate;
                      _preferredNationality = null;
                      _preferredLocation = null;
                    }),
                  ),
                  if (_recommend) ..._locationChoice(),
                  if (_recommend && _package!.priceByNationality)
                    ..._nationalityChoice(_package!),
                ],
                _Step.details => _detailsStep(),
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
                if (index > 0) ...[
                  Expanded(
                    child: AppButton(
                      label: 'Back',
                      variant: AppButtonVariant.outline,
                      onPressed: _back,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                ],
                Expanded(
                  child: _step == _Step.review
                      ? AppButton(label: 'Submit request', onPressed: _submit)
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

  // --- Step 1: visa type, package, duration, sponsor nationality ---------

  List<Widget> _packageStep() {
    final package = _package;
    final types = _visaTypes;
    final candidate = _candidate;

    return [
      if (candidate != null) ...[
        _SelectedMaid(candidate: candidate),
        const SizedBox(height: AppSpacing.md),
      ],
      if (types.length > 1) ...[
        const _StepHeading('Visa type'),
        for (final type in types) ...[
          OptionCard(
            icon: type == 'company'
                ? Icons.badge_rounded
                : Icons.verified_user_rounded,
            title: type == 'company' ? 'Company visa' : 'GCC sponsor visa',
            subtitle: type == 'company'
                ? 'The maid works on our company visa. Hire monthly or '
                      'yearly.'
                : 'A 2-year contract with the visa sponsored by you '
                      '(GCC nationals).',
            selected: _visaType == type,
            onTap: () => setState(() => _chooseVisaType(type)),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
      if (_visaType != null && _packagesForVisa.length > 1) ...[
        const _StepHeading('Package'),
        for (final option in _packagesForVisa) ...[
          OptionCard(
            title: option.name,
            subtitle: option.description.isEmpty ? null : option.description,
            trailing: packagePriceLabel(
              option,
              nationality: _candidate?.nationality,
            ),
            selected: package?.id == option.id,
            onTap: () => setState(() => _choosePackage(option)),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
      if (package != null) ...[
        if (_packagesForVisa.length == 1) ...[
          const _StepHeading('Package'),
          OptionCard(
            title: package.name,
            subtitle: package.description.isEmpty ? null : package.description,
            trailing: packagePriceLabel(
              package,
              nationality: _candidate?.nationality,
            ),
            selected: true,
            onTap: () {},
          ),
        ],
        const _StepHeading('Duration'),
        _DurationPicker(
          options: durationOptions(package),
          value: _months,
          onChanged: (months) => setState(() => _months = months),
        ),
        if (package.requiresSponsorNationality) ...[
          const _StepHeading("Sponsor's nationality"),
          const Text(
            'The 2-year contract is for GCC nationals sponsoring the visa.',
            style: AppTypography.bodySmall,
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final country in GccCountries.all)
                AppChip(
                  label: country.name,
                  selected: _sponsorNationality == country.isoCode,
                  onTap: () => setState(
                    () => _sponsorNationality = country.isoCode,
                  ),
                ),
            ],
          ),
        ],
      ],
    ];
  }

  // --- Step 3: customer details ---------------------------------------------

  List<Widget> _detailsStep() {
    return [
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
      const SizedBox(height: AppSpacing.md),
      AppTextField(
        controller: _email,
        label: 'Email (optional)',
        prefixIcon: Icons.mail_rounded,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
        validator: EnquiryValidators.optionalEmail,
      ),
      const _StepHeading('Emirate'),
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
      const _StepHeading('Your household'),
      AppTextField(
        controller: _household,
        label: 'Number of people (optional)',
        prefixIcon: Icons.groups_rounded,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        validator: HiringValidators.householdSize,
      ),
      _Toggle(
        label: 'Children at home',
        value: _children,
        onChanged: (v) => setState(() => _children = v),
      ),
      _Toggle(
        label: 'Elderly family members',
        value: _elderly,
        onChanged: (v) => setState(() => _elderly = v),
      ),
      _Toggle(
        label: 'Pets',
        value: _pets,
        onChanged: (v) => setState(() => _pets = v),
      ),
      const _StepHeading('Preferred start date'),
      AppButton(
        label: _startDate == null
            ? 'Choose a date (optional)'
            : formatDay(_startDate!),
        icon: Icons.event_rounded,
        variant: AppButtonVariant.outline,
        onPressed: _pickStartDate,
      ),
      const _StepHeading('Anything else we should know?'),
      AppTextField(
        controller: _requirements,
        label: 'Requirements (optional)',
        hint: 'e.g. cooking Arabic food, caring for a baby',
        maxLines: 4,
        keyboardType: TextInputType.multiline,
        textCapitalization: TextCapitalization.sentences,
        validator: HiringValidators.requirements,
      ),
      const _StepHeading('How should we contact you?'),
      Wrap(
        spacing: AppSpacing.xs,
        children: [
          for (final method in ContactMethod.values)
            AppChip(
              label: method.label,
              selected: _contactMethod == method,
              onTap: () => setState(() => _contactMethod = method),
            ),
        ],
      ),
    ];
  }

  // --- Step 4: review -------------------------------------------------------

  /// In or outside the UAE, when the agency recommends the maid.
  List<Widget> _locationChoice() => [
    const _StepHeading('Where should she be?'),
    for (final location in MaidLocation.values) ...[
      OptionCard(
        icon: location == MaidLocation.inUae
            ? Icons.home_work_rounded
            : Icons.flight_land_rounded,
        title: location.label,
        subtitle: location == MaidLocation.inUae
            ? 'Already here: she can start sooner.'
            : 'Recruited from her country: arrival time depends on '
                  'her nationality.',
        selected: _preferredLocation == location,
        onTap: () => setState(() => _preferredLocation = location),
      ),
      const SizedBox(height: AppSpacing.sm),
    ],
  ];

  /// The maid's nationality and its price, when the agency recommends the
  /// maid and the package is priced by nationality.
  List<Widget> _nationalityChoice(RecruitmentPackage package) {
    final nationalities = ref.watch(maidNationalitiesProvider);
    return [
      const _StepHeading("Maid's nationality"),
      const Text(
        "The price of this package depends on the maid's nationality.",
        style: AppTypography.bodySmall,
      ),
      const SizedBox(height: AppSpacing.sm),
      ...nationalities.when<List<Widget>>(
        loading: () => [
          const Padding(
            padding: EdgeInsets.all(AppSpacing.md),
            child: Center(child: CircularProgressIndicator()),
          ),
        ],
        error: (error, _) => [
          ErrorState(
            failure: AppFailure.from(error),
            onRetry: () => ref.invalidate(maidNationalitiesProvider),
          ),
        ],
        data: (list) => [
          for (final item in list) ...[
            OptionCard(
              leading: FlagImage(code: item.code, height: 20),
              title: item.name,
              trailing: packagePriceLabel(package, nationality: item.name),
              selected: _preferredNationality == item.name,
              onTap: () => setState(() => _preferredNationality = item.name),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ],
      ),
    ];
  }

  List<Widget> _reviewStep() {
    final package = _package!;
    final candidate = _candidate;
    final error = _error;
    final household = [
      if (_household.text.trim().isNotEmpty) '${_household.text.trim()} people',
      if (_children) 'children',
      if (_elderly) 'elderly',
      if (_pets) 'pets',
    ];
    final email = _email.text.trim();
    final requirements = _requirements.text.trim();

    final nationality = _recommend
        ? _preferredNationality
        : candidate?.nationality;
    final location = _recommend ? _preferredLocation : candidate?.location;
    final arrival = nationality == null ? null : arrivalFor(ref, nationality);
    return [
      const _StepHeading('Review your request'),
      if (candidate != null && !_recommend) ...[
        _SelectedMaid(candidate: candidate),
        const SizedBox(height: AppSpacing.sm),
      ],
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SummaryRow(label: 'Package', value: package.name),
            SummaryRow(label: 'Duration', value: monthsLabel(_months!)),
            if (_sponsorNationality case final iso?)
              SummaryRow(
                label: "Sponsor's nationality",
                value: gccCountryName(iso),
              ),
            SummaryRow(
              label: 'Maid',
              value: _recommend
                  ? 'Agency recommendation'
                  : candidate?.title ?? '',
            ),
            if (nationality != null)
              SummaryRow(label: 'Nationality', value: nationality),
            if (location != null)
              SummaryRow(label: 'Where she is', value: location.label),
            if (location == MaidLocation.outsideUae)
              SummaryRow(
                label: 'Expected arrival',
                value: arrival == null
                    ? 'On request'
                    : '$arrival after confirmation',
              ),
            SummaryRow(
              label: 'Price',
              value: packagePriceLabel(package, nationality: nationality),
            ),
            const Divider(height: AppSpacing.lg),
            SummaryRow(label: 'Name', value: _name.text.trim()),
            SummaryRow(label: 'Phone', value: _phone.text.trim()),
            if (email.isNotEmpty) SummaryRow(label: 'Email', value: email),
            SummaryRow(label: 'Emirate', value: _emirate),
            if (household.isNotEmpty)
              SummaryRow(label: 'Household', value: household.join(', ')),
            if (_startDate case final date?)
              SummaryRow(label: 'Start date', value: formatDay(date)),
            if (requirements.isNotEmpty)
              SummaryRow(label: 'Requirements', value: requirements),
            SummaryRow(label: 'Contact by', value: _contactMethod.label),
          ],
        ),
      ),
      if (package.visaType == VisaRoute.sponsor.value) ...[
        const SizedBox(height: AppSpacing.sm),
        const DocumentsChecklist(),
      ],
      const SizedBox(height: AppSpacing.md),
      const Text(
        'No payment is taken now. Our recruitment team will confirm '
        'availability, the price and the next steps with you.',
        style: AppTypography.bodySmall,
      ),
      if (error != null) ...[
        const SizedBox(height: AppSpacing.md),
        Text(
          error,
          style: AppTypography.bodyMedium.copyWith(color: AppColors.error),
        ),
      ],
    ];
  }
}

/// Validation for hiring-form fields not shared with other forms.
abstract final class HiringValidators {
  static const int maxRequirementsLength = 2000;

  /// Optional; 1–30 people when given.
  static String? householdSize(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final size = int.tryParse(text);
    if (size == null || size < 1 || size > 30) {
      return 'Please enter a number from 1 to 30.';
    }
    return null;
  }

  static String? requirements(String? value) {
    if ((value?.trim().length ?? 0) > maxRequirementsLength) {
      return 'Please keep it under $maxRequirementsLength characters.';
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

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: AppTypography.bodyMedium),
      value: value,
      onChanged: onChanged,
    );
  }
}

/// Chips for a few options; a − / + stepper for many (e.g. 1–11 months).
class _DurationPicker extends StatelessWidget {
  const _DurationPicker({
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final List<int> options;
  final int? value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    if (options.length == 1) {
      return Text(
        '${monthsLabel(options.single)} (fixed)',
        style: AppTypography.titleSmall,
      );
    }
    if (options.length <= 4) {
      return Wrap(
        spacing: AppSpacing.xs,
        children: [
          for (final months in options)
            AppChip(
              label: monthsLabel(months),
              selected: value == months,
              onTap: () => onChanged(months),
            ),
        ],
      );
    }
    final current = value;
    final index = current == null ? -1 : options.indexOf(current);
    return Row(
      children: [
        AppIconButton(
          icon: Icons.remove_rounded,
          tooltip: 'Fewer months',
          onPressed: index > 0 ? () => onChanged(options[index - 1]) : null,
        ),
        Expanded(
          child: Text(
            current == null ? 'Choose' : monthsLabel(current),
            style: AppTypography.titleMedium,
            textAlign: TextAlign.center,
          ),
        ),
        AppIconButton(
          icon: Icons.add_rounded,
          tooltip: 'More months',
          onPressed: index < options.length - 1
              ? () => onChanged(options[index + 1])
              : null,
        ),
      ],
    );
  }
}

/// The chosen maid, shown at the top of the form and in the review.
class _SelectedMaid extends ConsumerWidget {
  const _SelectedMaid({required this.candidate});

  final Candidate candidate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photoUrl = ref
        .watch(candidateRepositoryProvider)
        .photoUrl(candidate.photoPath);
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(
        children: [
          CandidatePhoto(
            url: photoUrl,
            label: 'Photo of ${candidate.title}',
            width: 56,
            height: 56,
            iconSize: 28,
            borderRadius: AppRadius.mdAll,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(candidate.title, style: AppTypography.titleSmall),
                Text(
                  '${candidateSubtitle(candidate)} · ${candidate.nationality}',
                  style: AppTypography.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Step 2 (from "Find a Maid" only): choose a maid offering the package.
class _MaidStep extends ConsumerWidget {
  const _MaidStep({
    required this.package,
    required this.selected,
    required this.recommend,
    required this.onRecommend,
    required this.onSelect,
  });

  final RecruitmentPackage package;
  final Candidate? selected;
  final bool recommend;
  final VoidCallback onRecommend;
  final ValueChanged<Candidate> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = CandidateFilter(packageId: package.id, availableOnly: true);
    final candidates = ref.watch(candidateSearchProvider(filter));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _StepHeading('Choose a maid'),
        OptionCard(
          icon: Icons.auto_awesome_rounded,
          title: 'Let the agency recommend someone',
          subtitle: 'We will suggest maids who match your household.',
          selected: recommend,
          onTap: onRecommend,
        ),
        const SizedBox(height: AppSpacing.md),
        candidates.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(AppSpacing.xl),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => ErrorState(
            failure: AppFailure.from(error),
            onRetry: () => ref.invalidate(candidateSearchProvider(filter)),
          ),
          data: (list) => list.isEmpty
              ? const Text(
                  'No maids are available for this package right now. '
                  'Choose "Let the agency recommend someone".',
                  style: AppTypography.bodySmall,
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final candidate in list) ...[
                      OptionCard(
                        title: candidate.title,
                        subtitle: [
                          candidateSubtitle(candidate),
                          candidate.nationality,
                          if (package.priceByNationality)
                            packagePriceLabel(
                              package,
                              nationality: candidate.nationality,
                            ),
                        ].join(' · '),
                        trailing: salaryLabel(candidate),
                        selected: !recommend && selected?.id == candidate.id,
                        onTap: () => onSelect(candidate),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _Success extends StatelessWidget {
  const _Success({required this.reference});

  final String reference;

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
          const Text(
            'Request submitted',
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
          const Text(
            'Our recruitment team will review your request and contact you. '
            'You can follow its progress in My Hiring Requests.',
            style: AppTypography.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xl),
          AppButton(
            label: 'View my requests',
            onPressed: () => context.go(AppRoutes.hiringRequests),
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
