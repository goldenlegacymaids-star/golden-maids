import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/phone_number.dart';

/// Mobile number input with a GCC country picker.
class PhoneField extends StatelessWidget {
  const PhoneField({
    super.key,
    required this.controller,
    required this.country,
    required this.onCountryChanged,
    this.textInputAction,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final GccCountry country;
  final ValueChanged<GccCountry> onCountryChanged;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  Future<void> _pickCountry(BuildContext context) async {
    final selected = await showModalBottomSheet<GccCountry>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.xl,
                0,
                AppSpacing.xl,
                AppSpacing.xs,
              ),
              child: Text('Select country', style: AppTypography.titleMedium),
            ),
            for (final option in GccCountries.all)
              ListTile(
                leading: Text(option.flag, style: const TextStyle(fontSize: 24)),
                title: Text(option.name, style: AppTypography.bodyLarge),
                trailing: Text(
                  '+${option.dialCode}',
                  style: AppTypography.labelLarge,
                ),
                selected: option == country,
                onTap: () => Navigator.of(context).pop(option),
              ),
          ],
        ),
      ),
    );
    if (selected != null) onCountryChanged(selected);
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.phone,
      textInputAction: textInputAction,
      autofillHints: const [AutofillHints.telephoneNumberNational],
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9 +\-]')),
        LengthLimitingTextInputFormatter(18),
      ],
      autovalidateMode: AutovalidateMode.onUserInteractionIfError,
      validator: (value) => PhoneNumbers.toE164(value ?? '', country) == null
          ? 'Enter a valid ${country.name} mobile number'
          : null,
      onFieldSubmitted: onSubmitted,
      style: AppTypography.bodyLarge,
      decoration: InputDecoration(
        labelText: 'Mobile number',
        hintText: country.example,
        prefixIcon: Semantics(
          button: true,
          label: 'Country code ${country.name}, +${country.dialCode}',
          child: InkWell(
            onTap: () => unawaited(_pickCountry(context)),
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.only(left: 14, right: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(country.flag, style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 6),
                  Text(
                    '+${country.dialCode}',
                    style: AppTypography.labelLarge,
                  ),
                  const Icon(
                    Icons.expand_more_rounded,
                    size: 18,
                    color: AppColors.textSecondary,
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
