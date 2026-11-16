import 'package:flutter_test/flutter_test.dart';
import 'package:golden_maids/features/candidates/domain/candidate.dart';
import 'package:golden_maids/features/candidates/presentation/widgets/candidate_cards.dart';

void main() {
  const base = Candidate(id: 'x', code: 'GM-1', nationality: 'Kenya');
  final now = DateTime(2026, 11, 16, 10);

  Candidate where(
    MaidLocation location, {
    CandidateAvailability availability = CandidateAvailability.available,
    DateTime? from,
  }) => Candidate(
    id: base.id,
    code: base.code,
    nationality: base.nationality,
    location: location,
    availability: availability,
    availableFrom: from,
  );

  test('in the UAE: available now, from a date, or just the place', () {
    expect(
      locationLabel(where(MaidLocation.inUae), now: now),
      'In the UAE · Available now',
    );
    expect(
      locationLabel(
        where(MaidLocation.inUae, from: DateTime(2026, 11, 24)),
        now: now,
      ),
      'In the UAE · From 24 Nov',
    );
    expect(
      locationLabel(
        where(MaidLocation.inUae, from: DateTime(2026, 11, 16)),
        now: now,
      ),
      'In the UAE · Available now',
    );
    expect(
      locationLabel(
        where(
          MaidLocation.inUae,
          availability: CandidateAvailability.reserved,
        ),
        now: now,
      ),
      'In the UAE',
    );
  });

  test('outside the UAE: the nationality arrival time, or on request', () {
    expect(
      locationLabel(where(MaidLocation.outsideUae), arrival: '10–20 days'),
      'Outside the UAE · Arrives in 10–20 days',
    );
    expect(
      locationLabel(where(MaidLocation.outsideUae)),
      'Outside the UAE · Arrival on request',
    );
  });

  test('arrival label from the nationality', () {
    expect(
      const MaidNationality(
        name: 'Kenya',
        code: 'KE',
        arrivalDaysMin: 10,
        arrivalDaysMax: 20,
      ).arrivalLabel,
      '10–20 days',
    );
    expect(
      const MaidNationality(
        name: 'Kenya',
        code: 'KE',
        arrivalDaysMin: 14,
        arrivalDaysMax: 14,
      ).arrivalLabel,
      '14 days',
    );
    expect(const MaidNationality(name: 'Kenya', code: 'KE').arrivalLabel, isNull);
  });

  test('values match the database', () {
    expect(MaidLocation.fromValue('in_uae'), MaidLocation.inUae);
    expect(MaidLocation.fromValue('outside_uae'), MaidLocation.outsideUae);
    expect(MaidLocation.fromValue('mars'), isNull);
    expect(VisaRoute.fromValue('sponsor'), VisaRoute.sponsor);
    expect(VisaRoute.fromValue('company'), VisaRoute.company);
  });
}
