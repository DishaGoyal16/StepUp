import 'photo_services.dart';

class FakePhotoPicker implements PhotoPicker {
  FakePhotoPicker([this.path]);

  String? path;

  @override
  Future<String?> pickAvatar() async => path;
}

class FakePhotoUploader implements PhotoUploader {
  final List<({String uid, String localPath})> uploads = [];
  bool shouldFail = false;

  @override
  Future<String> uploadAvatar({required String uid, required String localPath}) async {
    if (shouldFail) throw StateError('upload failed');
    uploads.add((uid: uid, localPath: localPath));
    return 'https://fake.storage/profilePhotos/$uid/avatar.jpg';
  }
}
