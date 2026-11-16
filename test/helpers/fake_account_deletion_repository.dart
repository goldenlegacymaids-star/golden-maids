import 'package:golden_maids/core/errors/app_failure.dart';
import 'package:golden_maids/features/profile/data/account_deletion_repository.dart';
import 'package:golden_maids/features/profile/domain/account_deletion.dart';

/// In-memory [AccountDeletionRepository].
class FakeAccountDeletionRepository implements AccountDeletionRepository {
  FakeAccountDeletionRepository({this.pending});

  /// The customer's pending request, if any.
  AccountDeletionRequest? pending;

  /// Reasons of the requests made, in order.
  final List<String> requests = [];

  /// Ids of withdrawn requests.
  final List<String> withdrawn = [];

  @override
  Future<AccountDeletionRequest?> getPendingRequest() async => pending;

  @override
  Future<void> requestDeletion({String reason = ''}) async {
    if (pending != null) {
      throw const ValidationFailure(
        message: 'You have already asked us to delete your account.',
      );
    }
    requests.add(reason);
    pending = AccountDeletionRequest(
      id: 'del-${requests.length}',
      reason: reason,
      createdAt: DateTime.now(),
    );
  }

  @override
  Future<void> withdraw(String requestId) async {
    if (pending?.id != requestId) throw const NotFoundFailure();
    withdrawn.add(requestId);
    pending = null;
  }
}
