import 'profile.dart';

/// The authenticated user returned from login and refresh flows.
class PreludeUser {
  const PreludeUser({required this.accessToken, required this.profile});

  final String accessToken;
  final PreludeProfile profile;

  Map<String, Object?> toJson() => {
    'accessToken': accessToken,
    'profile': profile.toJson(),
  };

  factory PreludeUser.fromJson(Map<Object?, Object?> json) => PreludeUser(
    accessToken: json['accessToken']! as String,
    profile: PreludeProfile.fromJson(
      Map<Object?, Object?>.from(json['profile']! as Map),
    ),
  );

  @override
  bool operator ==(Object other) =>
      other is PreludeUser &&
      other.accessToken == accessToken &&
      other.profile == profile;

  @override
  int get hashCode => Object.hash(accessToken, profile);

  @override
  String toString() =>
      'PreludeUser(accessToken: <redacted ${accessToken.length} chars>, '
      'profile: $profile)';
}
