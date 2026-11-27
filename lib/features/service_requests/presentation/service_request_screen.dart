import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
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
import '../../candidates/presentation/candidate_profile_screen.dart'
    show openExternal;
import '../../documents/data/document_repository.dart';
import '../../hiring/presentation/widgets/hiring_widgets.dart'
    show formatDay, formatDayTime;
import '../data/service_request_repository.dart';
import '../domain/service_request.dart';
import 'service_request_widgets.dart';

/// One request: its details and progress, documents from the agency, the
/// customer's attachments and the messages, with a reply box while open.
class ServiceRequestScreen extends ConsumerWidget {
  const ServiceRequestScreen({super.key, required this.requestId});

  final String requestId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final details = ref.watch(serviceRequestDetailsProvider(requestId));
    final reference = details.value?.request.reference;

    return PageScaffold(
      title: reference ?? 'Request',
      body: details.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => SingleChildScrollView(
          child: ErrorState(
            failure: AppFailure.from(error),
            onRetry: () =>
                ref.invalidate(serviceRequestDetailsProvider(requestId)),
          ),
        ),
        data: (data) => _Body(details: data),
      ),
    );
  }
}

class _Body extends ConsumerStatefulWidget {
  const _Body({required this.details});

  final ServiceRequestDetails details;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  final _reply = TextEditingController();
  bool _busy = false;

  ServiceRequest get _request => widget.details.request;

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    ref
      ..invalidate(serviceRequestDetailsProvider(_request.id))
      ..invalidate(myServiceRequestsProvider);
    try {
      await ref.read(serviceRequestDetailsProvider(_request.id).future);
    } on Object {
      // Shown in place of the page.
    }
  }

  /// Runs [action], then shows [done] (if any) and reloads the page.
  Future<void> _run(Future<void> Function() action, [String? done]) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      if (done != null) showAppSnackBar(context, done);
      await _reload();
    } on Object catch (error) {
      if (mounted) showErrorSnackBar(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() async {
    final text = _reply.text.trim();
    if (text.isEmpty) return;
    await _run(() async {
      await ref
          .read(serviceRequestRepositoryProvider)
          .sendMessage(_request.id, text);
      _reply.clear();
    });
  }

  Future<void> _addFile() async {
    final file = await ref.read(documentPickerProvider)();
    if (file == null || !mounted) return;
    final problem = file.problem;
    if (problem != null) {
      showAppSnackBar(context, problem, isError: true);
      return;
    }
    await _run(
      () => ref.read(serviceRequestRepositoryProvider).addFile(_request.id, file),
      'File added.',
    );
  }

  Future<void> _open(ServiceRequestFile file) async {
    try {
      final url = await ref.read(serviceRequestRepositoryProvider).fileUrl(file);
      if (!mounted) return;
      await openExternal(
        context,
        ref,
        Uri.parse(url),
        failureMessage: "This file couldn't be opened.",
      );
    } on Object catch (error) {
      if (mounted) showErrorSnackBar(context, error);
    }
  }

  Future<void> _cancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this request?'),
        content: Text(
          'We will stop working on your ${_request.type.label.toLowerCase()} '
          'request. You can send a new one at any time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Cancel request'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(
      () => ref.read(serviceRequestRepositoryProvider).cancel(_request.id),
      'Request cancelled.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final request = _request;
    final fromAgency = widget.details.files.where((f) => f.fromStaff).toList();
    final mine = widget.details.files.where((f) => !f.fromStaff).toList();
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return AppRefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.screenPadding,
          AppSpacing.xs,
          AppSpacing.screenPadding,
          bottomInset + AppSpacing.xl,
        ),
        children: [
          _Summary(request: request),
          const SizedBox(height: AppSpacing.md),
          _Progress(status: request.status),
          if (fromAgency.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            const Text('From the agency', style: AppTypography.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            for (final file in fromAgency)
              RequestFileTile(file: file, onOpen: () => unawaited(_open(file))),
          ],
          const SizedBox(height: AppSpacing.md),
          const Text('Messages', style: AppTypography.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          if (widget.details.messages.isEmpty)
            const Text(
              'No messages yet. Our team will reply here.',
              style: AppTypography.bodySmall,
            )
          else
            for (final message in widget.details.messages)
              _MessageBubble(message: message),
          if (request.status.isOpen) ...[
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _reply,
              minLines: 1,
              maxLines: 4,
              maxLength: 1000,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Write a message',
                suffixIcon: IconButton(
                  tooltip: 'Send message',
                  icon: const Icon(Icons.send_rounded),
                  onPressed: _busy ? null : () => unawaited(_send()),
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          const Text('Your files', style: AppTypography.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          if (mine.isEmpty)
            const Text('No files added.', style: AppTypography.bodySmall)
          else
            for (final file in mine)
              RequestFileTile(file: file, onOpen: () => unawaited(_open(file))),
          if (request.status.isOpen &&
              mine.length < ServiceRequestDraft.maxAttachments)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _busy ? null : () => unawaited(_addFile()),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add a photo or PDF'),
              ),
            ),
          if (request.status.canCancel) ...[
            const SizedBox(height: AppSpacing.lg),
            AppButton(
              label: 'Cancel request',
              variant: AppButtonVariant.outline,
              onPressed: _busy ? null : () => unawaited(_cancel()),
            ),
          ],
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.request});

  final ServiceRequest request;

  @override
  Widget build(BuildContext context) {
    final maid = request.maidName.isNotEmpty
        ? request.maidName
        : request.hiringReference;
    final from = request.travelFrom;
    final to = request.travelTo;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ServiceRequestIcon(type: request.type),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  request.type.label,
                  style: AppTypography.titleMedium,
                ),
              ),
              ServiceRequestStatusBadge(status: request.status),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _Line('Reference', request.reference),
          _Line('Sent', formatDayTime(request.createdAt)),
          if (maid != null) _Line('Maid', maid),
          if (request.travelCountry.isNotEmpty)
            _Line('Travelling to', request.travelCountry),
          if (from != null)
            _Line(
              'Dates',
              to == null
                  ? 'Leaving ${formatDay(from)}'
                  : '${formatDay(from)} – ${formatDay(to)}',
            ),
          if (request.details.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(request.details, style: AppTypography.bodyMedium),
          ],
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(label, style: AppTypography.bodySmall),
          ),
          Expanded(child: Text(value, style: AppTypography.bodyMedium)),
        ],
      ),
    );
  }
}

