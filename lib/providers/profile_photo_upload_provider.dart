import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:musi_link/providers/firebase_providers.dart';
import 'package:musi_link/providers/service_providers.dart';
import 'package:musi_link/utils/error_reporter.dart';

class ProfilePhotoUpload {
  const ProfilePhotoUpload({
    required this.uid,
    required this.bytes,
    required this.isUploading,
  });

  final String uid;
  final Uint8List bytes;
  final bool isUploading;
}

/// Keeps the preview and upload alive when the originating screen is closed.
class ProfilePhotoUploadNotifier extends Notifier<ProfilePhotoUpload?> {
  @override
  ProfilePhotoUpload? build() => null;

  Future<void> upload({
    required String uid,
    required XFile image,
    required Uint8List bytes,
    bool isSetup = false,
  }) async {
    final auth = ref.read(firebaseAuthProvider);
    if (auth.currentUser?.uid != uid) return;
    if (state?.uid == uid && state!.isUploading) return;
    final storage = ref.read(storageServiceProvider);
    final users = ref.read(userServiceProvider);
    final previous = state?.uid == uid ? state : null;
    final pending = ProfilePhotoUpload(
      uid: uid,
      bytes: bytes,
      isUploading: true,
    );
    state = pending;

    bool isCurrent() =>
        ref.mounted &&
        auth.currentUser?.uid == uid &&
        identical(state, pending);

    try {
      final url = await storage.uploadProfilePhoto(uid, image);
      if (!isCurrent()) return;
      if (url == null) throw StateError('Profile photo upload returned no URL');
      if (isSetup) {
        await users.updateSetupPhoto(uid, url);
      } else {
        await users.updateProfile(uid, photoUrl: url);
      }
      if (!isCurrent()) return;
      // Retain the local preview while the profile stream catches up.
      state = ProfilePhotoUpload(uid: uid, bytes: bytes, isUploading: false);
    } catch (error, stack) {
      reportError(error, stack).ignore();
      if (!isCurrent()) return;
      state = previous;
      rethrow;
    }
  }
}

final profilePhotoUploadProvider =
    NotifierProvider<ProfilePhotoUploadNotifier, ProfilePhotoUpload?>(
      ProfilePhotoUploadNotifier.new,
    );
