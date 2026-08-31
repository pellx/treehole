import 'package:flutter/material.dart';

// ============================================================
//  CommonColors — 全局通用颜色
// ============================================================
class CommonColors {
  final Color background;
  final Color surface;
  final Color onSurface;
  final Color secondary;
  final Color authorColor;
  final Color accentText;
  final Color buttonBg;
  final Color green;
  final Color attachment;
  final Color divider;
  final Color trailingIcon;
  final Color arrowIcon;
  final Color barText;
  final Color expandIconActive;
  final Color switchActive;
  final Color borderColor;
  final Color idTint;
  final Color drawerHeaderBg;
  final Color overlayActionBarBg;
  final Color overlayIcon;
  final Color overlayPageDot;
  final Color updateArrow;
  final Color deviceDeleteIcon;
  /// 主设备星标（与帖子收藏同款 SVG，黄色）
  final Color devicePrimaryStar;

  const CommonColors({
    required this.background,
    required this.surface,
    required this.onSurface,
    required this.secondary,
    required this.authorColor,
    required this.accentText,
    required this.buttonBg,
    required this.green,
    required this.attachment,
    required this.divider,
    required this.trailingIcon,
    required this.arrowIcon,
    required this.barText,
    required this.expandIconActive,
    required this.switchActive,
    required this.borderColor,
    required this.idTint,
    required this.drawerHeaderBg,
    required this.overlayActionBarBg,
    required this.overlayIcon,
    required this.overlayPageDot,
    required this.updateArrow,
    required this.deviceDeleteIcon,
    required this.devicePrimaryStar,
  });
}

// ============================================================
//  PostCardColors — 帖子卡片专属颜色
// ============================================================
class PostCardColors {
  final Color cardBorder;
  final Color bodyDivider;
  final Color title;
  final Color content;
  final Color dateText;
  final Color remainCount;
  final Color authorName;
  final Color atSymbol;
  final Color attachmentText;
  final Color commentContent;
  final Color commentAuthor;
  final Color commentDate;
  final Color commentRemain;
  final Color commentBg;
  final Color commentIcon;
  final Color commentDateSeparatorLine;
  final Color commentInputBarBg;
  final Color commentInputFieldBg;
  final Color commentSendActiveBg;
  final Color commentSendActiveIcon;
  final Color commentSendInactiveBg;
  final Color commentSendInactiveBorder;
  final Color commentSendInactiveIcon;
  final Color expandIconBlue;
  final Color expandIconGray;
  final Color dotsButtonBg;
  final Color actionMenuBg;
  final Color actionBtnText;
  final Color idTint;
  final Color idErrorFallback;

  const PostCardColors({
    required this.cardBorder,
    required this.bodyDivider,
    required this.title,
    required this.content,
    required this.dateText,
    required this.remainCount,
    required this.authorName,
    required this.atSymbol,
    required this.attachmentText,
    required this.commentContent,
    required this.commentAuthor,
    required this.commentDate,
    required this.commentRemain,
    required this.commentBg,
    required this.commentIcon,
    required this.commentDateSeparatorLine,
    required this.commentInputBarBg,
    required this.commentInputFieldBg,
    required this.commentSendActiveBg,
    required this.commentSendActiveIcon,
    required this.commentSendInactiveBg,
    required this.commentSendInactiveBorder,
    required this.commentSendInactiveIcon,
    required this.expandIconBlue,
    required this.expandIconGray,
    required this.dotsButtonBg,
    required this.actionMenuBg,
    required this.actionBtnText,
    required this.idTint,
    required this.idErrorFallback,
  });
}

// ============================================================
//  PostCreateColors — 发布页专属颜色
// ============================================================
class PostCreateColors {
  final Color pageBg;
  final Color fieldBg;
  final Color divider;
  final Color topBarBg;
  final Color titleLabelRest;
  final Color titleLabelFloat;
  final Color contentLabelRest;
  final Color contentLabelFloat;
  final Color previewDivider;
  final Color uploadBtnBorder;
  final Color uploadBtnIcon;
  final Color deleteBtnBorder;
  final Color deleteBtnIcon;
  final Color expandBtnBorder;
  final Color expandBtnIcon;
  final Color authorIcon;
  final Color authorBorder;
  final Color authorActiveFill;
  final Color authorActiveIcon;
  final Color bottomHintText;
  final Color errorText;
  final Color submitBg;
  final Color submitText;
  final Color buttonBg;
  final Color buttonIcon;
  final Color contentOverlay;
  final Color contentCollapseIcon;

