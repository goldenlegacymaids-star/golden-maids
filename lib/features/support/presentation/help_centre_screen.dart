import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/agency_contact.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../candidates/presentation/candidate_profile_screen.dart';
import '../domain/help_topics.dart';

/// Profile → Help Centre: common questions and ways to reach the agency.
class HelpCentreScreen extends ConsumerWidget {
  const HelpCentreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return PageScaffold(
      title: 'Help Centre',
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.screenPadding,
          AppSpacing.xs,
          AppSpacing.screenPadding,
          bottomInset + AppSpacing.xl,
        ),
        children: [
          const _ContactCard(),
          for (final section in helpSections()) ...[
            const SizedBox(height: AppSpacing.lg),
            Semantics(
              header: true,
              child: Text(section.title, style: AppTypography.titleMedium),
            ),
            const SizedBox(height: AppSpacing.xs),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final (index, topic) in section.topics.indexed) ...[
                    if (index > 0) const Divider(height: 1),
                    _Question(topic: topic),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Question extends StatelessWidget {
  const _Question({required this.topic});

  final HelpTopic topic;

  @override
  Widget build(BuildContext context) {
    return Theme(
      // No divider lines from the expansion tile itself.
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        title: Text(topic.question, style: AppTypography.titleSmall),
        tilePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        childrenPadding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.md,
        ),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [Text(topic.answer, style: AppTypography.bodyMedium)],
      ),
    );
  }
}

class _ContactCard extends ConsumerWidget {
  const _ContactCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppCard(
      color: AppColors.veryLightBlue,
      shadow: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Need help?', style: AppTypography.titleMedium),
          const SizedBox(height: AppSpacing.xxs),
          const Text(
            'Our team is happy to help with hiring, visas and your account.',
            style: AppTypography.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            label: 'Call ${AgencyContact.phoneDisplay}',
            icon: Icons.call_rounded,
            onPressed: () => openExternal(
              context,
              ref,
              AgencyContact.callUri(),
              failureMessage:
                  'Could not open the phone app. Please call '
                  '${AgencyContact.phoneDisplay}.',
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: 'WhatsApp',
                  icon: Icons.chat_rounded,
                  variant: AppButtonVariant.outline,
                  onPressed: () => openExternal(
                    context,
                    ref,
                    AgencyContact.whatsAppUri(
                      'Hello Golden Maids, I need help with the app.',
                    ),
                    failureMessage:
                        'Could not open WhatsApp. Please message '
                        '${AgencyContact.phoneDisplay}.',
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: AppButton(
                  label: 'Email',
                  icon: Icons.email_rounded,
                  variant: AppButtonVariant.outline,
                  onPressed: () => openExternal(
                    context,
                    ref,
                    AgencyContact.emailUri('Help with the Golden Maids app'),
                    failureMessage:
                        'Could not open your email app. Please write to '
                        '${AgencyContact.email}.',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
