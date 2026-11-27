import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/agency_contact.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../domain/candidate.dart';
import 'candidate_profile_screen.dart' show openExternal;

/// The WhatsApp message for hiring [candidate], as on the website, and
/// saying it was sent from the app.
String hireWhatsAppMessage(Candidate candidate) {
  final name = candidate.displayName;
  final who = name == null
      ? 'maid code ${candidate.code}'
      : '$name (maid code ${candidate.code})';
  return 'Hello Golden Legacy, I would like to hire $who.\n'
      '(Sent from the mobile app)';
}

/// The WhatsApp message for a question about [candidate] (contact bar).
String enquiryWhatsAppMessage(Candidate candidate) {
  final name = candidate.displayName;
  final who = name == null
      ? 'maid code ${candidate.code}'
      : '$name (maid code ${candidate.code})';
  return 'Hello Golden Legacy, I am interested in $who.\n'
      '(Sent from the mobile app)';
}

/// Opens WhatsApp with [hireWhatsAppMessage] typed in.
Future<void> openHireWhatsApp(
  BuildContext context,
  WidgetRef ref,
  Candidate candidate,
) => openExternal(
  context,
  ref,
  AgencyContact.whatsAppUri(hireWhatsAppMessage(candidate)),
  failureMessage: "WhatsApp couldn't be opened.",
);

/// Green "WhatsApp" button, as on the website.
class WhatsAppButton extends StatelessWidget {
  const WhatsAppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.height = 44,
  });

  final String label;
  final VoidCallback onPressed;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: AppColors.whatsApp,
        borderRadius: AppRadius.smAll,
        child: InkWell(
          borderRadius: AppRadius.smAll,
          onTap: onPressed,
          child: SizedBox(
            height: height,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.chat_rounded,
                    size: 18,
                    color: AppColors.onWhatsApp,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Flexible(
                    child: Text(
                      label,
                      style: AppTypography.labelLarge.copyWith(
                        color: AppColors.onWhatsApp,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
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
