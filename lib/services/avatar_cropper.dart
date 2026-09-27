import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_cropper/image_cropper.dart';
import 'package:path_provider/path_provider.dart';

import '../theme/avatar_cropper_theme.dart';

/// Uses the native crop page; only the final size/encoding is handled here.
class AvatarCropper {
  static Future<File?> crop(
    String sourcePath, {
    required ThemeData theme,
  }) async {
    final colors = AvatarCropperTheme.forBrightness(theme.brightness);
    final cropped = await ImageCropper().cropImage(
      sourcePath: sourcePath,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      maxWidth: 512,
      maxHeight: 512,
      compressFormat: ImageCompressFormat.png,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: '裁剪头像',
          toolbarColor: colors.toolbar,
          toolbarWidgetColor: colors.foreground,
          backgroundColor: colors.background,
          activeControlsWidgetColor: colors.accent,
          dimmedLayerColor: colors.dimmedLayer,
          cropFrameColor: colors.cropFrame,
          cropGridColor: colors.cropGrid,
          statusBarLight: theme.brightness == Brightness.light,
          navBarLight: theme.brightness == Brightness.light,
          initAspectRatio: CropAspectRatioPreset.square,
          lockAspectRatio: true,
          aspectRatioPresets: [CropAspectRatioPreset.square],
        ),
        ThemedIOSUiSettings(
          backgroundColor: colors.background,
          toolbarColor: colors.toolbar,
          foregroundColor: colors.foreground,
          accentColor: colors.accent,
          dimmedLayerColor: colors.dimmedLayer,
          dark: theme.brightness == Brightness.dark,
          title: '裁剪头像',
          doneButtonTitle: '完成',
          cancelButtonTitle: '取消',
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
          aspectRatioPickerButtonHidden: true,
        ),
      ],
    );
    if (cropped == null) return null;
    try {
      final bytes = await compute(
        encodeAvatarJpeg,
        await cropped.readAsBytes(),
      );
      final directory = await Directory(
        '${(await getTemporaryDirectory()).path}/avatar-upload',
      ).create(recursive: true);
      return await File(
        '${directory.path}/${DateTime.now().microsecondsSinceEpoch}.jpg',
      ).writeAsBytes(bytes, flush: true);
    } finally {
      await File(cropped.path).delete().catchError((_) => File(cropped.path));
    }
  }
}

/// Upscales small crops as well. Copying pixels into a new image drops metadata.
Uint8List encodeAvatarJpeg(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw const FormatException('无法读取裁剪后的图片');
  final oriented = img.bakeOrientation(decoded);
  final resized = img.copyResizeCropSquare(
    oriented,
    size: 512,
    interpolation: img.Interpolation.linear,
  );
  final clean = img.Image(width: 512, height: 512, numChannels: 3);
  img.fill(clean, color: img.ColorRgb8(255, 255, 255));
  img.compositeImage(clean, resized);
  return Uint8List.fromList(img.encodeJpg(clean, quality: 90));
}
