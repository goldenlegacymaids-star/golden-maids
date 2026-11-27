import 'package:golden_maids/core/errors/app_failure.dart';
import 'package:golden_maids/features/documents/domain/customer_document.dart';
import 'package:golden_maids/features/service_requests/data/service_request_repository.dart';
import 'package:golden_maids/features/service_requests/domain/service_request.dart';

/// In-memory [ServiceRequestRepository] following the database's rules.
class FakeServiceRequestRepository implements ServiceRequestRepository {
  FakeServiceRequestRepository({List<ServiceRequestDetails>? requests})
    : requests = [...?requests];

  final List<ServiceRequestDetails> requests;

  /// Drafts sent, in order.
  final List<ServiceRequestDraft> submitted = [];

  /// When set, every call fails with this error.
  AppFailure? failure;

  void _check() {
    final error = failure;
    if (error != null) throw error;
  }

  /// A request already sent.
  static ServiceRequestDetails sample({
    String id = 's1',
    String reference = 'SR-2026-000001',
    ServiceRequestType type = ServiceRequestType.travelNoc,
    ServiceRequestStatus status = ServiceRequestStatus.submitted,
    List<ServiceRequestMessage> messages = const [],
    List<ServiceRequestFile> files = const [],
  }) => ServiceRequestDetails(
    request: ServiceRequest(
      id: id,
      reference: reference,
      type: type,
      status: status,
      createdAt: DateTime(2026, 11, 27, 16, 30),
      maidName: 'Wanjiru Kamau',
      travelCountry: type.isTravel ? 'Kenya' : '',
      travelFrom: type.isTravel ? DateTime(2026, 12, 20) : null,
      travelTo: type.isTravel ? DateTime(2027, 1, 5) : null,
      details: 'Annual leave',
    ),
    messages: messages,
    files: files,
  );

  ServiceRequestDetails _find(String id) =>
      requests.firstWhere((r) => r.request.id == id,
          orElse: () => throw const NotFoundFailure());

  void _replace(String id, ServiceRequestDetails Function(ServiceRequestDetails) f) {
    final index = requests.indexWhere((r) => r.request.id == id);
    requests[index] = f(requests[index]);
  }

  @override
  Future<String> submit(ServiceRequestDraft draft) async {
    _check();
    final errors = draft.validate();
    if (errors.isNotEmpty) throw ValidationFailure(message: errors.values.first);
    submitted.add(draft);
    final number = requests.length + 1;
    final id = 'new-$number';
    requests.insert(
      0,
      ServiceRequestDetails(
        request: ServiceRequest(
          id: id,
          reference: 'SR-2026-${number.toString().padLeft(6, '0')}',
          type: draft.type,
          status: ServiceRequestStatus.submitted,
          createdAt: DateTime(2026, 11, 27, 17),
          hiringRequestId: draft.hiringRequestId,
          maidName: draft.maidName.trim(),
          travelCountry: draft.travelCountry.trim(),
          travelFrom: draft.travelFrom,
          travelTo: draft.travelTo,
          details: draft.details.trim(),
        ),
        files: [
          for (final (i, file) in draft.attachments.indexed)
            ServiceRequestFile(
              id: '$id-file-$i',
              storagePath: '$id/$i.pdf',
              fileName: file.name,
              sizeBytes: file.bytes.length,
              fromStaff: false,
              createdAt: DateTime(2026, 11, 27, 17),
            ),
        ],
      ),
    );
    return id;
  }

  @override
  Future<List<ServiceRequest>> getMine() async {
    _check();
    return [for (final r in requests) r.request];
  }

  @override
  Future<ServiceRequestDetails> getDetails(String id) async {
    _check();
    return _find(id);
  }

  @override
  Future<void> cancel(String id) async {
    _check();
    final current = _find(id).request;
    if (!current.status.canCancel) {
      throw const ValidationFailure(
        message: 'Only a request that is still waiting can be cancelled.',
      );
    }
    _replace(
      id,
      (r) => ServiceRequestDetails(
        request: ServiceRequest(
          id: current.id,
          reference: current.reference,
          type: current.type,
          status: ServiceRequestStatus.cancelled,
          createdAt: current.createdAt,
          maidName: current.maidName,
          details: current.details,
        ),
        messages: r.messages,
        files: r.files,
      ),
    );
  }

  @override
  Future<void> sendMessage(String requestId, String body) async {
    _check();
    _replace(
      requestId,
      (r) => ServiceRequestDetails(
        request: r.request,
        messages: [
          ...r.messages,
          ServiceRequestMessage(
            id: r.messages.length + 1,
            body: body.trim(),
            fromStaff: false,
            createdAt: DateTime(2026, 11, 27, 18),
          ),
        ],
        files: r.files,
      ),
    );
  }

  @override
  Future<void> addFile(String requestId, PickedDocument file) async {
    _check();
    final problem = file.problem;
    if (problem != null) throw ValidationFailure(message: problem);
    _replace(
      requestId,
      (r) => ServiceRequestDetails(
        request: r.request,
        messages: r.messages,
        files: [
          ...r.files,
          ServiceRequestFile(
            id: '$requestId-file-${r.files.length}',
            storagePath: '$requestId/${r.files.length}.pdf',
            fileName: file.name,
            sizeBytes: file.bytes.length,
            fromStaff: false,
            createdAt: DateTime(2026, 11, 27, 18),
          ),
        ],
      ),
    );
  }

  @override
  Future<String> fileUrl(ServiceRequestFile file) async {
    _check();
    return 'https://files.example.com/${file.storagePath}?token=short';
  }
}
