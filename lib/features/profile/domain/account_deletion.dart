/// A customer's request to delete their account
/// (`public.account_deletion_requests`).
class AccountDeletionRequest {
  const AccountDeletionRequest({
    required this.id,
    required this.createdAt,
    this.reason = '',
  });

  factory AccountDeletionRequest.fromJson(Map<String, dynamic> json) {
    return AccountDeletionRequest(
      id: json['id'] as String,
      reason: json['reason'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  static const String columns = 'id, reason, created_at';

  /// Longest reason the database accepts.
  static const int maxReasonLength = 500;

  final String id;
  final String reason;
  final DateTime createdAt;
}
