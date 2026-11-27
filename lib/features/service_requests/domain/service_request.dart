import 'package:flutter/material.dart';

import '../../documents/domain/customer_document.dart' show PickedDocument;

/// What an employer can ask the agency for, besides hiring a maid
/// (`service_requests.request_type`).
enum ServiceRequestType {
  maidVisa('maid_visa', '2-Year Maid Visa', Icons.badge_rounded),
  replacement('replacement', 'Free replacement', Icons.sync_rounded),
  renewal('renewal', 'Visa or contract renewal', Icons.event_repeat_rounded),
  travelNoc('travel_noc', 'Maid travel NOC', Icons.flight_takeoff_rounded),
  travelLetter('travel_letter', 'Travel letter', Icons.mail_rounded),
  salaryCertificate(
    'salary_certificate',
    'Salary certificate',
    Icons.request_quote_rounded,
  ),
  problem('problem', 'Report a problem', Icons.report_problem_rounded),
  support('support', 'General support', Icons.support_agent_rounded);

  const ServiceRequestType(this.value, this.label, this.icon);

  final String value;
  final String label;
  final IconData icon;

  /// Needs the maid it is for (one of the customer's hires, or a name).
  bool get needsMaid => switch (this) {
    replacement || renewal || travelNoc || travelLetter || salaryCertificate =>
      true,
    _ => false,
  };

  /// Asks for the country and travel dates.
  bool get isTravel => this == travelNoc || this == travelLetter;

  /// The note is required (the customer must say what they need).
  bool get needsDetails => this == problem || this == support;

  /// Label of the note field.
  String get detailsLabel => switch (this) {
    problem => 'What happened?',
    support => 'How can we help?',
    _ => 'Anything we should know?',
  };

  static ServiceRequestType? fromValue(String? value) {
    for (final type in values) {
      if (type.value == value) return type;
    }
    return null;
  }
}

/// `service_requests.status`.
enum ServiceRequestStatus {
  submitted('submitted', 'Sent'),
  inProgress('in_progress', 'In progress'),
  ready('ready', 'Ready'),
  completed('completed', 'Completed'),
  declined('declined', 'Declined'),
  cancelled('cancelled', 'Cancelled');

  const ServiceRequestStatus(this.value, this.label);

  final String value;
  final String label;

  /// The customer can cancel only while it is waiting.
  bool get canCancel => this == submitted;

  /// The customer can still reply and add files.
  bool get isOpen => this == submitted || this == inProgress || this == ready;

  static ServiceRequestStatus fromValue(String? value) {
    for (final status in values) {
      if (status.value == value) return status;
    }
    return submitted;
  }
}

/// A request the customer sent (`public.service_requests`).
class ServiceRequest {
  const ServiceRequest({
    required this.id,
    required this.reference,
    required this.type,
    required this.status,
    required this.createdAt,
    this.hiringRequestId,
    this.hiringReference,
    this.maidName = '',
    this.travelCountry = '',
    this.travelFrom,
    this.travelTo,
    this.details = '',
    this.closedAt,
  });

  factory ServiceRequest.fromJson(Map<String, dynamic> json) {
    final hiring = json['hiring_requests'];
    String? date(String key) => json[key] as String?;
    final from = date('travel_from');
    final to = date('travel_to');
    final closed = date('closed_at');
    return ServiceRequest(
      id: json['id'] as String,
      reference: json['reference'] as String,
      type:
          ServiceRequestType.fromValue(json['request_type'] as String?) ??
          ServiceRequestType.support,
      status: ServiceRequestStatus.fromValue(json['status'] as String?),
      createdAt: DateTime.parse(json['created_at'] as String),
      hiringRequestId: json['hiring_request_id'] as String?,
      hiringReference: hiring is Map<String, dynamic>
          ? hiring['reference'] as String?
          : null,
      maidName: (json['maid_name'] as String?) ?? '',
      travelCountry: (json['travel_country'] as String?) ?? '',
      travelFrom: from == null ? null : DateTime.tryParse(from),
      travelTo: to == null ? null : DateTime.tryParse(to),
      details: (json['details'] as String?) ?? '',
      closedAt: closed == null ? null : DateTime.tryParse(closed),
    );
  }

  static const String columns =
      'id, reference, request_type, status, created_at, hiring_request_id, '
      'maid_name, travel_country, travel_from, travel_to, details, closed_at, '
      'hiring_requests(reference)';

  final String id;

  /// e.g. `SR-2026-000001`.
  final String reference;
  final ServiceRequestType type;
  final ServiceRequestStatus status;
  final DateTime createdAt;
  final String? hiringRequestId;