/// Sent → In progress → Ready → Completed (or the request's end).
class _Progress extends StatelessWidget {
  const _Progress({required this.status});

  final ServiceRequestStatus status;

  @override
  Widget build(BuildContext context) {
    const steps = [
      ServiceRequestStatus.submitted,
      ServiceRequestStatus.inProgress,
      ServiceRequestStatus.ready,
      ServiceRequestStatus.completed,
    ];
    final ended =
        status == ServiceRequestStatus.declined ||
        status == ServiceRequestStatus.cancelled;
    final reached = ended ? 0 : steps.indexOf(status);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Progress', style: AppTypography.titleSmall),
          const SizedBox(height: AppSpacing.xs),
          for (final (index, step) in steps.indexed)
            if (!ended || index == 0)
              _StepRow(label: step.label, done: index <= reached),
          if (ended)
            _StepRow(
              label: status.label,
              done: true,
              color: status == ServiceRequestStatus.declined
                  ? AppColors.error
                  : AppColors.textSecondary,
            ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.label, required this.done, this.color});

  final String label;
  final bool done;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final dot = color ?? (done ? AppColors.success : AppColors.border);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            child: done
                ? const Icon(Icons.check_rounded, size: 10, color: Colors.white)
                : null,
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            label,
            style: AppTypography.bodyMedium.copyWith(
              color: done ? AppColors.textPrimary : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final ServiceRequestMessage message;

  @override
  Widget build(BuildContext context) {
    final staff = message.fromStaff;
    return Align(
      alignment: staff ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.xs),
        padding: const EdgeInsets.all(AppSpacing.sm),
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(
          color: staff ? AppColors.lightBlue : AppColors.veryLightBlue,
          borderRadius: AppRadius.mdAll,
          border: staff ? null : Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              staff ? 'The agency' : 'You',
              style: AppTypography.labelSmall.copyWith(
                color: staff ? AppColors.infoText : AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 2),
            Text(message.body, style: AppTypography.bodyMedium),
            const SizedBox(height: 2),
            Text(
              formatDayTime(message.createdAt),
              style: AppTypography.labelSmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
