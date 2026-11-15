/// How customers reach Golden Legacy Domestic Workers Services.
abstract final class AgencyContact {
  /// Shown to customers.
  static const String phoneDisplay = '+971 4 323 4393';

  /// For the phone dialler (E.164).
  static const String phone = '+97143234393';

  /// WhatsApp Business number (international format, digits only).
  /// The landline must be registered on WhatsApp Business.
  static const String whatsApp = '97143234393';

  static const String email = 'info@gldws.ae';

  static Uri callUri() => Uri(scheme: 'tel', path: phone);

  /// WhatsApp chat with [message] typed in.
  static Uri whatsAppUri(String message) => Uri.parse(
    'https://wa.me/$whatsApp?text=${Uri.encodeComponent(message)}',
  );

  /// New email with [subject] filled in. (Spaces are encoded as %20, which
  /// every mail app understands; "+" would appear literally in some.)
  static Uri emailUri(String subject) => Uri.parse(
    'mailto:$email?subject=${Uri.encodeComponent(subject)}',
  );
}
