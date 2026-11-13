import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

/// Chooses a profile photo from the device. Returns the local file path, or
/// `null` if the user cancelled.
abstract class PhotoPicker {
  Future<String?> pickAvatar();
}

class ImagePickerPhotoPicker implements PhotoPicker {
  ImagePickerPhotoPicker([ImagePicker? picker]) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<String?> pickAvatar() async {
    final x = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    return x?.path;
  }
}

/// Uploads the avatar to Firebase Storage `profilePhotos/{uid}/avatar.jpg`
/// and returns its download URL.
abstract class PhotoUploader {
  Future<String> uploadAvatar({required String uid, required String localPath});
}

class FirebasePhotoUploader implements PhotoUploader {
  FirebasePhotoUploader([FirebaseStorage? storage]) : _storage = storage ?? FirebaseStorage.instance;

  final FirebaseStorage _storage;

  @override
  Future<String> uploadAvatar({required String uid, required String localPath}) async {
    final ref = _storage.ref('profilePhotos/$uid/avatar.jpg');
    await ref.putFile(File(localPath), SettableMetadata(contentType: 'image/jpeg'));
    return ref.getDownloadURL();
  }
}
