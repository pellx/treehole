class Post {
  final int id;
  final String title;
  final String content;
  final String author;
  final bool isAnonymous;
  final String category;
  final String createdAt;
  final String updateAt;
  final List<PostImage> images;
  final List<PostAttachment> attachments;
  final List<int> comments;

  const Post({
    required this.id,
    required this.title,
    this.content = '',
    this.author = '',
    this.isAnonymous = false,
    this.category = '默认',
    this.createdAt = '',
    this.updateAt = '',
    this.images = const [],
    this.attachments = const [],
    this.comments = const [],
  });

  /// 对外展示署名：匿名或空名则不显示
  String get displayAuthor {
    if (isAnonymous) return '';
    return author.trim();
  }

  factory Post.fromJson(Map<String, dynamic> json) {
    return Post(
      id: json['id'] as int,
      title: json['title'] as String? ?? '',
      content: json['content'] as String? ?? '',
      author: json['author'] as String? ?? '',
      isAnonymous: _asBool(json['is_anonymous']),
      category: json['category'] as String? ?? '默认',
      createdAt: json['created_at'] as String? ?? '',
      updateAt: json['update_at'] as String? ?? '',
      images:
          (json['images'] as List<dynamic>?)
              ?.map((e) => PostImage(
                    fileName: e['file_name'] as String,
                    width: (e['width'] as num?)?.toInt() ?? 0,
                    height: (e['height'] as num?)?.toInt() ?? 0,
                  ))
              .toList() ??
          [],
      attachments:
          (json['attachments'] as List<dynamic>?)
              ?.map(
                (e) => PostAttachment(
                  fileName: e['file_name'] as String,
                  sourceName: e['source_name'] as String? ?? '',
                ),
              )
              .toList() ??
          [],
      comments:
          (json['comments'] as List<dynamic>?)?.map((e) => e as int).toList() ??
          [],
    );
  }
}

bool _asBool(dynamic v) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final s = v.toLowerCase();
    return s == 'true' || s == '1';
  }
  return false;
}

class PostImage {
  final String fileName;
  final int width;
  final int height;
  const PostImage({required this.fileName, this.width = 0, this.height = 0});
}

class PostAttachment {
  final String fileName;
  final String sourceName;
  const PostAttachment({required this.fileName, required this.sourceName});
}
