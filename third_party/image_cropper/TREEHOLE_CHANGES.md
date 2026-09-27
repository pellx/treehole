# Treehole image_cropper extension

Source: image_cropper 11.0.0 from https://pub.dev/packages/image_cropper/versions/11.0.0
Upstream: https://github.com/hnvn/flutter_image_cropper
The upstream LICENSE is retained. Only runtime sources are included (no example assets or standalone Gradle wrapper).

Local changes:
- Export ThemedIOSUiSettings, an IOSUiSettings subclass that adds ios.treehole_theme to the existing cropImage method call.
- Instantiate THThemedCropViewController (a TOCropViewController subclass) in the existing iOS plugin. It applies per-controller colors on load/appearance and overrides only its own interface/status-bar style.
- Pin TOCropViewController to 2.8.0 in both CocoaPods and Swift Package Manager. Its toolbar paints an internal plain UIView backdrop over backgroundColor; the extension recolors that direct child through normal UIView APIs. On upgrades, check this hierarchy and the toolbar/control setters.
- Existing cropping, rotation, result encoding, cancellation and Android behavior remain upstream implementations. No global UIKit appearance changes, method swizzling, or private selectors.

Verification:
- Flutter method-channel tests: test/avatar_cropper_theme_test.dart (light/dark ARGB values, original crop options, cancellation).
- Actual iOS native compilation/UI must be checked on macOS/Xcode. On iPhone, test App light with system dark and App dark with system light; verify background, title, toolbar, done/cancel, rotate/reset, safe areas, portrait/landscape, cancel/reopen, and successful upload. Returning to other screens must preserve their theme.
- Windows cannot validate UIKit compilation or visual appearance.
- Replacing the path dependency with the upstream hosted package removes this iOS theme extension.