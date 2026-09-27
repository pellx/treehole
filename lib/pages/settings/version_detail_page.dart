import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';

import '../../models/version_info.dart';
import '../../widgets/app_toast.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_dimens_accent.dart';

class VersionDetailPage extends StatefulWidget {
  final VersionInfo version;

  const VersionDetailPage({super.key, required this.version});

  @override
  State<VersionDetailPage> createState() => _VersionDetailPageState();
}

class _VersionDetailPageState extends State<VersionDetailPage> {
  static const _installChannel = MethodChannel('treehole/apk_install');
  static const _downloadTimeout = Duration(minutes: 5);

  bool _downloading = false;

  Future<String?> _getApkUrl() async {
    final v = widget.version;
    if (v.downloadUrl.isEmpty) return null;
    final base = v.downloadUrl.endsWith('/')
        ? v.downloadUrl
        : '${v.downloadUrl}/';

    if (Platform.isAndroid) {
      final info = await DeviceInfoPlugin().androidInfo;
      final abis = info.supportedAbis;
      const priority = ['arm64-v8a', 'armeabi-v7a', 'x86_64'];
      for (final abi in priority) {
        if (abis.contains(abi)) {
          return '${base}treehole-v${v.versionNumber}-$abi.apk';
        }
      }
    }
    return '${base}treehole-v${v.versionNumber}-all.apk';
  }

  void _toast(String message) {
    if (!mounted) return;
    showAppToast(context, message: message, duration: const Duration(seconds: 5));
  }

  Future<bool> _ensureInstallAllowed() async {
    if (!Platform.isAndroid) return true;
    try {
      final allowed = await _installChannel.invokeMethod<bool>('canRequestPackageInstalls');
      if (allowed == true) return true;
    } catch (e) {
      debugPrint('[VersionDetail] canRequestPackageInstalls: $e');
    }

    if (!mounted) return false;
    final colors = Theme.of(context).extension<AppColors>()!;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: colors.common.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AccentDimens.dialogRadius),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AccentDimens.dialogPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '请允许本应用「安装未知应用」，否则无法完成更新。打开设置后请开启开关，再返回重试。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: AccentDimens.dialogMessageFontSize,
                  height: AccentDimens.dialogMessageLineHeight,
                  color: onSurface,
                ),
              ),
              const SizedBox(height: AccentDimens.dialogActionsTopGap),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: AccentDimens.dialogActionHeight,
                      child: TextButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        style: TextButton.styleFrom(
                          foregroundColor: onSurface.withValues(
                              alpha: AccentDimens.dialogCancelTextAlpha),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          padding: const EdgeInsets.symmetric(
                              horizontal: AccentDimens.dialogActionHPadding),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                                AccentDimens.dialogActionRadius),
                          ),
                          textStyle: const TextStyle(
                              fontSize: AccentDimens.dialogActionFontSize),
                        ),
                        child: const Text('取消'),
                      ),
                    ),
                  ),
                  const SizedBox(width: AccentDimens.dialogActionGap),
                  Expanded(
                    child: SizedBox(
                      height: AccentDimens.dialogActionHeight,
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colors.postCreate.submitBg,
                          foregroundColor: colors.postCreate.submitText,
                          elevation: 0,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          padding: const EdgeInsets.symmetric(
                              horizontal: AccentDimens.dialogActionHPadding),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                                AccentDimens.dialogActionRadius),
                          ),
                          textStyle: const TextStyle(
                              fontSize: AccentDimens.dialogActionFontSize),
                        ),
                        child: const Text('去设置'),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (go != true) return false;

    try {
      await _installChannel.invokeMethod('openUnknownAppSettings');
    } catch (e) {
      debugPrint('[VersionDetail] openUnknownAppSettings: $e');
      _toast('无法打开设置，请手动在系统设置中允许安装未知应用');
      return false;
    }
    _toast('开启权限后请再点一次「更新」');
    return false;
  }

  Future<void> _install() async {
    if (_downloading) return;
    setState(() => _downloading = true);
    try {
      if (!await _ensureInstallAllowed()) return;

      final url = await _getApkUrl();
      if (url == null) {
        _toast('未配置下载地址');
        return;
      }
      debugPrint('[VersionDetail] 开始下载: $url');

      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/treehole_update.apk');
      await _downloadToFile(url, file);
      if (!mounted) return;

      final result = await OpenFilex.open(
        file.path,
        type: 'application/vnd.android.package-archive',
      );
      debugPrint('[VersionDetail] OpenFilex type=${result.type} message=${result.message}');
      if (result.type == ResultType.done) {
        _toast('已打开安装界面，请确认安装');
      } else {
        _toast(result.message.isNotEmpty ? result.message : '无法打开安装包');
      }
    } catch (e, st) {
      debugPrint('[VersionDetail] 更新失败: $e\n$st');
      _toast('更新失败：$e');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _downloadToFile(String url, File file) async {
    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(url));
      final streamed = await client.send(req).timeout(_downloadTimeout);
      if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
        throw Exception('HTTP ${streamed.statusCode}');
      }
      final sink = file.openWrite();
      try {
        await streamed.stream.pipe(sink).timeout(_downloadTimeout);
      } finally {
        await sink.close();
      }
      final len = await file.length();
      if (len <= 0) throw Exception('文件为空');
      debugPrint('[VersionDetail] 已写入 ${file.path} ($len bytes)');
    } finally {
      client.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final isCurrent = widget.version.versionNumber == VersionInfo.currentVersion;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          Container(
            color: colors.postCreate.topBarBg,
            child: SafeArea(
              bottom: false,
              child: SizedBox(
                height: AppDimens.settingsBarHeight,
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back, color: colors.common.barText),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Text(
                        'v${widget.version.versionNumber} ${widget.version.title}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w500,
                          color: colors.common.barText,
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.only(right: AppDimens.postCreateSubmitMarginRight),
                      child: SizedBox(
                        height: AppDimens.postCreateSubmitHeight,
                        child: ElevatedButton(
                          onPressed: isCurrent || _downloading ? null : _install,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: colors.postCreate.submitBg,
                            foregroundColor: colors.postCreate.submitText,
                            elevation: 0,
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            padding: EdgeInsets.symmetric(
                              horizontal: AppDimens.postCreateSubmitHPadding,
                              vertical: 0,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppDimens.postCreateSubmitRadius),
                            ),
                            textStyle: TextStyle(fontSize: AppDimens.postCreateSubmitFontSize),
                          ),
                          child: Text(
                            isCurrent ? '已是最新' : _downloading ? '下载中...' : '更新',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Text(
                widget.version.description.isNotEmpty ? widget.version.description : '暂无详细说明',
                style: TextStyle(
                  fontSize: 15,
                  color: colors.common.onSurface,
                  height: 1.7,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
