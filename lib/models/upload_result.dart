enum PostUploadType { image, attachment }

extension PostUploadTypeX on PostUploadType {
  String get apiValue => switch (this) {
    PostUploadType.image => 'image',
    PostUploadType.attachment => 'attachment',
  };
}

class UploadResult {
  final PostUploadType type;
  final String original;
  final String filename;

  const UploadResult({
    required this.type,
    required this.original,
    required this.filename,
  });

  Map<String, dynamic> toJson() => {
    'type': type.apiValue,
    'original': original,
    'filename': filename,
  };

  factory UploadResult.fromJson(Map<String, dynamic> json) {
    return UploadResult(
      type: json['type'] == PostUploadType.attachment.apiValue
          ? PostUploadType.attachment
          : PostUploadType.image,
      original: json['original'] as String? ?? '',
      filename: json['filename'] as String? ?? '',
    );
  }
}
