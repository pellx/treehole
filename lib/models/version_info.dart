class VersionInfo {
  /// 当前 app 版本号，与 pubspec.yaml 保持一致
  static const String currentVersion = '1.1.2';

  final int id;
  final String versionNumber;
  final String platform;
  final String title;
  final String log;
  final String description;
  final String downloadUrl;
  final String releaseDate;

  const VersionInfo({
    required this.id,
    required this.versionNumber,
    required this.platform,
    required this.title,
    required this.log,
    required this.description,
    required this.downloadUrl,
    required this.releaseDate,
  });

  factory VersionInfo.fromJson(Map<String, dynamic> json) {
    return VersionInfo(
      id: json['id'] as int? ?? 0,
      versionNumber: (json['versionNumber'] ?? json['version_number'] ?? '') as String,
      platform: (json['platform'] ?? '') as String,
      title: (json['title'] ?? '') as String,
      log: (json['log'] ?? '') as String,
      description: (json['description'] ?? '') as String,
      downloadUrl: (json['downloadUrl'] ?? json['download_url'] ?? '') as String,
      releaseDate: (json['releaseDate'] ?? json['release_date'] ?? '') as String,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'version_number': versionNumber,
    'platform': platform,
    'title': title,
    'log': log,
    'description': description,
    'download_url': downloadUrl,
    'release_date': releaseDate,
  };
}
