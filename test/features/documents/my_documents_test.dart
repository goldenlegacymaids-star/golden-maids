import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_maids/features/authentication/domain/auth_repository.dart';
import 'package:golden_maids/features/documents/domain/customer_document.dart';
import 'package:golden_maids/features/documents/presentation/document_sample.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_document_repository.dart';
import '../../helpers/test_app.dart';

const _profileIcon = Icons.person_outline_rounded;

void main() {
  late FakeAuthRepository auth;
  late FakeDocumentRepository documents;
  PickedDocument? nextFile;

  setUp(() {
    auth = FakeAuthRepository(
      signedInUser: const AppUser(id: 'u1', fullName: 'Sarah Khan'),
    );
    documents = FakeDocumentRepository(
      documents: [
        FakeDocumentRepository.sample(
          status: DocumentStatus.needsNewCopy,
          staffNote: 'The photo page is blurred.',
        ),
        FakeDocumentRepository.sample(
          id: 'd-eid',
          type: DocumentType.emiratesId,
          status: DocumentStatus.approved,
        ),
      ],
    );
    nextFile = null;
  });
  tearDown(() => auth.dispose());

  Future<void> openDocuments(WidgetTester tester) async {
    await pumpTestApp(
      tester,
      auth: auth,
      documents: documents,
      pickDocument: () async => nextFile,
    );
    await openTab(tester, _profileIcon);
    await tapAndSettle(tester, find.text('My Documents'));
  }

  testWidgets('shows each document with its status and the agency note', (
    tester,
  ) async {
    await openDocuments(tester);

    expect(find.textContaining('Only you and the Golden Maids'), findsOneWidget);
    expect(find.text('Emirates ID'), findsOneWidget);
    // Each card shows a sample drawing of its document.
    expect(
      find.byWidgetPredicate(
        (w) => w is DocumentSample && w.type == DocumentType.emiratesId,
      ),
      findsOneWidget,
    );
    expect(find.text('Approved'), findsOneWidget);
    expect(find.text('Passport copy'), findsOneWidget);
    expect(find.text('Needs a new copy'), findsOneWidget);
    expect(
      find.text('From the agency: The photo page is blurred.'),
      findsOneWidget,
    );
    expect(find.text('Not uploaded yet'), findsNWidgets(2));
  });

  testWidgets('upload a new document, and replace one', (tester) async {
    await openDocuments(tester);

    nextFile = FakeDocumentRepository.file('salary.pdf');
    await tapAndSettle(tester, find.text('Upload').first);
    expect(documents.uploads.single.type, DocumentType.salaryCertificate);
    expect(
      find.text('Salary certificate sent. The agency will review it.'),
      findsOneWidget,
    );
    expect(find.text('Under review'), findsOneWidget);

    nextFile = FakeDocumentRepository.file('passport-new.jpg');
    await tapAndSettle(tester, find.text('Replace').first);
    expect(documents.uploads.last.type, DocumentType.emiratesId);
    expect(documents.uploads.last.replaced, isTrue);
  });

  testWidgets('wrong or too large files are refused before uploading', (
    tester,
  ) async {
    await openDocuments(tester);

    nextFile = FakeDocumentRepository.file('notes.docx');
    await tapAndSettle(tester, find.text('Upload').first);
    expect(find.text('Please choose a PDF, JPG or PNG file.'), findsOneWidget);

    nextFile = FakeDocumentRepository.file(
      'big.pdf',
      size: PickedDocument.maxBytes + 1,
    );
    await tapAndSettle(tester, find.text('Upload').first);
    expect(find.textContaining('larger than 10 MB'), findsOneWidget);
    expect(documents.uploads, isEmpty);
  });

  testWidgets('delete asks first', (tester) async {
    await openDocuments(tester);

    await tapAndSettle(tester, find.text('Delete').first);
    expect(find.text('Delete your Emirates ID?'), findsOneWidget);
    await tapAndSettle(tester, find.text('Keep'));
    expect(documents.deleted, isEmpty);

    await tapAndSettle(tester, find.text('Delete').first);
    await tapAndSettle(tester, find.widgetWithText(TextButton, 'Delete').last);
    expect(documents.deleted, ['d-eid']);
    expect(find.text('Emirates ID deleted.'), findsOneWidget);
  });

  test('file checks', () {
    expect(PickedDocument.mimeTypeFor('A.PDF'), 'application/pdf');
    expect(PickedDocument.mimeTypeFor('photo.jpeg'), 'image/jpeg');
    expect(PickedDocument.mimeTypeFor('scan.png'), 'image/png');
    expect(PickedDocument.mimeTypeFor('virus.exe'), isNull);
    expect(fileSizeLabel(240 * 1024), '240 KB');
    expect(fileSizeLabel(1700 * 1024), '1.7 MB');
  });
}