  /// The hiring request's reference (HR-…), when the request names one.
  final String? hiringReference;
  final String maidName;
  final String travelCountry;
  final DateTime? travelFrom;
  final DateTime? travelTo;
  final String details;
  final DateTime? closedAt;
}

/// A message on a request, from the customer or the agency.
class ServiceRequestMessage {
  const ServiceRequestMessage({
    required this.id,
    required this.body,
    required this.fromStaff,
    required this.createdAt,
  });

  factory ServiceRequestMessage.fromJson(Map<String, dynamic> json) =>
      ServiceRequestMessage(
        id: (json['id'] as num).toInt(),
        body: json['body'] as String,
        fromStaff: json['from_staff'] as bool? ?? false,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  static const String columns = 'id, body, from_staff, created_at';

  final int id;
  final String body;
  final bool fromStaff;
  final DateTime createdAt;
}

/// A file on a request: the customer's attachment, or a document from the
/// agency (NOC, letter, certificate). In the private bucket.
class ServiceRequestFile {
  const ServiceRequestFile({
    required this.id,
    required this.storagePath,
    required this.fileName,
    required this.sizeBytes,
    required this.fromStaff,
    required this.createdAt,
    this.title = '',
  });

  factory ServiceRequestFile.fromJson(Map<String, dynamic> json) =>
      ServiceRequestFile(
        id: json['id'] as String,
        storagePath: json['storage_path'] as String,
        fileName: json['file_name'] as String,
        sizeBytes: (json['size_bytes'] as num).toInt(),
        fromStaff: json['from_staff'] as bool? ?? false,
        createdAt: DateTime.parse(json['created_at'] as String),
        title: (json['title'] as String?) ?? '',
      );

  static const String columns =
      'id, storage_path, file_name, size_bytes, from_staff, created_at, title';

  final String id;
  final String storagePath;
  final String fileName;
  final int sizeBytes;
  final bool fromStaff;
  final DateTime createdAt;
  final String title;

  String get displayName => title.isEmpty ? fileName : title;
}

/// What the customer fills in for a new request.
class ServiceRequestDraft {
  const ServiceRequestDraft({
    required this.type,
    this.hiringRequestId,
    this.maidName = '',
    this.travelCountry = '',
    this.travelFrom,
    this.travelTo,
    this.details = '',
    this.attachments = const [],
  });

  final ServiceRequestType type;
  final String? hiringRequestId;
  final String maidName;
  final String travelCountry;
  final DateTime? travelFrom;
  final DateTime? travelTo;
  final String details;
  final List<PickedDocument> attachments;

  /// Most attachments a customer can add to one request.
  static const int maxAttachments = 10;

  /// Why the draft cannot be sent yet, by field; empty when it can.
  Map<String, String> validate() {
    final errors = <String, String>{};
    if (type.needsMaid &&
        hiringRequestId == null &&
        maidName.trim().isEmpty) {
      errors['maid'] = 'Choose the maid this request is for.';
    }
    if (type.isTravel) {
      if (travelCountry.trim().isEmpty) {
        errors['country'] = 'Enter the country she is travelling to.';
      }
      final from = travelFrom;
      final to = travelTo;
      if (from == null) {
        errors['from'] = 'Choose the date she leaves.';
      } else if (to != null && to.isBefore(from)) {
        errors['to'] = 'The return date is before the date she leaves.';
      }
    }
    if (type.needsDetails && details.trim().isEmpty) {
      errors['details'] = 'Tell us what you need help with.';
    }
    if (details.trim().length > 2000) {
      errors['details'] = 'Please keep it under 2,000 characters.';
    }
    if (maidName.trim().length > 120) {
      errors['maid'] = 'Please keep the name under 120 characters.';
    }
    if (travelCountry.trim().length > 80) {
      errors['country'] = 'Please keep the country under 80 characters.';
    }
    if (attachments.length > maxAttachments) {
      errors['files'] = 'You can add up to $maxAttachments files.';
    }
    return errors;
  }

  String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> toInsertJson() {
    final from = travelFrom;
    final to = travelTo;
    return {
      'request_type': type.value,
      'hiring_request_id': hiringRequestId,
      'maid_name': hiringRequestId == null ? maidName.trim() : '',
      'travel_country': type.isTravel ? travelCountry.trim() : '',
      'travel_from': type.isTravel && from != null ? _day(from) : null,
      'travel_to': type.isTravel && to != null ? _day(to) : null,
      'details': details.trim(),
    };
  }
}

/// A request with its messages and files, for the request page.
class ServiceRequestDetails {
  const ServiceRequestDetails({
    required this.request,
    this.messages = const [],
    this.files = const [],
  });

  final ServiceRequest request;
  final List<ServiceRequestMessage> messages;
  final List<ServiceRequestFile> files;
}
