import '../../../core/constants/agency_contact.dart';
import '../../../core/constants/app_constants.dart';

/// A heading and its paragraphs.
class LegalSection {
  const LegalSection(this.heading, this.paragraphs);

  final String heading;
  final List<String> paragraphs;
}

/// A policy shown in the app.
class LegalDocument {
  const LegalDocument({
    required this.title,
    required this.updated,
    required this.sections,
  });

  final String title;

  /// e.g. "16 November 2026"
  final String updated;
  final List<LegalSection> sections;
}

/// The Privacy Policy and Terms and Conditions.
///
/// DRAFT: basic texts written from what the app does, for the client to
/// review (with legal advice) before release. Set [isDraft] to false once
/// the client has approved the final wording.
abstract final class LegalTexts {
  static const bool isDraft = true;

  static const String _company = AppConstants.companyName;
  static const String _contact =
      'Email ${AgencyContact.email} or call ${AgencyContact.phoneDisplay}.';

  static const LegalDocument privacy = LegalDocument(
    title: 'Privacy Policy',
    updated: '27 November 2026',
    sections: [
      LegalSection('Who we are', [
        '$_company ("Golden Maids", "we") provides domestic-worker '
            'recruitment in the United Arab Emirates and '
            'runs this app. This policy explains what personal data we '
            'collect through the app, why, and your choices.',
      ]),
      LegalSection('What we collect', [
        'Account details: your name, email address and phone number, and '
            'how you sign in.',
        'Hiring requests and questions about maids: the package and maid '
            'you choose, your contact details and messages, and, for the GCC '
            'sponsor package, your nationality.',
        'Maids you save, and the requests to delete your account.',
        'We do not take card details in the app.',
      ]),
      LegalSection('How we use it', [
        'To create and secure your account, handle your hiring requests, '
            'contact you about your requests, '
            'answer your questions, keep records we are required to keep, '
            'and improve our services.',
      ]),
      LegalSection('Who sees it', [
        'Our staff who handle your requests.',
        'Service providers who host our systems or send sign-in codes and '
            'emails for us, under agreements to protect your data.',
        'Government authorities when the law requires it, for example for '
            'visa and labour procedures.',
        'We do not sell your personal data.',
      ]),
      LegalSection('Maid profiles', [
        'Profiles of domestic workers are published with their consent and '
            'show only the details needed to choose a maid. Their identity '
            'documents are kept private.',
      ]),
      LegalSection('How long we keep it', [
        'We keep your data while your account is open. When you delete your '
            'account, we delete your sign-in and personal details and keep '
            'only the records we must keep by law, such as past hiring '
            'requests, without your name and contact details.',
      ]),
      LegalSection('Your rights', [
        'Under UAE data protection law you may ask to see, correct or '
            'delete your personal data, and to object to some uses of it. '
            'You can edit your details in Profile, and request deletion with '
            'Delete my account. For anything else, contact us.',
      ]),
      LegalSection('Security', [
        'Your data is sent over encrypted connections and protected by '
            'access controls, so customers and staff see only what they '
            'need.',
      ]),
      LegalSection('Changes', [
        'We will update this policy when our practices change and show the '
            'date of the latest version above.',
      ]),
      LegalSection('Contact us', [_contact]),
    ],
  );

  static const LegalDocument terms = LegalDocument(
    title: 'Terms and Conditions',
    updated: '27 November 2026',
    sections: [
      LegalSection('About these terms', [
        'These terms apply when you use the Golden Maids app, run by '
            '$_company. By creating an account or making a request in the '
            'app, you accept them.',
      ]),
      LegalSection('Your account', [
        'Please give accurate details and keep your sign-in secure. You are '
            'responsible for requests made from your account.',
      ]),
      LegalSection('Hiring a domestic worker', [
        'A hiring request is not a contract. Hiring depends on the '
            "worker's availability and on visa, medical and other legal "
            'requirements. The hire is governed by the written contract you '
            'sign with us, including its fees and conditions.',
        'You agree to treat the worker fairly and to follow UAE law on '
            'domestic workers.',
      ]),
      LegalSection('Using the app', [
        'Please do not misuse the app, try to access data that is not '
            'yours, or give false information.',
      ]),
      LegalSection('Responsibility', [
        'We provide the app and our services with reasonable care. To the '
            'extent the law allows, we are not responsible for losses that '
            'we could not reasonably foresee or control.',
      ]),
      LegalSection('Changes and governing law', [
        'We may update these terms and will show the date of the latest '
            'version above. These terms are governed by the laws of the '
            'United Arab Emirates.',
      ]),
      LegalSection('Contact us', [_contact]),
    ],
  );
}
