import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:musi_link/utils/error_reporter.dart';

class StorageService {
  StorageService({required FirebaseStorage storage}) : _storage = storage;

  final FirebaseStorage _storage;

  Future<String?> uploadProfilePhoto(String uid, XFile imageFile) async {
    try {
      final ref = _storage.ref('profile_photos/$uid');
      final bytes = await imageFile.readAsBytes();
      await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      return await ref.getDownloadURL();
    } catch (e, st) {
      await reportError(e, st);
      rethrow;
    }
  }

  Future<void> deleteProfilePhoto(String uid) async {
    try {
      await _storage.ref('profile_photos/$uid').delete();
    } on FirebaseException catch (e, st) {
      if (e.code == 'object-not-found') return;
      await reportError(e, st);
      rethrow;
    } catch (e, st) {
      await reportError(e, st);
      rethrow;
    }
  }
}
