import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/haptics/haptics.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_refresh_indicator.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../authentication/data/auth_providers.dart';
import '../../candidates/presentation/candidate_profile_screen.dart'
    show openExternal;
import '../data/document_repository.dart';
import '../domain/customer_document.dart';
import 'document_sample.dart';

final _uploadedOn = DateFormat('d MMM yyyy');

/// Profile → My Documents: the customer's documents for the GCC Sponsor
/// visa. Each can be uploaded, viewed, replaced or deleted; the agency
/// approves it or asks for a new copy.
class MyDocumentsScreen extends ConsumerWidget {
  const MyDocumentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final documents = ref.watch(myDocumentsProvider);
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return PageScaffold(
      title: 'My Documents',
      body: documents.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => SingleChildScrollView(
          child: ErrorState(
            failure: AppFailure.from(error),
            onRetry: () => ref.invalidate(myDocumentsProvider),
          ),
        ),
        data: (list) => AppRefreshIndicator(
          onRefresh: () async {
            ref.invalidate(myDocumentsProvider);
            try {
              await ref.read(myDocumentsProvider.future);
            } on Object {
              // Shown in place of the list.
            }
          },
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.screenPadding,
              AppSpacing.xs,
              AppSpacing.screenPadding,
              bottomInset + AppSpacing.xl,
            ),
            children: [
              const _PrivacyNote(),
              const SizedBox(height: AppSpacing.md),
              for (final type in DocumentType.values) ...[
                DocumentCard(
                  type: type,
                  document: _find(list, type),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static CustomerDocument? _find(List<CustomerDocument> list, DocumentType t) {
    for (final document in list) {
      if (document.type == t) return document;
    }
    return null;
  }
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: const BoxDecoration(
        color: AppColors.lightBlue,
        borderRadius: AppRadius.mdAll,
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_rounded, size: 20, color: AppColors.infoText),
          SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Needed for the GCC Sponsor Visa. Only you and the Golden '
              'Maids recruitment team can open these files. PDF, JPG or '
              'PNG, up to 10 MB each.',
              style: AppTypography.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// One document type: its status and what the customer can do with it.
class DocumentCard extends ConsumerStatefulWidget {
  const DocumentCard({super.key, required this.type, required this.document});

  final DocumentType type;
  final CustomerDocument? document;

  @override
  ConsumerState<DocumentCard> createState() => _DocumentCardState();
}

class _DocumentCardState extends ConsumerState<DocumentCard> {
  bool _busy = false;

  Future<void> _upload() async {
    final user =
        ref.read(authStateProvider).value ??
        ref.read(authRepositoryProvider).currentUser;
    if (user == null) return;
    final PickedDocument? file;
    try {
      file = await ref.read(documentPickerProvider)();
    } on Object {
      if (mounted) {
        showAppSnackBar(
          context,
          "The file couldn't be opened. Please try another one.",
          isError: true,
        );
      }
      return;
    }
    if (file == null || !mounted) return;
    final problem = file.problem;
    if (problem != null) {
      showAppSnackBar(context, problem, isError: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(documentRepositoryProvider)
          .upload(
            customerId: user.id,
            type: widget.type,
            file: file,
            existing: widget.document,
          );
      if (!mounted) return;
      ref.invalidate(myDocumentsProvider);
      haptic(context, HapticKind.success);
      showAppSnackBar(
        context,
        '${widget.type.label} sent. The agency will review it.',
      );
    } on Object catch (error) {
      if (mounted) showErrorSnackBar(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _view(CustomerDocument document) async {
    try {
      final url = await ref.read(documentRepositoryProvider).viewUrl(document);
      if (!mounted) return;
      await openExternal(
        context,
        ref,
        Uri.parse(url),
        failureMessage: "This document couldn't be opened.",
      );
    } on Object catch (error) {
      if (mounted) showErrorSnackBar(context, error);
    }
  }

  Future<void> _delete(CustomerDocument document) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete your ${widget.type.label}?'),
        content: const Text(
          'The file is removed from Golden Maids. You can upload it again '
          'at any time.',
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
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(documentRepositoryProvider).delete(document);
      if (!mounted) return;
      ref.invalidate(myDocumentsProvider);
      showAppSnackBar(context, '${widget.type.label} deleted.');
    } on Object catch (error) {
      if (mounted) showErrorSnackBar(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final document = widget.document;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              DocumentSample(type: widget.type),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.type.label, style: AppTypography.titleSmall),
                    Text(
                      document == null
                          ? 'Not uploaded yet'
                          : '${document.fileName} · '
                                '${fileSizeLabel(document.sizeBytes)} · '
                                '${_uploadedOn.format(document.uploadedAt.toLocal())}',
                      style: AppTypography.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (document != null) ...[
                const SizedBox(width: AppSpacing.xs),
                DocumentStatusBadge(status: document.status),
              ],
            ],
          ),
          if (document != null &&
              document.status == DocumentStatus.needsNewCopy &&
              document.staffNote.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.08),
                borderRadius: AppRadius.smAll,
              ),
              child: Text(
                'From the agency: ${document.staffNote}',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          if (_busy)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.xs),
                child: CircularProgressIndicator(),
              ),
            )
          else if (document == null)
            AppButton(
              label: 'Upload',
              icon: Icons.upload_file_rounded,
              onPressed: () => unawaited(_upload()),
            )
          else
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                TextButton.icon(
                  onPressed: () => unawaited(_view(document)),
                  icon: const Icon(Icons.visibility_rounded),
                  label: const Text('View'),
                ),
                TextButton.icon(
                  onPressed: () => unawaited(_upload()),
                  icon: const Icon(Icons.upload_file_rounded),
                  label: const Text('Replace'),
                ),
                TextButton.icon(
                  onPressed: () => unawaited(_delete(document)),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.error,
                  ),
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Delete'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// "Under review", "Approved" or "Needs a new copy".
class DocumentStatusBadge extends StatelessWidget {
  const DocumentStatusBadge({super.key, required this.status});

  final DocumentStatus status;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (status) {
      DocumentStatus.approved => (AppColors.successSoft, AppColors.successText),
      DocumentStatus.needsNewCopy => (
        AppColors.error.withValues(alpha: 0.1),
        AppColors.errorText,
      ),
      DocumentStatus.submitted => (AppColors.lightBlue, AppColors.infoText),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppRadius.pillAll,
      ),
      child: Text(
        status.label,
        style: AppTypography.labelSmall.copyWith(color: foreground),
      ),
    );
  }
}
