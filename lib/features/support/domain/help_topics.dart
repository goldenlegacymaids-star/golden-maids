import '../../bookings/domain/booking.dart';

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

/// `8 am`, `8:30 pm`
String clockLabel(int minutesAfterMidnight) {
  final hour = minutesAfterMidnight ~/ 60;
  final minute = minutesAfterMidnight % 60;
  final suffix = hour < 12 || hour == 24 ? 'am' : 'pm';
  final hour12 = hour % 12 == 0 ? 12 : hour % 12;
  return minute == 0
      ? '$hour12 $suffix'
      : '$hour12:${minute.toString().padLeft(2, '0')} $suffix';
}

/// The Help Centre content. Booking rules come from the live booking
/// settings, so the answers stay correct if the agency changes them.
List<HelpSection> helpSections(BookingSettings settings) {
  final allWeek = settings.openDays.length == 7;
  final hours =
      '${clockLabel(settings.openMinutes)} to '
      '${clockLabel(settings.closeMinutes)}'
      '${allWeek ? ', every day' : ''}';
  final cancel = settings.cancelHours;

  return [
    HelpSection('Home-service bookings', [
      const HelpTopic(
        'How do I book a home service?',
        'Choose a service on the Home screen and tap Book now. Pick the '
            'number of hours (for hourly services), a day and a free time, '
            'then your address. Our team confirms your booking and assigns a '
            'professional. You can follow every step in Bookings.',
      ),
      HelpTopic(
        'When can I book?',
        'Bookings run from $hours (UAE time), up to ${settings.windowDays} '
            'days ahead and at least ${settings.minNoticeHours} hours from '
            'now. Hourly services can be booked for ${settings.minHours} to '
            '${settings.maxHours} hours.',
      ),
      const HelpTopic(
        'How do I pay?',
        'You pay when the job is done, by cash or card. Nothing is charged '
            'in the app.',
      ),
      const HelpTopic(
        'How is the price worked out?',
        'The price shown before you confirm is an estimate: the hourly rate '
            'times the hours, or the listed price of the visit. For some '
            'services our team confirms the price with you.',
      ),
      HelpTopic(
        'Can I cancel or reschedule?',
        'Yes, free of charge until $cancel hours before the start: open the '
            'booking in Bookings and tap Reschedule or Cancel booking. Within '
            '$cancel hours of the start, please call us.',
      ),
      const HelpTopic(
        'Who will come to my home?',
        "One of the agency's own professionals. Once our team assigns them, "
            'you will see their name in the booking.',
      ),
    ]),
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
            'check the details and send. Follow its progress in Profile, My '
            'Hiring Requests.',
      ),
      HelpTopic(
        'Can I ask about a maid first?',
        "Yes. On the maid's profile, tap Request Info, or call or WhatsApp "
            'us.',
      ),
      HelpTopic(
        'Can I cancel a hiring request?',
        'Yes, from My Hiring Requests until our team starts shortlisting. '
            'After that, please contact us.',
      ),
    ]),
    const HelpSection('Your account', [
      HelpTopic(
        'How do I change my details?',
        'In Profile, tap the pencil next to your name to edit your details, '
            'and use Saved Addresses to add, change or remove addresses.',
      ),
      HelpTopic(
        'How do I delete my account?',
        'In Profile, tap Delete my account at the bottom. Our team then '
            'deletes your sign-in and personal details. Records we must keep, '
            'such as past bookings and hiring requests, are kept without your '
            'name and contact details.',
      ),
    ]),
  ];
}
