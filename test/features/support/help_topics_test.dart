import 'package:flutter_test/flutter_test.dart';
import 'package:golden_maids/features/support/domain/help_topics.dart';
import 'package:golden_maids/features/support/domain/legal_texts.dart';

String _answer(List<HelpSection> sections, String question) => sections
    .expand((section) => section.topics)
    .firstWhere((topic) => topic.question == question)
    .answer;

void main() {
  test('help covers hiring, without home-service bookings', () {
    final sections = helpSections();
    expect(sections.map((s) => s.title), ['Hiring a maid', 'Your account']);
    expect(
      _answer(sections, 'How do I hire a maid?'),
      contains('Requests tab'),
    );
  });

  test('policies are marked as drafts until approved', () {
    expect(LegalTexts.isDraft, isTrue);
    expect(LegalTexts.privacy.sections, isNotEmpty);
    expect(LegalTexts.terms.sections.last.heading, 'Contact us');
  });
}
