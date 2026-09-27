import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:treehole/services/avatar_cropper.dart';

void main() {
  for (final size in [32, 1024]) {
    test('normalizes a ${size}px crop to a 512px JPEG', () {
      final input = img.Image(width: size, height: size);
      img.fill(input, color: img.ColorRgb8(210, 40, 50));
      final result = encodeAvatarJpeg(Uint8List.fromList(img.encodePng(input)));
      final decoded = img.decodeJpg(result)!;
      expect(decoded.width, 512);
      expect(decoded.height, 512);
      expect(decoded.getPixel(256, 256).r, closeTo(210, 5));
    });
  }
  test('rejects unreadable crop output', () {
    expect(() => encodeAvatarJpeg(Uint8List(8)), throwsFormatException);
  });
}
