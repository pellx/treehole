import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_cropper/image_cropper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.hunghd.vn/image_cropper');

  for (final dark in [false, true]) {
    test(
      'passes the complete ${dark ? "dark" : "light"} palette to iOS',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'crop-theme-test',
        );
        final source = await File(
          '${directory.path}/source.png',
        ).writeAsBytes([0]);
        MethodCall? captured;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              captured = call;
              return null; // Native cancel must remain a normal null result.
            });
        try {
          final background = dark ? const Color(0xFF191919) : Colors.white;
          final foreground = dark
              ? const Color(0xFFD3D3D3)
              : const Color(0xFF333333);
          final result = await ImageCropper().cropImage(
            sourcePath: source.path,
            aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
            uiSettings: [
              ThemedIOSUiSettings(
                backgroundColor: background,
                toolbarColor: background,
                foregroundColor: foreground,
                accentColor: const Color(0xFF2693FF),
                dark: dark,
                title: '裁剪头像',
                doneButtonTitle: '完成',
                cancelButtonTitle: '取消',
                aspectRatioLockEnabled: true,
                resetAspectRatioEnabled: false,
                aspectRatioPickerButtonHidden: true,
              ),
            ],
          );
          expect(result, isNull);
          expect(captured!.method, 'cropImage');
          final arguments = captured!.arguments as Map;
          expect(arguments['ios.treehole_theme'], {
            'background': background.toARGB32(),
            'surface': background.toARGB32(),
            'foreground': foreground.toARGB32(),
            'accent': 0xFF2693FF,
            'dark': dark,
          });
          expect(arguments['ios.title'], '裁剪头像');
          expect(arguments['ios.aspect_ratio_lock_enabled'], true);
          expect(arguments['ratio_x'], 1);
          expect(arguments['ratio_y'], 1);
        } finally {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null);
          await directory.delete(recursive: true);
        }
      },
    );
  }
}
