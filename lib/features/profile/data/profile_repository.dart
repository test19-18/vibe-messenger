import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/error_message.dart';
import '../domain/user_profile.dart';

class ProfileRepository {
  const ProfileRepository(this._client);

  final SupabaseClient? _client;

  SupabaseClient get _requiredClient =>
      _client ?? (throw const BackendUnavailableException());

  static const _profileColumns =
      'id,username,display_name,avatar_path,bio,created_at,updated_at';
  static const _profileSelection =
      '$_profileColumns,user_presence(last_seen_at,online_until)';

  Future<UserProfile?> getProfile(String userId) async {
    final response = await _requiredClient
        .from('profiles')
        .select(_profileSelection)
        .eq('id', userId)
        .maybeSingle();
    if (response == null) {
      return null;
    }
    return _withSignedAvatar(UserProfile.fromMap(response));
  }

  Future<List<UserProfile>> listProfiles({
    required String currentUserId,
    String query = '',
  }) async {
    final response = await _requiredClient
        .from('profiles')
        .select(_profileSelection)
        .neq('id', currentUserId)
        .order('display_name')
        .limit(100);
    final parsedProfiles = response.map(UserProfile.fromMap).toList();
    final normalizedQuery = query.trim().toLowerCase();
    final filteredProfiles = normalizedQuery.isEmpty
        ? parsedProfiles
        : parsedProfiles.where((profile) {
            return profile.visibleName.toLowerCase().contains(
                  normalizedQuery,
                ) ||
                profile.handle.toLowerCase().contains(normalizedQuery);
          }).toList();
    return Future.wait(filteredProfiles.map(_withSignedAvatar));
  }

  Future<UserProfile> upsertProfile(UserProfile profile) async {
    final updated = await _requiredClient
        .from('profiles')
        .update(profile.toUpdateMap())
        .eq('id', profile.id)
        .select(_profileColumns)
        .maybeSingle();
    final response =
        updated ??
        await _requiredClient
            .from('profiles')
            .insert(profile.toInsertMap())
            .select(_profileColumns)
            .single();
    return _withSignedAvatar(UserProfile.fromMap(response));
  }

  Future<String> uploadAvatar({
    required String userId,
    required Uint8List bytes,
    required String extension,
    required String contentType,
  }) async {
    if (bytes.isEmpty || bytes.length > 10 * 1024 * 1024) {
      throw const FormatException('Аватар должен быть меньше 10 МБ.');
    }
    final safeExtension = extension.toLowerCase().replaceAll(
      RegExp('[^a-z0-9]'),
      '',
    );
    final path =
        '$userId/avatar-${DateTime.now().toUtc().microsecondsSinceEpoch}.'
        '${safeExtension.isEmpty ? 'jpg' : safeExtension}';
    await _requiredClient.storage
        .from('avatars')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: false),
        );
    return path;
  }

  Future<UserProfile> _withSignedAvatar(UserProfile profile) async {
    final avatarPath = profile.avatarPath?.trim();
    if (avatarPath == null || avatarPath.isEmpty) {
      return profile;
    }
    try {
      final signedUrl = await _requiredClient.storage
          .from('avatars')
          .createSignedUrl(avatarPath, 3600);
      return profile.copyWith(avatarUrl: signedUrl);
    } catch (_) {
      return profile;
    }
  }
}
