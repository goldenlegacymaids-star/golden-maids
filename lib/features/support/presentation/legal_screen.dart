import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../domain/legal_texts.dart';

/// Shows the Privacy Policy or the Terms and Conditions.
class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key, required this.document});

  final LegalDocument document;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return PageScaffold(
      title: document.title,
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.screenPadding,
          AppSpacing.xs,
          AppSpacing.screenPadding,
          bottomInset + AppSpacing.xl,
        ),
        children: [
          if (LegalTexts.isDraft) ...[
            const AppCard(
              color: AppColors.veryLightBlue,
              shadow: false,
              child: Row(
                children: [
                  Icon(Icons.edit_note_rounded, color: AppColors.primary),
                  SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Draft: this text is being reviewed and may change.',
                      style: AppTypography.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          Text(
            '${LegalTexts.isDraft ? 'Draft of' : 'Last updated'} '
            '${document.updated}',
            style: AppTypography.bodySmall,
          ),
          for (final section in document.sections) ...[
            const SizedBox(height: AppSpacing.lg),
            Semantics(
              header: true,
              child: Text(section.heading, style: AppTypography.titleMedium),
            ),
            for (final paragraph in section.paragraphs) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(paragraph, style: AppTypography.bodyMedium),
            ],
          ],
        ],
      ),
    );
  }
}
