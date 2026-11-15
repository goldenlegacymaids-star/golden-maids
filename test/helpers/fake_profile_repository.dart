import 'package:golden_maids/core/errors/app_failure.dart';
import 'package:golden_maids/features/profile/data/profile_repository.dart';
import 'package:golden_maids/features/profile/domain/profile.dart';

/// In-memory [ProfileRepository] for widget tests.
class FakeProfileRepository implements ProfileRepository {
  FakeProfileRepository({this.profile});

  Profile? profile;

  @override
  Future<Profile> getMyProfile() async {
    final current = profile;
    if (current == null) throw const NotFoundFailure();
    return current;
  }

  @override
  Future<void> updateFullName(String fullName) async {
    final current = profile;
    if (current == null) throw const NotFoundFailure();
    profile = Profile(
      id: current.id,
      fullName: fullName,
      email: current.email,
      phone: current.phone,
    );
  }
}
