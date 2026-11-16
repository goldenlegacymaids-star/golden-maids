import 'package:intl/intl.dart';

/// What a notification is about (from the `kind` prefix).
enum NotificationTopic { booking, hiring, enquiry, document, other }

/// An update from the agency (`public.customer_notifications`), written by
/// the database when staff change a booking, hiring request or enquiry.
class CustomerNotification {
  const CustomerNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.createdAt,
    this.bookingId,
    this.hiringRequestId,
    this.candidateId,
    this.readAt,
  });

  factory CustomerNotification.fromJson(Map<String, dynamic> json) =>
      CustomerNotification(
        id: (json['id'] as num).toInt(),
        kind: json['kind'] as String,
        title: json['title'] as String,
        body: (json['body'] as String?) ?? '',
        createdAt: DateTime.parse(json['created_at'] as String),
        bookingId: json['booking_id'] as String?,
        hiringRequestId: json['hiring_request_id'] as String?,
        candidateId: json['candidate_id'] as String?,
        readAt: json['read_at'] == null
            ? null
            : DateTime.parse(json['read_at'] as String),
      );

  final int id;

  /// e.g. `booking.confirmed`, `hiring.shortlisted`, `enquiry.closed`.
  final String kind;
  final String title;
  final String body;
  final DateTime createdAt;
  final String? bookingId;
  final String? hiringRequestId;
  final String? candidateId;
  final DateTime? readAt;

  bool get isUnread => readAt == null;

  NotificationTopic get topic => switch (kind.split('.').first) {
    'booking' => NotificationTopic.booking,
    'hiring' => NotificationTopic.hiring,
    'enquiry' => NotificationTopic.enquiry,
    'document' => NotificationTopic.document,
    _ => NotificationTopic.other,
  };

  CustomerNotification markedRead(DateTime at) => CustomerNotification(
    id: id,
    kind: kind,
    title: title,
    body: body,
    createdAt: createdAt,
    bookingId: bookingId,
    hiringRequestId: hiringRequestId,
    candidateId: candidateId,
    readAt: readAt ?? at,
  );
}

final _sameYear = DateFormat('d MMM');
final _otherYear = DateFormat('d MMM yyyy');

/// "Just now", "5 min ago", "3 h ago", "Yesterday", "12 Nov", "12 Nov 2025".
String notificationTime(DateTime at, {DateTime? now}) {
  final local = at.toLocal();
  final current = (now ?? DateTime.now()).toLocal();
  final difference = current.difference(local);
  if (difference.inMinutes < 1) return 'Just now';
  if (difference.inMinutes < 60) return '${difference.inMinutes} min ago';
  final today = DateTime(current.year, current.month, current.day);
  final day = DateTime(local.year, local.month, local.day);
  if (day == today) return '${difference.inHours} h ago';
  if (today.difference(day).inDays == 1) return 'Yesterday';
  return local.year == current.year
      ? _sameYear.format(local)
      : _otherYear.format(local);
}