  const PostCreateColors({
    required this.pageBg,
    required this.fieldBg,
    required this.divider,
    required this.topBarBg,
    required this.titleLabelRest,
    required this.titleLabelFloat,
    required this.contentLabelRest,
    required this.contentLabelFloat,
    required this.previewDivider,
    required this.uploadBtnBorder,
    required this.uploadBtnIcon,
    required this.deleteBtnBorder,
    required this.deleteBtnIcon,
    required this.expandBtnBorder,
    required this.expandBtnIcon,
    required this.authorIcon,
    required this.authorBorder,
    required this.authorActiveFill,
    required this.authorActiveIcon,
    required this.bottomHintText,
    required this.errorText,
    required this.submitBg,
    required this.submitText,
    required this.buttonBg,
    required this.buttonIcon,
    required this.contentOverlay,
    required this.contentCollapseIcon,
  });
}

// ============================================================
//  VersionCardColors — 版本卡片专属颜色
// ============================================================
class VersionCardColors {
  final Color version;
  final Color badgeBg;
  final Color badgeText;
  final Color boxBg;
  final Color title;
  final Color log;
  final Color latestBorder;

  const VersionCardColors({
    required this.version,
    required this.badgeBg,
    required this.badgeText,
    required this.boxBg,
    required this.title,
    required this.log,
    required this.latestBorder,
  });
}

// ---- RegisterColors ----

class RegisterColors {
  final Color loadingIndicator;
  final Color buttonBg;
  final Color buttonText;
  final Color buttonBorderColor;
  final Color disabledButtonBg;
  final Color disabledButtonText;
  final Color disabledButtonBorderColor;
  final Color errorText;
  final Color stepCompleted;
  final Color pageBg;
  final Color ellipseBg;
  final Color registeredTextColor;
  final Color loginRecoverColor;

  const RegisterColors({
    required this.loadingIndicator,
    required this.buttonBg,
    required this.buttonText,
    required this.buttonBorderColor,
    required this.disabledButtonBg,
    required this.disabledButtonText,
    required this.disabledButtonBorderColor,
    required this.errorText,
    required this.stepCompleted,
    required this.pageBg,
    required this.ellipseBg,
    required this.registeredTextColor,
    required this.loginRecoverColor,
  });
}

// ---- SmsPageColors ----

/// 手机号验证码页（sms_login / sms_register）配色
class SmsPageColors {
  final Color pageBg;
  final Color title;
  final Color subtitle;
  final Color boxBg;
  final Color boxBorder;
  final Color fieldText;
  final Color hintText;
  final Color prefixIcon;
  final Color suffixLink;
  final Color suffixDisabled;
  final Color buttonBg;
  final Color buttonText;
  final Color error;

  const SmsPageColors({
    required this.pageBg,
    required this.title,
    required this.subtitle,
    required this.boxBg,
    required this.boxBorder,
    required this.fieldText,
    required this.hintText,
    required this.prefixIcon,
    required this.suffixLink,
    required this.suffixDisabled,
    required this.buttonBg,
    required this.buttonText,
    required this.error,
  });
}

// ============================================================
//  AppColors — 主题扩展
// ============================================================
class AppColors extends ThemeExtension<AppColors> {
  final CommonColors common;
  final PostCardColors postCard;
  final PostCreateColors postCreate;
  final VersionCardColors versionCard;
  final RegisterColors register;
  final SmsPageColors smsPage;

  const AppColors({
    required this.common,
    required this.postCard,
    required this.postCreate,
    required this.versionCard,
    required this.register,
    required this.smsPage,
  });

