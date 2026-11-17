import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_maids/features/authentication/domain/auth_repository.dart';
import 'package:golden_maids/features/documents/domain/customer_document.dart';
import 'package:golden_maids/features/visas/domain/visa_application.dart';
import 'package:golden_maids/features/visas/presentation/visa_screens.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_document_repository.dart';
import '../../helpers/fake_notification_repository.dart';
import '../../helpers/fake_visa_repository.dart';
import '../../helpers/test_app.dart';

const _profileTab = Icons.person_outline_rounded;

Future<void> _openVisas(WidgetTester tester) async {
  await openTab(tester, _profileTab);
  await tapAndSettle(tester, find.text('My Visa Applications'));
  expect(find.text('My Visa Applications'), findsWidgets);
}

void main() {
  late FakeAuthRepository auth;

  setUp(() {
    auth = FakeAuthRepository(
      signedInUser: const AppUser(id: 'u1', fullName: 'Sarah Khan'),
    );
  });
  tearDown(() => auth.dispose());

  testWidgets('lists visas with progress; a visa shows its steps and files', (
    tester,
  ) async {
    final visas = FakeVisaRepository(
      applications: [FakeVisaRepository.abroad()],
    );
    final launcher = FakeLauncher();
    await pumpTestApp(tester, auth: auth, visas: visas, launcher: launcher);
    await _openVisas(tester);

    expect(find.text('Your maid'), findsOneWidget);
    expect(find.text('Company Visa · From abroad'), findsOneWidget);
    expect(find.text('In progress'), findsOneWidget);
    expect(find.text('Step 3 of 8 · Flight booked'), findsOneWidget);

    await tapAndSettle(tester, find.text('Your maid'));
    expect(find.text('Ref. HR-2026-000004'), findsOneWidget);
    expect(find.textContaining('Golden Maids is the sponsor'), findsOneWidget);
    expect(find.text('Contract signed (MOHRE)'), findsOneWidget);
    expect(find.text('Flight options sent to you.'), findsOneWidget);
    // Company visa: nothing for the customer to send.
    expect(find.text('Needed from you'), findsNothing);

    await scrollTo(tester, find.text('Ask about this visa'));
    expect(find.text('Entry permit'), findsOneWidget);
    await tapAndSettle(tester, find.text('View'));
    expect(visas.viewed.single.fileName, 'entry-permit.pdf');
    expect(launcher.opened.single.path, contains('entry-permit.pdf'));

    await tapAndSettle(tester, find.text('Ask about this visa'));
    expect(launcher.opened.last.toString(), contains('HR-2026-000004'));
  });

  testWidgets('a GCC Sponsor visa asks for the missing documents', (
    tester,
  ) async {
    final visas = FakeVisaRepository(
      applications: [FakeVisaRepository.abroad(sponsor: true)],
    );
    final documents = FakeDocumentRepository(
      documents: [
        FakeDocumentRepository.sample(),
        FakeDocumentRepository.sample(
          id: 'd-eid',
          type: DocumentType.emiratesId,
          status: DocumentStatus.needsNewCopy,
          staffNote: 'Blurred.',
        ),
      ],
    );
    await pumpTestApp(
      tester,
      auth: auth,
      visas: visas,
      documents: documents,
    );
    await _openVisas(tester);

    expect(find.text('Action needed'), findsOneWidget);
    expect(find.text('Please send your documents'), findsOneWidget);

    await tapAndSettle(tester, find.text('Your maid'));
    expect(find.text('Needed from you'), findsOneWidget);
    // The passport was sent; the Emirates ID needs a new copy.
    expect(
      find.text('Emirates ID · Salary certificate · Marriage certificate'),
      findsOneWidget,
    );
    await tapAndSettle(tester, find.text('Send in My Documents'));
    expect(find.text('My Documents'), findsWidgets);
  });

  testWidgets('an empty list explains what will appear', (tester) async {
    await pumpTestApp(tester, auth: auth);
    await _openVisas(tester);
    expect(find.text('No visa applications yet'), findsOneWidget);
  });

  testWidgets('a visa notification opens the visa', (tester) async {
    final visas = FakeVisaRepository(
      applications: [FakeVisaRepository.abroad()],
    );
    final notifications = FakeNotificationRepository(
      notifications: [
        FakeNotificationRepository.sample(
          id: 1,
          kind: 'visa.step',
          title: 'Visa update',
          body: 'Entry permit: done.',
          hiringRequestId: 'r-v1',
        ),
      ],
    );
    await pumpTestApp(
      tester,
      auth: auth,
      visas: visas,
      notifications: notifications,
    );
    await tapAndSettle(tester, find.byTooltip('Notifications'));
    await tapAndSettle(tester, find.text('Visa update'));
    expect(find.text('Visa application'), findsOneWidget);
    expect(find.text('Ref. HR-2026-000004'), findsOneWidget);
  });

  group('visa state', () {
    final today = DateTime(2026, 11, 17);

    test('expiring within 7 days comes first', () {
      final soon = FakeVisaRepository.abroad(
        allDone: true,
        expiresOn: DateTime(2026, 11, 24),
      );
      expect(soon.daysToExpiry(today), 7);
      expect(soon.state(today, missingDocuments: true), VisaState.expiringSoon);
      final later = FakeVisaRepository.abroad(
        allDone: true,
        expiresOn: DateTime(2026, 11, 25),
      );
      expect(later.state(today, missingDocuments: false), VisaState.ready);
    });

    test('a sponsor with missing documents needs to act', () {
      final sponsor = FakeVisaRepository.abroad(sponsor: true);
      expect(
        sponsor.state(today, missingDocuments: true),
        VisaState.actionNeeded,
      );
      expect(
        sponsor.state(today, missingDocuments: false),
        VisaState.inProgress,
      );
      // The agency's own visas never ask the customer for documents.
      expect(
        FakeVisaRepository.abroad().state(today, missingDocuments: true),
        VisaState.inProgress,
      );
    });

    test('the current step is the one in progress, else the next', () {
      final visa = FakeVisaRepository.abroad();
      expect(visa.currentStep?.step, VisaStep.flightBooked);
      expect(visa.doneCount, 2);
      expect(FakeVisaRepository.abroad(allDone: true).currentStep, isNull);
    });

    test('missing sponsor documents: absent or needing a new copy', () {
      final missing = missingSponsorDocuments([
        FakeDocumentRepository.sample(status: DocumentStatus.approved),
        FakeDocumentRepository.sample(
          type: DocumentType.emiratesId,
          status: DocumentStatus.needsNewCopy,
        ),
      ]);
      expect(missing, [
        DocumentType.emiratesId,
        DocumentType.salaryCertificate,
        DocumentType.marriageCertificate,
      ]);
    });
  });
}
