/// A question and answer in the Help Centre.
class HelpTopic {
  const HelpTopic(this.question, this.answer);

  final String question;
  final String answer;
}

/// Help Centre questions by section.
class HelpSection {
  const HelpSection(this.title, this.topics);

  final String title;
  final List<HelpTopic> topics;
}

/// The Help Centre content.
List<HelpSection> helpSections() {
  return [
    const HelpSection('Hiring a maid', [
      HelpTopic(
        'Which hiring packages do you offer?',
        'Full-Time Live-In Maid, Monthly (1 to 11 months) or Yearly (12 '
            "or 24 months), on the agency's visa; and the 2-Year Contract on "
            'a GCC Sponsor Visa, where you, as a GCC national, sponsor the '
            "maid's visa.",
      ),
      HelpTopic(
        'How do I hire a maid?',
        'Open Find a Maid, choose a maid and tap Hire on their profile, or '
            'tap Hire a Maid and let us recommend one. Choose your package, '
            'check the details and send. Follow its progress in the Requests '
            'tab.',
      ),
      HelpTopic(
        'Can I ask about a maid first?',
        "Yes. On the maid's profile, tap Request Info, or call or WhatsApp "
            'us.',
      ),
      HelpTopic(
        'Can I cancel a hiring request?',
        'Yes, from the Requests tab until our team starts shortlisting. '
            'After that, please contact us.',
      ),
    ]),
    const HelpSection('Your account', [
      HelpTopic(
        'How do I change my details?',
        'In Profile, tap the pencil next to your name to edit your '
            'details.',
      ),
      HelpTopic(
        'How do I delete my account?',
        'In Profile, tap Delete my account at the bottom. Our team then '
            'deletes your sign-in and personal details. Records we must keep, '
            'such as past hiring requests, are kept without your '
            'name and contact details.',
      ),
    ]),
  ];
}
