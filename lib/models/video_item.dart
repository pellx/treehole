class VideoQuality {
  final String label;
  final Uri url;

  const VideoQuality({required this.label, required this.url});

  factory VideoQuality.fromJson(Map<String, dynamic> json) => VideoQuality(
    label: json['label'] as String,
    url: Uri.parse(json['url'] as String),
  );
}

class VideoItem {
  final int id;
  final String title;
  final Uri coverUrl;
  final Uri playbackUrl;
  final int? durationMs;
  final List<VideoQuality> qualities;

  const VideoItem({
    required this.id,
    required this.title,
    required this.coverUrl,
    required this.playbackUrl,
    required this.durationMs,
    required this.qualities,
  });

  factory VideoItem.fromJson(Map<String, dynamic> json) => VideoItem(
    id: (json['id'] as num).toInt(),
    title: json['title'] as String,
    coverUrl: Uri.parse(json['cover_url'] as String),
    playbackUrl: Uri.parse(json['playback_url'] as String),
    durationMs: (json['duration_ms'] as num?)?.toInt(),
    qualities: (json['qualities'] as List<dynamic>? ?? const [])
        .map((item) => VideoQuality.fromJson(item as Map<String, dynamic>))
        .toList(),
  );
}

class VideoDanmaku {
  final int id;
  final int timeMs;
  final String text;

  const VideoDanmaku({
    required this.id,
    required this.timeMs,
    required this.text,
  });

  factory VideoDanmaku.fromJson(Map<String, dynamic> json) => VideoDanmaku(
    id: (json['id'] as num).toInt(),
    timeMs: (json['time_ms'] as num).toInt(),
    text: json['text'] as String,
  );
}
