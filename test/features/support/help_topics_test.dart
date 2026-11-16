import 'package:flutter_test/flutter_test.dart';
import 'package:golden_maids/features/bookings/domain/booking.dart';
import 'package:golden_maids/features/support/domain/help_topics.dart';
import 'package:golden_maids/features/support/domain/legal_texts.dart';

String _answer(List<HelpSection> sections, String question) => sections
    .expand((section) => section.topics)
    .firstWhere((topic) => topic.question == question)
    .answer;

void main() {
  test('clock labels', () {
    expect(clockLabel(0), '12 am');
    expect(clockLabel(8 * 60), '8 am');
    expect(clockLabel(12 * 60), '12 pm');
    expect(clockLabel(20 * 60 + 30), '8:30 pm');
  });

  test('booking answers follow the live settings', () {
    const settings = BookingSettings(
      openMinutes: 9 * 60,
      closeMinutes: 18 * 60,
      openDays: [1, 2, 3, 4, 5, 6],
      cancelHours: 12,
      minHours: 3,
    );
    final sections = helpSections(settings);
    final when = _answer(sections, 'When can I book?');
    expect(when, contains('9 am to 6 pm (UAE time)'));
    expect(when, isNot(contains('every day')));
    expect(when, contains('3 to 8 hours'));
    expect(
      _answer(sections, 'Can I cancel or reschedule?'),
      contains('until 12 hours before'),
    );
  });

  test('policies are marked as drafts until approved', () {
    expect(LegalTexts.isDraft, isTrue);
    expect(LegalTexts.privacy.sections, isNotEmpty);
    expect(LegalTexts.terms.sections.last.heading, 'Contact us');
  });
}