  @override
  AppColors copyWith({
    CommonColors? common,
    PostCardColors? postCard,
    PostCreateColors? postCreate,
    VersionCardColors? versionCard,
    RegisterColors? register,
    SmsPageColors? smsPage,
  }) {
    return AppColors(
      common: common ?? this.common,
      postCard: postCard ?? this.postCard,
      postCreate: postCreate ?? this.postCreate,
      versionCard: versionCard ?? this.versionCard,
      register: register ?? this.register,
      smsPage: smsPage ?? this.smsPage,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      common: t < 0.5 ? common : other.common,
      postCard: t < 0.5 ? postCard : other.postCard,
      postCreate: t < 0.5 ? postCreate : other.postCreate,
      versionCard: t < 0.5 ? versionCard : other.versionCard,
      register: t < 0.5 ? register : other.register,
      smsPage: t < 0.5 ? smsPage : other.smsPage,
    );
  }

// ============================================================
//  具体颜色值 — light / dark 成对排列
// ============================================================

// ---- CommonColors ----

static const commonLight = CommonColors(
  background:             Color(0xFFFFFFFF),
  surface:                Color(0xFFFFFFFF),
  onSurface:              Color(0xFF333333),
  secondary:              Color(0xFF747474),
  authorColor:            Color(0xFF2F68C5),
  accentText:             Color(0xFF33B1FF),
  buttonBg:               Color(0xFF2CAEFF),
  green:                  Color(0xFF7BB380),
  attachment:             Color(0xFF545FFF),
  divider:                Color(0xFFE0E0E0),
  trailingIcon:           Color(0xFF9E9E9E),
  arrowIcon:              Color(0x8A000000),
  barText:                Color(0xDD000000),
  expandIconActive:       Color(0xFF3B82F6),
  switchActive:           Color(0xFF0EAB00),
  borderColor:            Color(0xFF999999),
  idTint:                 Color(0xFF0EAB00),
  drawerHeaderBg:         Color(0xFFE8F5E9),
  overlayActionBarBg:     Color(0xE6212121),
  overlayIcon:            Color(0xFFFFFFFF),
  overlayPageDot:         Color(0xFFFFFFFF),
  updateArrow:            Color(0xFF92C8FF),
  deviceDeleteIcon:       Color(0x8CBD0000),
  devicePrimaryStar:      Color(0xFFFFC107),
);

static const commonDark = CommonColors(
  background:             Color(0xFF191919),
  surface:                Color(0xFF222222),
  onSurface:              Color(0xFFd3d3d3),
  secondary:              Color(0x70999999),
  authorColor:            Color(0xFF2F68C5),
  accentText:             Color(0xBA5498FF),
  buttonBg:               Color(0xFF2693FF),
  green:                  Color(0xFF7BB380),
  attachment:             Color(0xFF616BFF),
  divider:                Color(0xFF424242),
  trailingIcon:           Color(0xFF757575),
  arrowIcon:              Color(0x8AFFFFFF),
  barText:                Color(0xDDFFFFFF),
  expandIconActive:       Color(0xFF3B82F6),
  switchActive:           Color(0xFF0EAB00),
  borderColor:            Color(0xFF444444),
  idTint:                 Color(0xFF0EAB00),
  drawerHeaderBg:         Color(0xFF1B2E1F),
  overlayActionBarBg:     Color(0xE6212121),
  overlayIcon:            Color(0xFFFFFFFF),
  overlayPageDot:         Color(0xFFFFFFFF),
  updateArrow:            Color(0xFF235180),
  deviceDeleteIcon:       Color(0x8Cd3d3d3),
  devicePrimaryStar:      Color(0xFFFFC107),
);

// ---- PostCardColors ----

static const postCardLight = PostCardColors(
  cardBorder:             Color(0x2E999999),
  bodyDivider:            Color(0x2E999999),
  title:                  Color(0xFF333333),
  content:                Color(0xFF333333),
  dateText:               Color(0xFF747474),
  remainCount:            Color(0xFF747474),
  authorName:             Color(0xFF2F68C5),
  atSymbol:               Color(0xFF7BB380),
  attachmentText:         Color(0xFF545FFF),
  commentContent:         Color(0xFF333333),
  commentAuthor:          Color(0xFF2F68C5),
  commentDate:            Color(0xFF747474),
  commentRemain:          Color(0xFF747474),
  commentBg:              Color(0x17747474),
  commentIcon:            Color(0xFF747474),
  commentDateSeparatorLine: Color(0x4D747474),
  commentInputBarBg:        Color(0xFFF5F5F5),
  commentInputFieldBg:      Color(0xFFFFFFFF),
  commentSendActiveBg:      Color(0xFF00CC62),
  commentSendActiveIcon:    Color(0xFFFFFFFF),
  commentSendInactiveBg:    Color(0xFFFFFFFF),
  commentSendInactiveBorder:Color(0x6C999999),
  commentSendInactiveIcon:  Color(0xA8999999),
  expandIconBlue:         Color(0xFF3B82F6),
  expandIconGray:         Color(0x21747474),
  dotsButtonBg:           Color(0x17747474),
  actionMenuBg:           Color(0xFF3B3B3B),
  actionBtnText:          Color(0xFFEEEEEE),
  idTint:                 Color(0x810EAB00),
  idErrorFallback:        Color(0xFFF44336),
);

static const postCardDark = PostCardColors(
  cardBorder:             Color(0x39AEAEAE),
  bodyDivider:            Color(0x2EFF0000),
  title:                  Color(0xFFd3d3d3),
  content:                Color(0xFFd3d3d3),
  dateText:               Color(0xFF8B8B8B),
  remainCount:            Color(0x70999999),
  authorName:             Color(0xE378B0FF),
  atSymbol:               Color(0xCC87FF91),
  attachmentText:         Color(0xFF616BFF),
  commentContent:         Color(0xFFd3d3d3),
  commentAuthor:          Color(0xE378B0FF),
  commentDate:            Color(0xFF8B8B8B),
  commentRemain:          Color(0xA5999999),
  commentBg:              Color(0xFF282828),
  commentIcon:            Color(0xA5999999),
  commentDateSeparatorLine: Color(0x4D5F5D60),
  commentInputBarBg:        Color(0xFF1A1A1A),
  commentInputFieldBg:      Color(0xFF282828),
  commentSendActiveBg:      Color(0xFF12B460),
  commentSendActiveIcon:    Color(0xFFEFEFEF),
  commentSendInactiveBg:    Color(0xFF2A2A2A),
  commentSendInactiveBorder:Color(0x39AEAEAE),
  commentSendInactiveIcon:  Color(0xFF8B8B8B),
  expandIconBlue:         Color(0xFF326CCA),
  expandIconGray:         Color(0xFF3C3C3C),
  dotsButtonBg:           Color(0xFF3C3C3C),
  actionMenuBg:           Color(0xFF3B3B3B),
  actionBtnText:          Color(0xFFEEEEEE),
  idTint:                 Color(0xBC307828),
  idErrorFallback:        Color(0xFFF44336),
);

// ---- PostCreateColors ----

static const postCreateLight = PostCreateColors(
  pageBg:                 Color(0xFFF5F5F5),
  fieldBg:                Color(0xFFFFFFFF),
  divider:                Color(0xFFEEEEEE),
  topBarBg:               Color(0xFFD5F2D7),
  titleLabelRest:         Color(0xB1000000),
  titleLabelFloat:        Color(0xFFBBBBBB),
  contentLabelRest:       Color(0xB1000000),
  contentLabelFloat:      Color(0xFFBBBBBB),
  previewDivider:         Color(0xFFE8E8E8),
  uploadBtnBorder:        Color(0xFF67BDFF),
  uploadBtnIcon:          Color(0xFF1D81CD),
  deleteBtnBorder:        Color(0xFFFF8383),
  deleteBtnIcon:          Color(0xFFDF2323),
  expandBtnBorder:        Color(0xFF67BDFF),
  expandBtnIcon:          Color(0xFF1D81CD),
  authorIcon:             Color(0xFF626262),
  authorBorder:           Color(0xFF626262),
  authorActiveFill:       Color(0xFF00CC62),
  authorActiveIcon:       Color(0xFFFFFFFF),
  bottomHintText:         Color(0xDD000000),
  errorText:              Color(0xFFFF0000),
  submitBg:               Color(0xFF00CC62),
  submitText:             Color(0xFFFFFFFF),
  buttonBg:               Color(0xFF2CAEFF),
  buttonIcon:             Color(0xFFFFFFFF),
  contentOverlay:         Color(0xFF000000),
  contentCollapseIcon:    Color(0xFF666666),
);

static const postCreateDark = PostCreateColors(
  pageBg:                 Color(0xFF1A1A1A),
  fieldBg:                Color(0xFF2A2A2A),
  divider:                Color(0xFF404040),
  topBarBg:               Color(0xFF1B2E1F),
  titleLabelRest:         Color(0xB1FFFFFF),
  titleLabelFloat:        Color(0xFFAAAAAA),
  contentLabelRest:       Color(0xB1FFFFFF),
  contentLabelFloat:      Color(0xFFAAAAAA),
  previewDivider:         Color(0xFF3A3A3A),
  uploadBtnBorder:        Color(0xFF286B9E),
  uploadBtnIcon:          Color(0xFF57B5FD),
  deleteBtnBorder:        Color(0xFF8B2F2F),
  deleteBtnIcon:          Color(0xFFFB3E3E),
  expandBtnBorder:        Color(0xFF2874AE),
  expandBtnIcon:          Color(0xFF57B5FD),
  authorIcon:             Color(0xFFAAAAAA),
  authorBorder:           Color(0xFFAAAAAA),
  authorActiveFill:       Color(0xFF12B460),
  authorActiveIcon:       Color(0xFFEFEFEF),
  bottomHintText:         Color(0xCCFFFFFF),
  errorText:              Color(0xFFFF0400),
  submitBg:               Color(0xFF12B460),
  submitText:             Color(0xFFEFEFEF),
  buttonBg:               Color(0xFF2B84DC),
  buttonIcon:             Color(0xFFDEDEDE),
  contentOverlay:         Color(0xFF000000),
  contentCollapseIcon:    Color(0xFFAAAAAA),
);

// ---- VersionCardColors ----

static const versionCardLight = VersionCardColors(
  version:                Color(0xFF000000),
  badgeBg:                Color(0xFF3EB147),
  badgeText:              Color(0xFFFFFFFF),
  boxBg:                  Color(0xFFFFFFFF),
  title:                  Color(0xFF000000),
  log:                    Color(0xFF444444),
  latestBorder:           Color(0xAF4AB655),
);

static const versionCardDark = VersionCardColors(
  version:                Color(0xFFFFFFFF),
  badgeBg:                Color(0xA953FF61),
  badgeText:              Color(0xFFFFFFFF),
  boxBg:                  Color(0xFF2C2C2C),
  title:                  Color(0xFFFFFFFF),
  log:                    Color(0xFFD9D9D9),
  latestBorder:           Color(0x6C7AB47F),
);

// ---- RegisterColors ----

static const registerLight = RegisterColors(
  loadingIndicator: Color(0xFF3EB147),
  buttonBg:         Color(0xFF5EED6F),
  buttonText:       Color(0xFFFFFFFF),
  buttonBorderColor: Color(0xFF45D151),
  disabledButtonBg:         Color(0x53D5D5D5),
  disabledButtonText:       Color(0x539E9E9E),
  disabledButtonBorderColor: Color(0x53BDBDBD),
  errorText:        Color(0xFFE57373),
  stepCompleted:    Color(0xFF9E9E9E),
  pageBg:           Color(0xFFD5F2D7),
  ellipseBg:        Color(0xFFFFFFFF),
  registeredTextColor: Color(0xCC000000),
  loginRecoverColor: Color(0xFF64B5F6),
);
  
static const registerDark = RegisterColors(
  loadingIndicator: Color(0xDF31E840),
  buttonBg:         Color(0xFF1A7E26),
  buttonText:       Color(0xFFFFFFFF),
  buttonBorderColor: Color(0xFF43A64B),
  disabledButtonBg:         Color(0x883A3A3A),
  disabledButtonText:       Color(0x88757575),
  disabledButtonBorderColor: Color(0x884A4A4A),
  errorText:        Color(0xFFEF9A9A),
  stepCompleted:    Color(0xFFBDBDBD),
  pageBg:           Color(0xFF1B2E1F),
  ellipseBg:        Color(0xFF2C3E2F),
  registeredTextColor: Color(0xCCC0C0C0),
  loginRecoverColor: Color(0xFF90CAF9),
);

static const smsLight = SmsPageColors(
  pageBg:         Color(0xFFFFFFFF),
  title:          Color(0xFF333333),
  subtitle:       Color(0x73333333),
  boxBg:          Color(0xFFFFFFFF),
  boxBorder:      Color(0x40333333),
  fieldText:      Color(0xFF333333),
  hintText:       Color(0x59333333),
  prefixIcon:     Color(0x99333333),
  suffixLink:     Color(0xFF00CC62),
  suffixDisabled: Color(0x59333333),
  buttonBg:       Color(0xFF00CC62),
  buttonText:     Color(0xFFFFFFFF),
  error:          Color(0xFFFF0000),
);

static const smsDark = SmsPageColors(
  pageBg:         Color(0xFF222222),
  title:          Color(0xFFd3d3d3),
  subtitle:       Color(0x73d3d3d3),
  boxBg:          Color(0xFF222222),
  boxBorder:      Color(0x40d3d3d3),
  fieldText:      Color(0xFFd3d3d3),
  hintText:       Color(0x59d3d3d3),
  prefixIcon:     Color(0x99d3d3d3),
  suffixLink:     Color(0xFF12B460),
  suffixDisabled: Color(0x59d3d3d3),
  buttonBg:       Color(0xFF12B460),
  buttonText:     Color(0xFFEFEFEF),
  error:          Color(0xFFFF0400),
);

static const light = AppColors(
  common: commonLight,
  postCard: postCardLight,
  postCreate: postCreateLight,
  versionCard: versionCardLight,
  register: registerLight,
  smsPage: smsLight,
);

static const dark = AppColors(
  common: commonDark,
  postCard: postCardDark,
  postCreate: postCreateDark,
  versionCard: versionCardDark,
  register: registerDark,
  smsPage: smsDark,
);
}
