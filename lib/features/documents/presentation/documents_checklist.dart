import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_card.dart';
import '../data/document_repository.dart';
import '../domain/customer_document.dart';
import 'my_documents_screen.dart';

/// "Documents you'll need" for the GCC Sponsor visa, with what the customer
/// has already sent, and a link to My Documents.
class DocumentsChecklist extends ConsumerWidget {
  const DocumentsChecklist({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final documents =
        ref.watch(myDocumentsProvider).value ?? const <CustomerDocument>[];
    CustomerDocument? find(DocumentType type) {
      for (final document in documents) {
        if (document.type == type) return document;
      }
      return null;
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text("Documents you'll need", style: AppTypography.titleSmall),
          const SizedBox(height: AppSpacing.xxs),
          const Text(
            'For the GCC Sponsor Visa. You can send them now or later from '
            'Profile → My Documents.',
            style: AppTypography.bodySmall,
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final type in DocumentType.values)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
              child: Row(
                children: [
                  const Icon(
                    Icons.description_outlined,
                    size: 18,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(type.label, style: AppTypography.bodyMedium),
                  ),
                  if (find(type) case final document?)
                    DocumentStatusBadge(status: document.status)
                  else
                    const Text('Not sent', style: AppTypography.bodySmall),
                ],
              ),
            ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () => unawaited(context.push(AppRoutes.myDocuments)),
              icon: const Icon(Icons.folder_open_rounded),
              label: const Text('Open My Documents'),
            ),
          ),
        ],
      ),
    );
  }
}
