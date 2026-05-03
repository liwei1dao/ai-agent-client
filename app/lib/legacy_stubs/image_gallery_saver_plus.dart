/// Stub of `image_gallery_saver_plus` for the legacy meeting module port.
import 'dart:typed_data';

class ImageGallerySaverPlus {
  static Future<dynamic> saveImage(
    Uint8List imageBytes, {
    int quality = 80,
    String? name,
    bool isReturnImagePathOfIOS = false,
  }) async =>
      <String, dynamic>{'isSuccess': false};

  static Future<dynamic> saveFile(
    String file, {
    String? name,
    bool isReturnPathOfIOS = false,
  }) async =>
      <String, dynamic>{'isSuccess': false};
}
