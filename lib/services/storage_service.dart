import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:musi_link/utils/error_reporter.dart';

class StorageService {
  StorageService({required this._storage});

  final FirebaseStorage _storage;

  Future<String?> uploadProfilePhoto(String uid, XFile imageFile) =>
      _uploadPhoto('profile_photos/$uid', imageFile);

  /// Solo los miembros pueden escribir en la ruta de su grupo.
  Future<String?> uploadGroupPhoto(String chatId, XFile imageFile) =>
      _uploadPhoto('group_photos/$chatId', imageFile);

  Future<String?> _uploadPhoto(String path, XFile imageFile) async {
    try {
      final ref = _storage.ref(path);
      final bytes = await imageFile.readAsBytes();
      await ref.putData(
        bytes,
        SettableMetadata(
          contentType: 'image/jpeg',
          cacheControl: 'private,max-age=86400',
        ),
      );
      return await ref.getDownloadURL();
    } catch (e, st) {
      await reportError(e, st);
      rethrow;
    }
  }
}
