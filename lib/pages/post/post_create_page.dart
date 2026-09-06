import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config/post_limits.dart';
import '../../models/post.dart';
import '../../models/post_draft.dart';
import '../../widgets/app_confirm_dialog.dart';
import '../../widgets/image_overlay.dart';
import '../../widgets/live_pop_scope.dart';
import '../../models/upload_result.dart';
import '../../services/api.dart';
import '../../services/device_credential_store.dart';
import '../../services/session_service.dart';
import '../../services/storage.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../theme/moderation_feedback.dart';
import '../account/register_page.dart';
import '../settings/settings_navigation.dart';

class PostCreatePage extends StatefulWidget {
  const PostCreatePage({super.key});

  @override
  State<PostCreatePage> createState() => _PostCreatePageState();
}

class _PickedFile {
  final String path;
  final String name;
  final int bytes;

  const _PickedFile({
    required this.path,
    required this.name,
    required this.bytes,
  });
}

class _PostCreatePageState extends State<PostCreatePage>
    with SingleTickerProviderStateMixin {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _titleFocus = FocusNode();
  final _contentFocus = FocusNode();

  final List<_PickedFile> _images = [];
  List<GlobalKey> _previewKeys = [];
  _PickedFile? _attachment;
  final List<UploadResult> _uploadedImages = [];
  UploadResult? _uploadedAttachment;

  bool _titleState = false;
  bool _fileState = true;
  bool _uploading = false;
  bool _submitting = false;
  String? _errorMessage;
  Color? _errorColor;
  bool _hasAuthor = false;

  bool _titleFocused = false;
  bool _contentFocused = false;

  // 内容展开覆盖层
  final _contentFieldKey = GlobalKey();
  late final AnimationController _contentExpandCtrl;
  Rect? _contentStartRect;

  List<UploadResult> get _uploaded => [
    ..._uploadedImages,
    if (_uploadedAttachment != null) _uploadedAttachment!,
  ];

  @override
  void initState() {
    super.initState();
    SessionService.instance.ensureSession();
    _restoreDraftFromStorage();
    _contentExpandCtrl =
        AnimationController(
          vsync: this,
          duration: Duration(
            milliseconds: AppDimens.postCreateContentExpandAnimMs,
          ),
        )..addListener(() {
          if (mounted) setState(() {});
        });
    _titleController.addListener(() {
      final v = _titleController.text.trim().isNotEmpty;
      if (v != _titleState && mounted) setState(() => _titleState = v);
    });
    _contentController.addListener(() {
      if (mounted) setState(() {});
    });
    _titleFocus.addListener(
      () => setState(() => _titleFocused = _titleFocus.hasFocus),
    );
    _contentFocus.addListener(
      () => setState(() => _contentFocused = _contentFocus.hasFocus),
    );
  }

  Timer? _errorTimer;

  void _setError(String? msg, {Color color = Colors.transparent}) {
    _errorTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _errorMessage = msg;
      _errorColor = color == Colors.transparent ? null : color;
    });
    if (msg != null) {
      _errorTimer = Timer(
        Duration(milliseconds: AppDimens.postCreateErrorDismissMs),
        () {
          if (mounted) {
            setState(() {
              _errorMessage = null;
              _errorColor = null;
            });
          }
        },
      );
    }
  }

  @override
  void dispose() {
    _errorTimer?.cancel();
    _contentExpandCtrl.dispose();
    _titleController.dispose();
    _contentController.dispose();
    _titleFocus.dispose();
    _contentFocus.dispose();
    super.dispose();
  }

  // ---- 上传文件（合并按钮）----

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const [
        'jpg',
        'jpeg',
        'png',
        'gif',
        'asc',
        'txt',
        'log',
        'conf',
        'nfo',
        'me',
        'tsv',
        'ics',
        'vcs',
        'vcf',
        'c',
        'h',
        'cpp',
        'cxx',
        'py',
        'java',
        'prel',
        'pl',
        'lua',
        'yaml',
        'yml',
        'kt',
      ],
      withData: false,
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty) return;

    final pickedImages = <_PickedFile>[];
    _PickedFile? pickedAttachment;
    bool hasUnknown = false;

    for (final f in result.files) {
      final path = f.path;
      final name = f.name;
      if (path == null) continue;
      final ext = name.split('.').last.toLowerCase();
      if (['jpg', 'jpeg', 'png', 'gif'].contains(ext)) {
        pickedImages.add(_PickedFile(path: path, name: name, bytes: f.size));
      } else if ([
        'asc',
        'txt',
        'log',
        'conf',
        'nfo',
        'me',
        'tsv',
        'ics',
        'vcs',
        'vcf',
        'c',
        'h',
        'cpp',
        'cxx',
        'py',
        'java',
        'prel',
        'pl',
        'lua',
        'yaml',
        'yml',
        'kt',
      ].contains(ext)) {
        if (pickedAttachment != null) {
          hasUnknown = true; // 多个附件 — 只保留第一个
        } else {
          pickedAttachment = _PickedFile(path: path, name: name, bytes: f.size);
        }
      } else {
        hasUnknown = true;
      }
    }

    if (pickedImages.isEmpty && pickedAttachment == null) {
      if (hasUnknown) _setError('不支持的文件类型');
      return;
    }

    // 校验图片
    final totalImages = pickedImages.length + _images.length;
    if (totalImages > PostLimits.imageMaxCount) {
      _setError('!上传的图像过多，上限为12张');
      return;
    }
    final currentSize = _images.fold<double>(0, (s, e) => s + e.bytes);
    final newImgSize = pickedImages.fold<double>(0, (s, e) => s + e.bytes);
    if ((currentSize + newImgSize) / 1024 / 1024 > PostLimits.imageMaxTotalMb) {
      _setError('!图片总大小超过8MB');
      return;
    }

    // 校验附件
    if (pickedAttachment != null &&
        pickedAttachment.bytes / 1024 / 1024 > PostLimits.attachmentMaxMb) {
      _setError('附件不能超过 3.5MB');
      return;
    }

    setState(() {
      _images.addAll(pickedImages);
      if (pickedAttachment != null) {
        _attachment = pickedAttachment;
        _uploadedAttachment = null;
      }
      _fileState = false;
      _uploading = true;
      _errorMessage = null;
    });

    // 上传不带 session / user_id（后端 DTO 禁止）；归属在发帖 v2 时由 session 落库
    // 并行上传。targets 与 futures 一一对应，用于完成回调中判断该文件
    // 是否仍被保留（上传期间用户可能已点叉删除，避免删除的结果“复活”）
    final targets = <_PickedFile>[];
    final futures = <Future<UploadResult?>>[];
    for (final img in pickedImages) {
      targets.add(img);
      futures.add(ApiService.uploadFile(PostUploadType.image, File(img.path)));
    }
    if (pickedAttachment != null) {
      targets.add(pickedAttachment);
      futures.add(
        ApiService.uploadFile(
          PostUploadType.attachment,
          File(pickedAttachment.path),
        ),
      );
    }

    final results = await Future.wait(futures);
    if (!mounted) return;

    final failed = results.any((e) => e == null);
    if (failed) {
      setState(() {
        _fileState = false;
        _uploading = false;
      });
      _setError(getModerationMessage(ApiService.lastError ?? '上传失败，请重试'));
      return;
    }

    setState(() {
      for (var i = 0; i < results.length; i++) {
        final r = results[i];
        if (r == null) continue;
        final target = targets[i];
        if (r.type == PostUploadType.image) {
          // 上传期间已被用户删除的图片不再登记（identity 比较，同名图不误删）
          if (_images.any((e) => identical(e, target))) {
            _uploadedImages.add(r);
          }
        } else if (identical(_attachment, target)) {
          _uploadedAttachment = r;
        }
      }
      _fileState = true;
      _uploading = false;
    });
  }

  void _removeImage(int index) {
    HapticFeedback.lightImpact();
    setState(() {
      final removed = _images.removeAt(index);
      _uploadedImages.removeWhere((r) => r.original == removed.name);
      if (_previewKeys.length == _images.length + 1) {
        _previewKeys.removeAt(index);
      } else {
        _previewKeys = List.generate(_images.length, (_) => GlobalKey());
      }
      if (_images.isEmpty && _attachment == null) {
        _fileState = true;
      }
    });
  }

  void _removeAttachment() {
    HapticFeedback.lightImpact();
    setState(() {
      _attachment = null;
      _uploadedAttachment = null;
      if (_images.isEmpty) _fileState = true;
    });
  }

  void _clearAll() {
    HapticFeedback.lightImpact();
    setState(() {
      _images.clear();
      _attachment = null;
      _uploadedImages.clear();
      _uploadedAttachment = null;
      _previewKeys = [];
      _fileState = true;
      _errorMessage = null;
    });
  }

  void _toggleAuthor() {
    HapticFeedback.lightImpact();
    setState(() {
      _hasAuthor = !_hasAuthor;
    });
    _errorTimer?.cancel();
    final msg = _hasAuthor ? '开启署名' : '关闭署名';
    if (mounted) {
      setState(() {
        _errorMessage = msg;
        _errorColor = Theme.of(
          context,
        ).extension<AppColors>()!.postCreate.bottomHintText;
      });
    }
    _errorTimer = Timer(
      Duration(milliseconds: AppDimens.postCreateToastDismissMs),
      () {
        if (mounted) {
          setState(() {
            _errorMessage = null;
            _errorColor = null;
          });
        }
      },
    );
  }

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      _setError('标题不能为空');
      return;
    }
    if (!_titleState || !_fileState || _uploading || _submitting) return;

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    // v2 发帖：session 必带；署名作者由后端按 session 解析，body 不带 author / user_id
    final sessionId = await DeviceCredentialStore.getSessionId();
    final sessionSecret = await DeviceCredentialStore.getSessionSecret();
    if (sessionId == null ||
        sessionSecret == null ||
        sessionSecret.isEmpty) {
      setState(() => _submitting = false);
      _setError('登录状态已失效，请重新登录');
      return;
    }
    final draft = PostDraft(
      title: title,
      content: _contentController.text,
      isAnonymous: !_hasAuthor,
      uploaded: _uploaded,
    );

    final post = await ApiService.createPost(
      draft,
      sessionId: sessionId,
      sessionSecret: sessionSecret,
    );
    if (!mounted) return;

    setState(() => _submitting = false);
    if (post == null) {
      _setError(getModerationMessage(ApiService.lastError ?? '发布失败'));
      return;
    }
    HapticFeedback.mediumImpact();
    await PostStorage.clearPostDraft();
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  void _openContentEditor() {
    final renderBox =
        _contentFieldKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    _contentStartRect = offset & size;
    _contentExpandCtrl.forward();
    setState(() {});
  }

  void _closeContentEditor() {
    _contentExpandCtrl.reverse();
    setState(() {});
  }

  // ---- 退出与本地暂存草稿 ----

  bool _exitPromptShowing = false;

  /// 有未提交的输入内容（标题/正文/图片/附件任一）即视为可暂存
  bool get _hasDraftContent =>
      _titleController.text.trim().isNotEmpty ||
      _contentController.text.trim().isNotEmpty ||
      _images.isNotEmpty ||
      _attachment != null;

  Map<String, dynamic> _draftToMap() => {
    'title': _titleController.text,
    'content': _contentController.text,
    'has_author': _hasAuthor,
    'images': _images
        .map((e) => {'path': e.path, 'name': e.name, 'bytes': e.bytes})
        .toList(),
    'attachment': _attachment == null
        ? null
        : {
            'path': _attachment!.path,
            'name': _attachment!.name,
            'bytes': _attachment!.bytes,
          },
    // 发布时用的是上传结果而非本地文件，必须一并暂存
    'uploaded_images': _uploadedImages.map((e) => e.toJson()).toList(),
    'uploaded_attachment': _uploadedAttachment?.toJson(),
  };

  void _restoreDraftFromStorage() {
    final draft = PostStorage.getPostDraft();
    if (draft == null) return;
    final title = (draft['title'] ?? '') as String;
    final content = (draft['content'] ?? '') as String;
    final images = <_PickedFile>[];
    for (final raw in (draft['images'] as List? ?? const [])) {
      final map = Map<String, dynamic>.from(raw as Map);
      if (File(map['path'] as String).existsSync()) {
        images.add(
          _PickedFile(
            path: map['path'] as String,
            name: map['name'] as String,
            bytes: (map['bytes'] ?? 0) as int,
          ),
        );
      }
    }
    final attRaw = draft['attachment'] as Map?;
    _PickedFile? attachment;
    if (attRaw != null) {
      final map = Map<String, dynamic>.from(attRaw);
      if (File(map['path'] as String).existsSync()) {
        attachment = _PickedFile(
          path: map['path'] as String,
          name: map['name'] as String,
          bytes: (map['bytes'] ?? 0) as int,
        );
      }
    }
    if (title.isEmpty &&
        content.isEmpty &&
        images.isEmpty &&
        attachment == null) {
      return;
    }
    _titleController.text = title;
    _contentController.text = content;
    _hasAuthor = (draft['has_author'] ?? false) as bool;
    _images.addAll(images);
    _previewKeys = List.generate(_images.length, (_) => GlobalKey());
    _attachment = attachment;

    // 恢复已上传结果：按文件名与本地文件配对，避免发布时丢图
    final uploadedByName = <String, UploadResult>{};
    for (final raw in (draft['uploaded_images'] as List? ?? const [])) {
      final result = UploadResult.fromJson(
        Map<String, dynamic>.from(raw as Map),
      );
      uploadedByName[result.original] = result;
    }
    for (final img in images) {
      final result = uploadedByName[img.name];
      if (result != null) _uploadedImages.add(result);
    }
    final attUpRaw = draft['uploaded_attachment'] as Map?;
    if (attUpRaw != null && attachment != null) {
      final result = UploadResult.fromJson(Map<String, dynamic>.from(attUpRaw));
      if (result.original == attachment.name) _uploadedAttachment = result;
    }

    // 配不上的（如旧版本草稿没存上传结果）→ 进入页面后自动补传
    final orphanImages = images
        .where((img) => !_uploadedImages.any((r) => r.original == img.name))
        .toList();
    final orphanAttachment = attachment != null && _uploadedAttachment == null
        ? attachment
        : null;
    if (orphanImages.isNotEmpty || orphanAttachment != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reuploadRestored(orphanImages, orphanAttachment);
      });
    }
  }

  /// 补传恢复草稿时缺失上传结果的文件（复用选图后的上传状态展示）
  Future<void> _reuploadRestored(
    List<_PickedFile> images,
    _PickedFile? attachment,
  ) async {
    setState(() {
      _fileState = false;
      _uploading = true;
      _errorMessage = null;
    });
    // targets 与 futures 一一对应；补传期间用户也可能删除文件，完成时按
    // identity 校验该文件是否仍被保留，避免已删除的上传结果“复活”
    final targets = <_PickedFile>[...images, if (attachment != null) attachment];
    final futures = <Future<UploadResult?>>[
      for (final img in images)
        ApiService.uploadFile(PostUploadType.image, File(img.path)),
      if (attachment != null)
        ApiService.uploadFile(
          PostUploadType.attachment,
          File(attachment.path),
        ),
    ];
    final results = await Future.wait(futures);
    if (!mounted) return;
    final failed = results.any((e) => e == null);
    if (failed) {
      setState(() => _uploading = false);
      _setError(getModerationMessage(ApiService.lastError ?? '上传失败，请重试'));
      return;
    }
    setState(() {
      _uploading = false;
      for (var i = 0; i < results.length; i++) {
        final r = results[i];
        if (r == null) continue;
        final target = targets[i];
        if (r.type == PostUploadType.image) {
          if (_images.any((e) => identical(e, target))) {
            _uploadedImages.add(r);
          }
        } else if (identical(_attachment, target)) {
          _uploadedAttachment = r;
        }
      }
      _fileState = true;
    });
  }

  /// 退出意图统一入口：返回手势、返回键、顶栏关闭按钮都走这里。
  /// 预览打开 → 先关预览；编辑器展开 → 先收起；有未提交内容 → 询问暂存。
  Future<void> _handleExitIntent() async {
    if (ImageOverlay.currentEntry != null) {
      ImageOverlay.closeCurrent();
      return;
    }
    if (_contentExpandCtrl.isCompleted) {
      _closeContentEditor();
      return;
    }
    if (_exitPromptShowing) return;
    if (!_hasDraftContent) {
      Navigator.pop(context);
      return;
    }
    _exitPromptShowing = true;
    final save = await showAppConfirmDialog(
      context,
      message: '是否暂存输入的内容于本地？下次进入发帖页时将自动恢复。',
      cancelText: '不暂存',
      confirmText: '暂存',
    );
    _exitPromptShowing = false;
    if (!mounted) return;
    if (save == null) return; // 点弹窗外部关闭 → 留在本页
    if (save) {
      await PostStorage.savePostDraft(_draftToMap());
    } else {
      await PostStorage.clearPostDraft();
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final canSubmit = _titleState && _fileState && !_uploading && !_submitting;
    final hasFiles = _images.isNotEmpty || _attachment != null;
    final needsExpand =
        _contentController.text.length >
        AppDimens.postCreateExpandThresholdChars;

    // canPop 实时求值：预览打开时返回只关预览；内容编辑器展开时先收起；
    // 有未提交内容时弹出暂存询问。真正的退出动作统一走 _handleExitIntent
    return LivePopScope(
      recomputeTrigger: ImageOverlay.isOpen,
      canPop: () =>
          ImageOverlay.currentEntry == null &&
          !_contentExpandCtrl.isCompleted &&
          !_hasDraftContent,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleExitIntent();
      },
      child: Scaffold(
        backgroundColor: colors.postCreate.pageBg,
        body: Stack(
          children: [
            Column(
              children: [
                _topBar(colors, canSubmit),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () {
                      _titleFocus.unfocus();
                      _contentFocus.unfocus();
                    },
                    child: ListView(
                      padding: EdgeInsets.symmetric(
                        vertical: AppDimens.postCreatePagePadding,
                      ),
                      children: [
                        // 第一部分：椭圆输入区
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: AppDimens.postCreatePagePadding,
                          ),
                          child: _inputCard(colors),
                        ),
                        SizedBox(height: AppDimens.postCreateSectionGap),
                        // 预览区（与内容栏同距屏幕边缘）
                        if (hasFiles)
                          Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: AppDimens.postCreatePagePadding,
                            ),
                            child: _previewArea(colors),
                          ),
                        if (hasFiles)
                          Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: AppDimens.postCreatePagePadding,
                            ),
                            child: Container(
                              height: AppDimens.postCreatePreviewDividerHeight,
                              color: colors.postCreate.previewDivider,
                            ),
                          ),
                        SizedBox(height: AppDimens.postCreatePreviewGap),
                        // 第二部分：按钮行
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: AppDimens.postCreateButtonRowPaddingH,
                          ),
                          child: _buttonRow(colors, hasFiles, needsExpand),
                        ),
                        if (_errorMessage != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: _error(colors),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            // 内容展开覆盖层
            _buildContentExpandOverlay(colors),
          ],
        ),
      ),
    );
  }

  Widget _buildContentExpandOverlay(AppColors colors) {
    final isExpanding =
        _contentExpandCtrl.isAnimating || _contentExpandCtrl.isCompleted;
    if (!isExpanding && !_contentExpandCtrl.isCompleted) {
      return const SizedBox.shrink();
    }

    final progress = _contentExpandCtrl.value;
    final screenSize = MediaQuery.of(context).size;
    final safeTop = MediaQuery.of(context).padding.top;
    final topBarH = AppDimens.settingsBarHeight + safeTop;

    final startRect = _contentStartRect ?? Rect.zero;
    final endRect = Rect.fromLTRB(
      0,
      topBarH + AppDimens.postCreateContentExpandedTopGap,
      screenSize.width,
      screenSize.height,
    );

    final currentRect = Rect.lerp(startRect, endRect, progress)!;
    final overlayOpacity = progress * AppDimens.postCreateContentOverlayOpacity;
    // 进度 < 8% 时保持原宽度（展开开头/收起末尾），>= 8% 切到目标宽度
    final textPadding =
        progress < AppDimens.postCreateContentCollapseWidthSwitchT
        ? AppDimens.postCreateContentExpandedTextHPadding
        : 0.0;

    return Stack(
      children: [
        // 遮罩
        Positioned.fill(
          child: GestureDetector(
            onTap: _closeContentEditor,
            child: AnimatedContainer(
              duration: Duration.zero,
              color: colors.postCreate.contentOverlay.withValues(
                alpha: overlayOpacity,
              ),
            ),
          ),
        ),
        // 展开卡片 — 用 OverflowBox 固定文字宽度 + ClipRect 裁剪动画
        Positioned(
          left: currentRect.left,
          top: currentRect.top,
          height: currentRect.height,
          right: endRect.width - currentRect.width - currentRect.left,
          child: ClipRect(
            child: OverflowBox(
              minWidth: endRect.width,
              maxWidth: endRect.width,
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: endRect.width,
                height: endRect.height,
                child: GestureDetector(
                  onTap: () {},
                  child: Container(
                    decoration: BoxDecoration(
                      color: colors.postCreate.fieldBg,
                      borderRadius: BorderRadius.circular(
                        AppDimens.postCreateContentExpandedRadius,
                      ),
                    ),
                    clipBehavior: Clip.hardEdge,
                    child: Stack(
                      children: [
                        // 文本顶部位置平滑动画：从贴近顶部过渡到按钮下方
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            AppDimens.postCreateContentExpandedTextLeftEnd +
                                textPadding,
                            AppDimens.postCreateContentExpandedTextTopStart +
                                (AppDimens.settingsBarHeight -
                                        AppDimens
                                            .postCreateContentExpandedTextTopStart) *
                                    progress,
                            AppDimens.postCreateContentExpandedPadding +
                                textPadding,
                            AppDimens.postCreateContentExpandedPadding + 8,
                          ),
                          child: TextField(
                            controller: _contentController,
                            autofocus: true,
                            maxLines: null,
                            expands: true,
                            textAlignVertical: TextAlignVertical.top,
                            cursorColor: colors.common.onSurface,
                            style: const TextStyle(
                              fontSize:
                                  AppDimens.postCreateContentLabelFontSizeLarge,
                              color: null,
                              height: 1.5,
                            ),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                              hintText: '请输入内容...',
                            ),
                          ),
                        ),
                        // 收起按钮浮动在文本之上，不占文档流
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: AnimatedOpacity(
                            opacity: progress > 0.5 ? 1.0 : 0.0,
                            duration: Duration.zero,
                            child: SizedBox(
                              height: AppDimens.settingsBarHeight,
                              child: Row(
                                children: [
                                  IconButton(
                                    icon: Icon(
                                      Icons.keyboard_arrow_down,
                                      size: AppDimens
                                          .postCreateContentCollapseIconSize,
                                      color:
                                          colors.postCreate.contentCollapseIcon,
                                    ),
                                    onPressed: _closeContentEditor,
                                  ),
                                  const Spacer(),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _topBar(AppColors colors, bool canSubmit) {
    return Container(
      color: colors.postCreate.topBarBg,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: AppDimens.settingsBarHeight,
          child: Row(
            children: [
              IconButton(
                icon: Icon(
                  Icons.keyboard_arrow_up,
                  color: colors.common.barText,
                ),
                onPressed: _handleExitIntent,
              ),
              const Spacer(),
              Padding(
                padding: EdgeInsets.only(
                  right: AppDimens.postCreateSubmitMarginRight,
                ),
                child: _submitButton(canSubmit),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _error(AppColors colors) {
    return Center(
      child: Text(
        _errorMessage!,
        style: TextStyle(
          color: _errorColor ?? colors.postCreate.errorText,
          fontSize: 14,
        ),
      ),
    );
  }

  // ---- 第一部分：椭圆输入区 ----

  Widget _inputCard(AppColors colors) {
    return Container(
      decoration: BoxDecoration(
        color: colors.postCreate.fieldBg,
        borderRadius: BorderRadius.circular(AppDimens.postCreateInputRadius),
        border: AppDimens.postCreateInputBorderWidth > 0
            ? Border.all(
                color: colors.postCreate.divider,
                width: AppDimens.postCreateInputBorderWidth,
              )
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 标题
          _titleField(colors),
          // 分隔线
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppDimens.postCreateDividerIndent,
            ),
            child: Container(
              height: AppDimens.postCreateDividerThickness,
              color: colors.postCreate.divider,
            ),
          ),
          // 内容
          _contentField(colors, key: _contentFieldKey),
        ],
      ),
    );
  }

  Widget _titleField(AppColors colors) {
    final hasText = _titleController.text.isNotEmpty;
    final float = _titleFocused || hasText;
    final animMs = AppDimens.postCreateLabelAnimMs;
    final curve = Curves.easeOut;
    return GestureDetector(
      onTap: () async {
        if (PostStorage.isRegistered()) {
          _titleFocus.requestFocus();
        } else {
          await Navigator.of(context).push(bottomUpRoute(const RegisterPage()));
          if (mounted) setState(() {});
        }
      },
      child: Container(
        height: AppDimens.postCreateTitleMinHeight,
        padding: EdgeInsets.symmetric(
          horizontal: AppDimens.postCreateInputPaddingH,
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // label：始终存在，动画变化位置和字号
            AnimatedPositioned(
              duration: Duration(milliseconds: animMs),
              curve: curve,
              left: AppDimens.postCreateLabelFloatDx,
              top: float
                  ? AppDimens.postCreateLabelFloatDy + 12
                  : AppDimens.postCreateLabelRestDy +
                        (AppDimens.postCreateTitleMinHeight - 20) / 2 -
                        12,
              child: AnimatedDefaultTextStyle(
                duration: Duration(milliseconds: animMs),
                curve: curve,
                style: TextStyle(
                  fontSize: float
                      ? AppDimens.postCreateLabelFontSizeSmall
                      : AppDimens.postCreateLabelFontSizeLarge,
                  color: float
                      ? colors.postCreate.titleLabelFloat
                      : colors.postCreate.titleLabelRest,
                ),
                child: Text(PostStorage.isRegistered() ? '标题' : '请注册'),
              ),
            ),
            // TextField：只在已注册时渲染
            if (PostStorage.isRegistered())
              AnimatedPositioned(
                duration: Duration(milliseconds: animMs),
                curve: curve,
                left: 0,
                right: 0,
                top: float
                    ? AppDimens.postCreateLabelFloatDy + 28
                    : AppDimens.postCreateLabelRestDy + 14,
                child: TextField(
                  controller: _titleController,
                  focusNode: _titleFocus,
                  cursorColor: colors.common.onSurface,
                  style: TextStyle(
                    fontSize: AppDimens.postCreateLabelFontSizeLarge,
                    color: colors.common.onSurface,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _contentField(AppColors colors, {Key? key}) {
    final hasText = _contentController.text.isNotEmpty;
    final float = _contentFocused || hasText;
    final animMs = AppDimens.postCreateContentLabelAnimMs;
    final curve = Curves.easeOut;
    final topMargin = float
        ? AppDimens.postCreateContentLabelFloatDy + 22
        : (AppDimens.postCreateContentLabelRestDy + 14)
              .clamp(0.0, double.infinity)
              .toDouble();

    return GestureDetector(
      onTap: () async {
        if (PostStorage.isRegistered()) {
          _contentFocus.requestFocus();
        } else {
          await Navigator.of(context).push(bottomUpRoute(const RegisterPage()));
          if (mounted) setState(() {});
        }
      },
      child: Container(
        key: key,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final textWidth =
                constraints.maxWidth - AppDimens.postCreateInputPaddingH * 2;
            final height = _contentFieldHeight(textWidth, topMargin);
            final textHeight =
                (height - topMargin - AppDimens.postCreateInputPaddingV * 2)
                    .clamp(24.0, AppDimens.postCreateContentMaxHeight)
                    .toDouble();

            return AnimatedContainer(
              duration: Duration(milliseconds: animMs),
              curve: curve,
              height: height,
              padding: EdgeInsets.fromLTRB(
                AppDimens.postCreateInputPaddingH,
                AppDimens.postCreateInputPaddingV,
                AppDimens.postCreateInputPaddingH,
                AppDimens.postCreateInputPaddingV,
              ),
              clipBehavior: Clip.hardEdge,
              decoration: const BoxDecoration(),
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  AnimatedPositioned(
                    duration: Duration(milliseconds: animMs),
                    curve: curve,
                    left: AppDimens.postCreateContentLabelFloatDx,
                    top: float
                        ? AppDimens.postCreateContentLabelFloatDy + 8
                        : AppDimens.postCreateContentLabelRestDy +
                              (AppDimens.postCreateContentMinHeight - 20) / 2 -
                              12,
                    child: AnimatedDefaultTextStyle(
                      duration: Duration(milliseconds: animMs),
                      curve: curve,
                      style: TextStyle(
                        fontSize: float
                            ? AppDimens.postCreateContentLabelFontSizeSmall
                            : AppDimens.postCreateContentLabelFontSizeLarge,
                        color: float
                            ? colors.postCreate.contentLabelFloat
                            : colors.postCreate.contentLabelRest,
                      ),
                      child: Text(
                        PostStorage.isRegistered() ? '内容' : '目前未绑定账号',
                      ),
                    ),
                  ),
                  if (PostStorage.isRegistered())
                    AnimatedPositioned(
                      duration: Duration(milliseconds: animMs),
                      curve: curve,
                      left: 0,
                      right: 0,
                      top: topMargin,
                      child: SizedBox(
                        height: textHeight,
                        child: TextField(
                          controller: _contentController,
                          focusNode: _contentFocus,
                          cursorColor: colors.common.onSurface,
                          keyboardType: TextInputType.multiline,
                          maxLines: null,
                          expands: true,
                          textAlignVertical: TextAlignVertical.top,
                          style: TextStyle(
                            fontSize:
                                AppDimens.postCreateContentLabelFontSizeLarge,
                            color: colors.common.onSurface,
                            height: 1.4,
                          ),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  double _contentFieldHeight(double textWidth, double topMargin) {
    if (_contentController.text.isEmpty) {
      return AppDimens.postCreateContentMinHeight;
    }

    final painter = TextPainter(
      text: TextSpan(
        text: _contentController.text,
        style: const TextStyle(
          fontSize: AppDimens.postCreateContentLabelFontSizeLarge,
          height: 1.4,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: textWidth.clamp(1.0, double.infinity));

    final wantedHeight =
        topMargin + painter.height + AppDimens.postCreateInputPaddingV * 2 + 16;
    return wantedHeight.clamp(
      AppDimens.postCreateContentMinHeight,
      AppDimens.postCreateContentMaxHeight,
    );
  }

  // ---- 预览区 ----

  Widget _previewArea(AppColors colors) {
    if (_images.isEmpty && _attachment == null) return const SizedBox.shrink();
    final widgets = <Widget>[];
    if (_images.isNotEmpty) {
      if (_previewKeys.length != _images.length) {
        _previewKeys = List.generate(_images.length, (_) => GlobalKey());
      }
      widgets.add(
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: _images.asMap().entries.map((entry) {
            final index = entry.key;
            final img = entry.value;
            return _PreviewThumb(
              key: _previewKeys[index],
              path: img.path,
              onRemove: () => _removeImage(index),
              onTap: () => _openImageOverlay(index),
            );
          }).toList(),
        ),
      );
    }
    if (_attachment != null) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              const Icon(Icons.description_outlined, size: 18),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  _attachment!.name,
                  style: TextStyle(
                    fontSize: 14,
                    color: colors.common.secondary,
                  ),
                ),
              ),
              GestureDetector(
                onTap: _removeAttachment,
                child: Icon(
                  Icons.close,
                  size: 18,
                  color: colors.common.secondary,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.only(bottom: AppDimens.postCreatePreviewGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: widgets,
      ),
    );
  }

  void _openImageOverlay(int index) {
    if (_images.isEmpty || ImageOverlay.currentEntry != null) return;
    final imageList = _images
        .map((img) => PostImage(fileName: img.name))
        .toList();
    final rects = <Rect?>[];
    for (final key in _previewKeys) {
      final box = key.currentContext?.findRenderObject() as RenderBox?;
      if (box == null) {
        rects.add(null);
        continue;
      }
      final offset = box.localToGlobal(Offset.zero);
      final size = box.size;
      rects.add(Rect.fromLTWH(offset.dx, offset.dy, size.width, size.height));
    }
    while (rects.length <= index) {
      rects.add(null);
    }
    // 本地图片：缓存到 Hive 缩略图，使 ImageOverlay 可以直接找到
    final thumbs = <Uint8List?>[];
    for (final img in _images) {
      final bytes = PostStorage.getThumbnail(img.name)?.bytes;
      if (bytes != null) {
        thumbs.add(bytes);
      } else {
        // 从本地文件读取并缓存
        final fileBytes = File(img.path).readAsBytesSync();
        PostStorage.saveThumbnail(
          img.name,
          ThumbnailData(bytes: fileBytes, width: 0, height: 0),
        );
        thumbs.add(fileBytes);
      }
    }
    final overlay = Overlay.of(context);
    ImageOverlay.currentEntry = OverlayEntry(
      builder: (_) {
        return ImageOverlay(
          images: imageList,
          initialIndex: index,
          thumbRects: rects,
          thumbnails: thumbs,
        );
      },
    );
    overlay.insert(ImageOverlay.currentEntry!);
  }

  // ---- 第二部分：按钮行 ----

  Widget _buttonRow(AppColors colors, bool hasFiles, bool needsExpand) {
    final registered = PostStorage.isRegistered();
    return Row(
      children: [
        if (registered)
          _iconOnlyButton(
            icon: Icons.upload_file,
            onTap: _uploading ? null : _pickFiles,
            iconColor: colors.postCreate.uploadBtnIcon,
            fillColor: colors.postCreate.fieldBg,
            borderColor: colors.postCreate.uploadBtnBorder,
          ),
        if (registered) SizedBox(width: AppDimens.postCreateActionRowGap),
        if (hasFiles)
          _iconOnlyButton(
            icon: Icons.delete_outline,
            onTap: _clearAll,
            iconColor: colors.postCreate.deleteBtnIcon,
            fillColor: colors.postCreate.fieldBg,
            borderColor: colors.postCreate.deleteBtnBorder,
          ),
        if (hasFiles) SizedBox(width: AppDimens.postCreateActionRowGap),
        const Spacer(),
        if (needsExpand) _expandButton(colors),
        if (needsExpand) SizedBox(width: AppDimens.postCreateActionRowGap),
        _iconOnlyButton(
          icon: _hasAuthor ? Icons.person : Icons.person_outline,
          onTap: _toggleAuthor,
          iconColor: _hasAuthor
              ? colors.postCreate.authorActiveIcon
              : colors.postCreate.authorIcon,
          fillColor: _hasAuthor
              ? colors.postCreate.authorActiveFill
              : colors.postCreate.fieldBg,
          borderColor: _hasAuthor
              ? colors.postCreate.authorActiveFill
              : colors.postCreate.authorBorder,
        ),
      ],
    );
  }

  Widget _iconOnlyButton({
    required IconData icon,
    required VoidCallback? onTap,
    required Color iconColor,
    required Color fillColor,
    required Color borderColor,
    double? size,
    double? radius,
    double? borderWidth,
    double? iconSize,
  }) {
    final w = size ?? AppDimens.postCreateActionButtonSize;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: w,
        height: w,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(
            radius ?? AppDimens.postCreateActionButtonRadius,
          ),
          color: fillColor,
          border: Border.all(
            color: borderColor,
            width: borderWidth ?? AppDimens.postCreateActionButtonBorderWidth,
          ),
        ),
        child: Icon(
          icon,
          size: iconSize ?? AppDimens.postCreateActionButtonIconSize,
          color: iconColor,
        ),
      ),
    );
  }

  Widget _expandButton(AppColors colors) {
    return _iconOnlyButton(
      icon: Icons.crop_free,
      onTap: _openContentEditor,
      iconColor: colors.postCreate.expandBtnIcon,
      fillColor: colors.postCreate.fieldBg,
      borderColor: colors.postCreate.expandBtnBorder,
      size: AppDimens.postCreateExpandButtonSize,
      radius: AppDimens.postCreateExpandButtonRadius,
      borderWidth: AppDimens.postCreateExpandButtonBorderWidth,
      iconSize: AppDimens.postCreateExpandButtonIconSize,
    );
  }

  // ---- 第三部分：发布按钮 ----

  Widget _submitButton(bool canSubmit) {
    return SizedBox(
      height: AppDimens.postCreateSubmitHeight,
      child: ElevatedButton(
        onPressed: canSubmit ? _submit : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: Theme.of(
            context,
          ).extension<AppColors>()!.postCreate.submitBg,
          foregroundColor: Theme.of(
            context,
          ).extension<AppColors>()!.postCreate.submitText,
          elevation: 0,
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: EdgeInsets.symmetric(
            horizontal: AppDimens.postCreateSubmitHPadding,
            vertical: 0,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              AppDimens.postCreateSubmitRadius,
            ),
          ),
          textStyle: TextStyle(fontSize: AppDimens.postCreateSubmitFontSize),
        ),
        child: _submitting || _uploading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Text('发布'),
      ),
    );
  }
}

class _PreviewThumb extends StatelessWidget {
  final String path;
  final VoidCallback onRemove;
  final VoidCallback onTap;

  const _PreviewThumb({
    super.key,
    required this.path,
    required this.onRemove,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        children: [
          SizedBox(
            width: AppDimens.postCreatePreviewThumbSize,
            height: AppDimens.postCreatePreviewThumbSize,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.file(File(path), fit: BoxFit.cover),
            ),
          ),
          Positioned(
            top: 2,
            right: 2,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: colors.common.surface.withValues(alpha: 0.85),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.close,
                  size: 12,
                  color: colors.common.onSurface,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
