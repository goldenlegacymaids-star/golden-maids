import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../documents/data/document_repository.dart';
import '../../documents/domain/customer_document.dart'
    show PickedDocument, fileSizeLabel;
import '../../hiring/data/hiring_repository.dart';
import '../../hiring/domain/hiring_request.dart';
import '../../hiring/presentation/widgets/hiring_widgets.dart' show formatDay;
import '../data/service_request_repository.dart';
import '../domain/service_request.dart';
import 'service_request_widgets.dart';

/// A new request of [type]: the maid, travel details, a note and files.
class NewServiceRequestScreen extends ConsumerStatefulWidget {
  const NewServiceRequestScreen({super.key, required this.type});

  final ServiceRequestType type;

  /// The "another maid" choice in the maid list.
  static const String otherMaid = 'other';

  @override
  ConsumerState<NewServiceRequestScreen> createState() =>
      _NewServiceRequestScreenState();
}

class _NewServiceRequestScreenState
    extends ConsumerState<NewServiceRequestScreen> {
  final _maidName = TextEditingController();
  final _country = TextEditingController();
  final _details = TextEditingController();
  String? _maidChoice;
  DateTime? _from;
  DateTime? _to;
  final List<PickedDocument> _files = [];
  Map<String, String> _errors = const {};
  bool _sending = false;

  ServiceRequestType get _type => widget.type;

  @override
  void dispose() {
    _maidName.dispose();
    _country.dispose();
    _details.dispose();
    super.dispose();
  }

  ServiceRequestDraft _draft() {
    final choice = _maidChoice;
    final hiringId = choice == null || choice == NewServiceRequestScreen.otherMaid
        ? null
        : choice;
    return ServiceRequestDraft(
      type: _type,
      hiringRequestId: hiringId,
      maidName: hiringId == null ? _maidName.text : '',
      travelCountry: _country.text,
      travelFrom: _from,
      travelTo: _to,
      details: _details.text,
      attachments: List.of(_files),
    );
  }

  Future<void> _pickDate({required bool leaving}) async {
    final today = DateUtils.dateOnly(DateTime.now());
    final first = leaving ? today : (_from ?? today);
    final current = leaving ? _from : _to;
    final picked = await showDatePicker(
      context: context,
      initialDate: current != null && !current.isBefore(first) ? current : first,
      firstDate: first,
      lastDate: today.add(const Duration(days: 730)),
      helpText: leaving ? 'Date she leaves' : 'Date she comes back',
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (leaving) {
        _from = picked;
        final to = _to;
        if (to != null && to.isBefore(picked)) _to = null;
      } else {
        _to = picked;
      }
    });
  }

  Future<void> _addFile() async {
    if (_files.length >= ServiceRequestDraft.maxAttachments) {
      showAppSnackBar(
        context,
        'You can add up to ${ServiceRequestDraft.maxAttachments} files.',
        isError: true,
      );
      return;
    }
    final file = await ref.read(documentPickerProvider)();
    if (file == null || !mounted) return;
    final problem = file.problem;
    if (problem != null) {
      showAppSnackBar(context, problem, isError: true);
      return;
    }
    setState(() => _files.add(file));
  }

  Future<void> _send() async {
    final draft = _draft();
    final errors = draft.validate();
    setState(() => _errors = errors);
    if (errors.isNotEmpty) return;

    setState(() => _sending = true);
    try {
      final id = await ref.read(serviceRequestRepositoryProvider).submit(draft);
      ref.invalidate(myServiceRequestsProvider);
      if (!mounted) return;
      showAppSnackBar(context, '${_type.label} request sent.');
      context.go(AppRoutes.serviceRequest(id));
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _sending = false);
      showAppSnackBar(context, AppFailure.from(error).message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hires = ref.watch(myHiringRequestsProvider).value ?? const [];
    final showMaid = _type != ServiceRequestType.support;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return PageScaffold(
      title: _type.label,
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.screenPadding,
          AppSpacing.xs,
          AppSpacing.screenPadding,
          bottomInset + AppSpacing.xl,
        ),
        children: [
          Row(
            children: [
              ServiceRequestIcon(type: _type, size: 44),
              const SizedBox(width: AppSpacing.sm),
              const Expanded(
                child: Text(
                  'Our team replies here and adds any document to this '
                  'request. You will get a notification at each step.',
                  style: AppTypography.bodySmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          if (showMaid) ...[
            _Label(
              _type.needsMaid ? 'Which maid?' : 'Which maid? (optional)',
            ),
            _MaidChoice(
              hires: hires,
              value: _maidChoice,
              onChanged: (value) => setState(() => _maidChoice = value),
              error: hires.isEmpty ? null : _errors['maid'],
            ),
            if (hires.isEmpty ||
                _maidChoice == NewServiceRequestScreen.otherMaid) ...[
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _maidName,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: "Maid's name",
                  errorText: _errors['maid'],
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
          ],
          if (_type.isTravel) ...[
            const _Label('Travelling to'),
            TextField(
              controller: _country,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Country',
                errorText: _errors['country'],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: _DateField(
                    label: 'Leaving',
                    value: _from,
                    error: _errors['from'],
                    onTap: () => unawaited(_pickDate(leaving: true)),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _DateField(
                    label: 'Back (optional)',
                    value: _to,
                    error: _errors['to'],
                    onTap: () => unawaited(_pickDate(leaving: false)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          _Label(
            _type.needsDetails
                ? _type.detailsLabel
                : '${_type.detailsLabel} (optional)',
          ),
          TextField(
            controller: _details,
            minLines: 3,
            maxLines: 6,
            maxLength: 2000,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'Write here',
              errorText: _errors['details'],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          const _Label('Attach files (optional)'),
          for (final (index, file) in _files.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: AppCard(
                bordered: true,
                shadow: false,
                padding: const EdgeInsets.only(left: AppSpacing.sm),
                child: Row(
                  children: [
                    const Icon(
                      Icons.attach_file_rounded,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        '${file.name} · ${fileSizeLabel(file.bytes.length)}',
                        style: AppTypography.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove ${file.name}',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => setState(() => _files.removeAt(index)),
                    ),
                  ],
                ),
              ),
            ),
          OutlinedButton.icon(
            onPressed: _sending ? null : () => unawaited(_addFile()),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add a photo or PDF'),
          ),
          if (_errors['files'] case final error?)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xxs),
              child: Text(
                error,
                style: AppTypography.bodySmall.copyWith(color: AppColors.error),
              ),
            ),
          const SizedBox(height: AppSpacing.lg),
          AppButton(
            label: 'Send request',
            icon: Icons.send_rounded,
            isLoading: _sending,
            onPressed: _sending ? null : () => unawaited(_send()),
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Text(text, style: AppTypography.titleSmall),
    );
  }
}

/// The customer's hires as choices, and "Another maid".
class _MaidChoice extends StatelessWidget {
  const _MaidChoice({
    required this.hires,
    required this.value,
    required this.onChanged,
    this.error,
  });

  final List<HiringRequest> hires;
  final String? value;
  final ValueChanged<String?> onChanged;
  final String? error;

  @override
  Widget build(BuildContext context) {
    if (hires.isEmpty) return const SizedBox.shrink();
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Choose',
        errorText: error,
      ),
      items: [
        for (final hire in hires)
          DropdownMenuItem(
            value: hire.id,
            child: Text(
              '${hire.maidLabel} · ${hire.reference}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        const DropdownMenuItem(
          value: NewServiceRequestScreen.otherMaid,
          child: Text('Another maid (type her name)'),
        ),
      ],
      onChanged: onChanged,
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
    this.error,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onTap;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final date = value;
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          errorText: error,
          errorMaxLines: 2,
          suffixIcon: const Icon(Icons.calendar_today_rounded, size: 18),
        ),
        child: Text(
          date == null ? 'Choose' : formatDay(date),
          style: AppTypography.bodyMedium.copyWith(
            color: date == null ? AppColors.textSecondary : null,
          ),
        ),
      ),
    );
  }
}
