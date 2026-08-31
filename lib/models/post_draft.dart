import 'upload_result.dart';

class PostDraft {
  final String title;
  final String content;
  /// 是否匿名（与署名开关相反）；署名作者由后端按 session 解析
  final bool isAnonymous;
  final List<UploadResult> uploaded;

  /// v2 发帖：body 不带 author / user_id（后端 DTO 禁止），
  /// 也不带 session——session_id / session_secret 由 ApiService 统一注入
  const PostDraft({
    required this.title,
    required this.content,
    required this.isAnonymous,
    required this.uploaded,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'title': title,
      'content': content,
      'is_anonymous': isAnonymous,
      'uploaded': uploaded.map((e) => e.toJson()).toList(),
    };
    return map;
  }
}
