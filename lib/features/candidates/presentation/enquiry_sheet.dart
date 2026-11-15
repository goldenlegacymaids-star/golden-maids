import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_chip.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../profile/data/profile_repository.dart';
import '../data/candidate_repository.dart';
import '../domain/candidate.dart';
import '../domain/candidate_profile.dart';

/// Shows the "Request Info" form. Returns the enquiry reference when sent.
Future<String?> showEnquirySheet(
  BuildContext context, {
  required Candidate candidate,
}) {
  return showModalBottomSheet<String>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (context) => EnquirySheet(candidate: candidate),
  );
}

/// Form validation for the enquiry fields.
abstract final class EnquiryValidators {
  static const int maxMessageLength = 1000;

  static final RegExp _phoneCharacters = RegExp(r'^\+?[\d\s-]+$');

  static String? message(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Please write your question.';
    if (text.length > maxMessageLength) {
      return 'Please keep it under $maxMessageLength characters.';
    }
    return null;
  }

  static String? phone(String? value) {
    final text = value?.trim() ?? '';
    final digits = text.replaceAll(RegExp(r'\D'), '').length;
    if (text.isEmpty) return 'Please enter your phone number.';
    if (!_phoneCharacters.hasMatch(text) || digits < 7 || digits > 15) {
      return 'Please enter a valid phone number, e.g. +971 50 123 4567.';
    }
    return null;
  }

  /// Email is optional.
  static String? optionalEmail(String? value) {
    final text = value?.trim() ?? '';
    return text.isEmpty ? null : Validators.email(text);
  }
}

class EnquirySheet extends ConsumerStatefulWidget {
  const EnquirySheet({super.key, required this.candidate});

  final Candidate candidate;

  @override
  ConsumerState<EnquirySheet> createState() => _EnquirySheetState();
}

class _EnquirySheetState extends ConsumerState<EnquirySheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _message;
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  ContactMethod _contactMethod = ContactMethod.phone;

  /// Shown above the Send button (a snackbar would be hidden by the sheet).
  String? _error;

  @override
  void initState() {
    super.initState();
    _message = TextEditingController(
      text: "Hello, I'd like more information about "
          '${widget.candidate.title} (${widget.candidate.code}).',
    );
    _name = TextEditingController();
    _phone = TextEditingController();
    _email = TextEditingController();
    // Fill in the customer's details once their profile has loaded
    // (fields the customer already typed in are left alone).
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
  }

  @override
  void dispose() {
    _message.dispose();
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final email = _email.text.trim();
    final enquiry = CandidateEnquiry(
      candidateId: widget.candidate.id,
      name: _name.text.trim(),
      phone: _phone.text.trim(),
      email: email.isEmpty ? null : email,
      message: _message.text.trim(),
      contactMethod: _contactMethod,
    );
    setState(() => _error = null);
    try {
      final reference = await ref
          .read(candidateRepositoryProvider)
          .sendEnquiry(enquiry);
      if (mounted) Navigator.of(context).pop(reference);
    } on Object catch (error) {
      if (mounted) setState(() => _error = AppFailure.from(error).message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;

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
                  const Text('Request Info', style: AppTypography.titleLarge),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    'Ask us anything about ${widget.candidate.title}. Our '
                    'recruitment team will get back to you.',
                    style: AppTypography.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  AppTextField(
                    controller: _message,
                    label: 'Your question',
                    maxLines: 4,
                    keyboardType: TextInputType.multiline,
                    textCapitalization: TextCapitalization.sentences,
                    validator: EnquiryValidators.message,
                  ),
                  const SizedBox(height: AppSpacing.md),
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
                  const SizedBox(height: AppSpacing.md),
                  const Text(
                    'How should we reply?',
                    style: AppTypography.titleSmall,
                  ),
                  const SizedBox(height: AppSpacing.xs),
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
                  const SizedBox(height: AppSpacing.xl),
                  if (_error case final error?) ...[
                    Text(
                      error,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.error,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  AppButton(label: 'Send', onPressed: _send),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
