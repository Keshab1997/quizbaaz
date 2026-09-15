import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

/// Uploads admin content images (avatars, shop art) to **Firebase Storage**.
///
/// Replaces the old ImgBB integration, whose API key was committed in the
/// client source (P0 finding R01 — see docs/SECURITY_P0_FIXES.md).
///
/// Security model:
///   * No upload secret lives in the client. Authentication is the caller's
///     Firebase Auth token; authorization is the storage rule
///     `content/** -> write: admin custom claim && image && < 5 MB`
///     (see storage.rules).
///   * Only the admin panel calls this service, and the admin panel is
///     gated on the same `admin` claim.
///
/// Uploaded objects land under `content/avatars/` or `content/shop/` and get
/// a public download URL (storage rules allow public reads on `content/`).
class ImageUploadService {
  static FirebaseStorage get _storage => FirebaseStorage.instance;

  /// Uploads [file] as an avatar into `content/avatars/`.
  static Future<String?> uploadAvatar(File file) =>
      _upload('content/avatars', file);

  /// Uploads [file] as shop art into `content/shop/`.
  static Future<String?> uploadShopItem(File file) =>
      _upload('content/shop', file);

  static Future<String?> _upload(String folder, File file) async {
    try {
      final name = file.path.split(Platform.pathSeparator).last;
      final safeName = _safeName(name);
      final ref = _storage
          .ref()
          .child('$folder/${DateTime.now().millisecondsSinceEpoch}_$safeName');

      final task = ref.putFile(
        file,
        SettableMetadata(contentType: _contentTypeFor(safeName)),
      );
      final snapshot = await task;
      return await snapshot.ref.getDownloadURL();
    } catch (e) {
      debugPrint('ImageUploadService: upload error – $e');
      return null;
    }
  }

  /// Deletes an object previously uploaded here, given its download URL.
  /// Returns false (fail-soft) when the URL is not in this bucket.
  static Future<bool> deleteByUrl(String url) async {
    try {
      final ref = _storage.refFromURL(url);
      await ref.delete();
      return true;
    } catch (e) {
      debugPrint('ImageUploadService: delete error – $e');
      return false;
    }
  }

  static String _safeName(String name) {
    final base = name.split('.').first.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return base.isEmpty ? 'image' : base;
  }

  static String _contentTypeFor(String name) {
    final ext = name.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'png':
      default:
        return 'image/png';
    }
  }
}
