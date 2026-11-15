import 'package:golden_maids/core/errors/app_failure.dart';
import 'package:golden_maids/features/hiring/data/hiring_repository.dart';
import 'package:golden_maids/features/hiring/domain/hiring_request.dart';

import 'fake_candidate_repository.dart';

/// In-memory [HiringRepository] following the database's rules.
class FakeHiringRepository implements HiringRepository {
  FakeHiringRepository({List<HiringRequest>? requests})
    : requests = [...?requests];

  final List<HiringRequest> requests;
  final Map<String, List<HiringStatusEvent>> history = {};

  /// Drafts submitted, in order.
  final List<HiringDraft> submitted = [];

  /// When set, every call fails with this error.
  AppFailure? failure;

  void _check() {
    final error = failure;
    if (error != null) throw error;
  }

  /// A request already sent, e.g. for the My Hiring Requests list.
  static HiringRequest sample({
    required String id,
    required String reference,
    HiringStatus status = HiringStatus.submitted,
    String? candidateId = 'k1',
  }) {
    final candidate = FakeCandidateRepository.defaultCandidates
        .where((c) => c.id == candidateId)
        .firstOrNull;
    return HiringRequest(
      id: id,
      reference: reference,
      packageId: 'pkg-monthly',
      packageName: 'Full-Time Live-In Maid – Monthly',
      durationMonths: 3,
      status: status,
      createdAt: DateTime(2026, 11, 10, 9, 30),
      customerName: 'Sarah Khan',
      customerPhone: '+971501234567',
      emirate: 'Dubai',
      candidateId: candidateId,
      candidate: candidate,
      hasChildren: true,
    );
  }

  @override
  Future<String> submit(HiringDraft draft) async {
    _check();
    submitted.add(draft);
    final number = submitted.length;
    final id = 'new-$number';
    final reference = 'HR-2026-${number.toString().padLeft(6, '0')}';
    final package = FakeCandidateRepository.defaultPackages.firstWhere(
      (p) => p.id == draft.packageId,
    );
    final candidate = FakeCandidateRepository.defaultCandidates
        .where((c) => c.id == draft.candidateId)
        .firstOrNull;
    requests.insert(
      0,
      HiringRequest(
        id: id,
        reference: reference,
        packageId: draft.packageId,
        packageName: package.name,
        durationMonths: draft.durationMonths,
        sponsorNationality: draft.sponsorNationality,
        candidateId: draft.candidateId,
        candidate: candidate,
        status: HiringStatus.submitted,
        createdAt: DateTime(2026, 11, 16, 10),
        customerName: draft.name,
        customerPhone: draft.phone,
        customerEmail: draft.email,
        emirate: draft.emirate,
        householdSize: draft.householdSize,
        hasChildren: draft.hasChildren,
        hasElderly: draft.hasElderly,
        hasPets: draft.hasPets,
        preferredStartDate: draft.preferredStartDate,
        requirements: draft.requirements,
        contactMethod: draft.contactMethod,
      ),
    );
    history[id] = [
      HiringStatusEvent(
        status: HiringStatus.submitted,
        createdAt: DateTime(2026, 11, 16, 10),
      ),
    ];
    return reference;
  }

  @override
  Future<List<HiringRequest>> getMyRequests() async {
    _check();
    return [...requests];
  }

  @override
  Future<HiringRequest> getRequest(String id) async {
    _check();
    return requests.firstWhere(
      (r) => r.id == id,
      orElse: () => throw const NotFoundFailure(),
    );
  }

  @override
  Future<List<HiringStatusEvent>> getHistory(String requestId) async {
    _check();
    return history[requestId] ?? const [];
  }

  @override
  Future<void> cancel(String requestId) async {
    _check();
    final index = requests.indexWhere((r) => r.id == requestId);
    if (index < 0) throw const NotFoundFailure();
    if (!requests[index].status.canCancel) {
      throw const PermissionFailure(
        message:
            'You can only cancel a request that has not been processed yet.',
      );
    }
    requests[index] = requests[index].withStatus(HiringStatus.cancelled);
    history[requestId] = [
      ...?history[requestId],
      HiringStatusEvent(
        status: HiringStatus.cancelled,
        createdAt: DateTime(2026, 11, 16, 12),
      ),
    ];
  }
}
