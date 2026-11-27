import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_maids/features/authentication/domain/auth_repository.dart';
import 'package:golden_maids/features/documents/domain/customer_document.dart';
import 'package:golden_maids/features/service_requests/domain/service_request.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_billing_repository.dart';
import '../../helpers/fake_service_request_repository.dart';
import '../../helpers/test_app.dart';

const _requestsIcon = Icons.assignment_outlined;
const _walletIcon = Icons.account_balance_wallet_outlined;

void main() {
  late FakeAuthRepository auth;
  late FakeServiceRequestRepository requests;
  late FakeLauncher launcher;
  PickedDocument? nextFile;

  setUp(() {
    auth = FakeAuthRepository(
      signedInUser: const AppUser(id: 'u1', fullName: 'Sarah Khan'),
    );
    requests = FakeServiceRequestRepository();
    launcher = FakeLauncher();
    nextFile = null;
  });
  tearDown(() => auth.dispose());

  Future<void> start(WidgetTester tester, {FakeBillingRepository? billing}) =>
      pumpTestApp(
        tester,
        auth: auth,
        serviceRequests: requests,
        billing: billing,
        launcher: launcher,
        pickDocument: () async => nextFile,
      );

  group('ServiceRequestDraft', () {
    test('travel requests need the maid, country and leaving date', () {
      const draft = ServiceRequestDraft(type: ServiceRequestType.travelNoc);
      expect(draft.validate().keys, containsAll(['maid', 'country', 'from']));

      final ok = ServiceRequestDraft(
        type: ServiceRequestType.travelNoc,
        maidName: 'Wanjiru',
        travelCountry: 'Kenya',
        travelFrom: DateTime(2026, 12, 20),
      );
      expect(ok.validate(), isEmpty);
      expect(ok.toInsertJson()['travel_from'], '2026-12-20');

      final backBefore = ServiceRequestDraft(
        type: ServiceRequestType.travelLetter,
        maidName: 'Wanjiru',
        travelCountry: 'Kenya',
        travelFrom: DateTime(2026, 12, 20),
        travelTo: DateTime(2026, 12, 1),
      );
      expect(backBefore.validate().keys, ['to']);
    });

    test('problems and support need a note; a visa needs nothing else', () {
      expect(
        const ServiceRequestDraft(type: ServiceRequestType.problem)
            .validate()
            .keys,
        ['details'],
      );
      expect(
        const ServiceRequestDraft(type: ServiceRequestType.maidVisa).validate(),
        isEmpty,
      );
      // Travel fields are not sent for other types.
      final json = ServiceRequestDraft(
        type: ServiceRequestType.salaryCertificate,
        maidName: 'Wanjiru',
        travelCountry: 'Kenya',
        travelFrom: DateTime(2026, 12, 20),
      ).toInsertJson();
      expect(json['travel_country'], '');
      expect(json['travel_from'], isNull);
    });
  });

  testWidgets('New lists hiring and every request type', (tester) async {
    await start(tester);
    await openTab(tester, _requestsIcon);
    expect(find.text('No requests yet'), findsOneWidget);

    await tapAndSettle(tester, find.text('New'));
    expect(find.text('What do you need?'), findsOneWidget);
    expect(find.text('Hire a maid'), findsOneWidget);
    for (final type in ServiceRequestType.values) {
      await scrollTo(tester, find.text(type.label));
      expect(find.text(type.label), findsOneWidget);
    }
  });

  testWidgets('send a travel NOC with an attachment, then follow it', (
    tester,
  ) async {
    await start(tester);
    await openTab(tester, _requestsIcon);
    await tapAndSettle(tester, find.text('New'));
    await tapAndSettle(tester, find.text('Maid travel NOC'));

    // Nothing filled in yet: the form says what is missing.
    await tapAndSettle(tester, find.text('Send request'));
    expect(find.text('Choose the maid this request is for.'), findsOneWidget);
    expect(find.text('Enter the country she is travelling to.'), findsOneWidget);
    expect(find.text('Choose the date she leaves.'), findsOneWidget);
    expect(requests.submitted, isEmpty);

    await tester.enterText(
      find.widgetWithText(TextField, "Maid's name"),
      'Wanjiru Kamau',
    );
    await tester.enterText(find.widgetWithText(TextField, 'Country'), 'Kenya');
    await tapAndSettle(tester, find.text('Leaving'));
    await tapAndSettle(tester, find.text('OK'));

    nextFile = PickedDocument(
      name: 'ticket.pdf',
      bytes: Uint8List.fromList([1, 2, 3]),
    );
    await tapAndSettle(tester, find.text('Add a photo or PDF'));
    expect(find.textContaining('ticket.pdf'), findsOneWidget);

    await tapAndSettle(tester, find.text('Send request'));
    final sent = requests.submitted.single;
    expect(sent.type, ServiceRequestType.travelNoc);
    expect(sent.maidName, 'Wanjiru Kamau');
    expect(sent.travelCountry, 'Kenya');
    expect(sent.travelFrom, isNotNull);
    expect(sent.attachments.single.name, 'ticket.pdf');

    // The request page.
    expect(find.text('SR-2026-000001'), findsWidgets);
    expect(find.text('Kenya'), findsOneWidget);
    expect(find.text('No messages yet. Our team will reply here.'),
        findsOneWidget);
    await scrollTo(tester, find.text('ticket.pdf'));
    expect(find.text('ticket.pdf'), findsOneWidget);
  });

  testWidgets('a request shows agency documents and messages; reply and '
      'cancel', (tester) async {
    requests = FakeServiceRequestRepository(
      requests: [
        FakeServiceRequestRepository.sample(
          messages: [
            ServiceRequestMessage(
              id: 1,
              body: 'Please send the return ticket.',
              fromStaff: true,
              createdAt: DateTime(2026, 11, 27, 17),
            ),
          ],
          files: [
            ServiceRequestFile(
              id: 'f1',
              storagePath: 's1/noc.pdf',
              fileName: 'noc.pdf',
              title: 'Travel NOC',
              sizeBytes: 100,
              fromStaff: true,
              createdAt: DateTime(2026, 11, 27, 18),
            ),
          ],
        ),
      ],
    );
    await start(tester);
    await openTab(tester, _requestsIcon);
    expect(find.text('Other requests'), findsOneWidget);
    await tapAndSettle(tester, find.text('Maid travel NOC'));

    expect(find.text('From the agency'), findsOneWidget);
    await tapAndSettle(tester, find.text('Travel NOC'));
    expect(launcher.opened.single.path, '/s1/noc.pdf');

    await scrollTo(tester, find.text('Please send the return ticket.'));
    expect(find.text('Please send the return ticket.'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Write a message'),
      'Sent it now.',
    );
    await tapAndSettle(tester, find.byTooltip('Send message'));
    expect(find.text('Sent it now.'), findsOneWidget);

    await tapAndSettle(tester, find.text('Cancel request'));
    await tapAndSettle(tester, find.text('Cancel request').last);
    expect(requests.requests.single.request.status,
        ServiceRequestStatus.cancelled);
    expect(find.text('Cancelled'), findsWidgets);
  });

  testWidgets('the Wallet lists receipts and invoices; each opens', (
    tester,
  ) async {
    await start(
      tester,
      billing: FakeBillingRepository(
        documents: [
          FakeBillingRepository.invoice(),
          FakeBillingRepository.receipt(),
        ],
      ),
    );
    await openTab(tester, _walletIcon);

    expect(find.text('Receipts and invoices'), findsOneWidget);
    expect(find.text('Invoice INV-42'), findsOneWidget);
    expect(find.text('Unpaid'), findsOneWidget);
    expect(find.text('Receipt R-1001'), findsOneWidget);

    await tapAndSettle(tester, find.text('Receipt R-1001'));
    expect(launcher.opened.single.path, '/u1/r-1001.pdf');
  });
}
