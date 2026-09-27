import 'package:flutter/painting.dart';
import 'package:image_cropper_platform_interface/image_cropper_platform_interface.dart';

/// Optional iOS palette supported by Treehole's local image_cropper bridge.
class ThemedIOSUiSettings extends IOSUiSettings {
  final Color backgroundColor;
  final Color toolbarColor;
  final Color foregroundColor;
  final Color accentColor;
  final Color? dimmedLayerColor;
  final bool dark;

  ThemedIOSUiSettings({
    required this.backgroundColor,
    required this.toolbarColor,
    required this.foregroundColor,
    required this.accentColor,
    required this.dark,
    this.dimmedLayerColor,
    super.title,
    super.doneButtonTitle,
    super.cancelButtonTitle,
    super.aspectRatioLockEnabled,
    super.resetAspectRatioEnabled,
    super.aspectRatioPickerButtonHidden,
  });

  @override
  Map<String, dynamic> toMap() => {
        ...super.toMap(),
        'ios.treehole_theme': {
          'background': backgroundColor.toARGB32(),
          'surface': toolbarColor.toARGB32(),
          'foreground': foregroundColor.toARGB32(),
          'accent': accentColor.toARGB32(),
          'dark': dark,
          if (dimmedLayerColor != null)
            'dimmedLayer': dimmedLayerColor!.toARGB32(),
        },
      };
}
