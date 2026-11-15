/// A row of `public.profiles`.
class Profile {
  const Profile({
    required this.id,
    this.fullName,
    this.email,
    this.phone,
    this.avatarUrl,
  });

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'] as String,
      fullName: json['full_name'] as String?,
      email: json['email'] as String?,
      phone: json['phone'] as String?,
      avatarUrl: json['avatar_url'] as String?,
    );
  }

  final String id;
  final String? fullName;
  final String? email;
  final String? phone;

  /// Storage path of the profile photo.
  final String? avatarUrl;

  /// First name for greetings ("Hello, Sarah"), or `null` if unknown.
  String? get firstName {
    final name = fullName?.trim();
    if (name == null || name.isEmpty) return null;
    return name.split(RegExp(r'\s+')).first;
  }
}
