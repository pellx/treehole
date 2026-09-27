import 'package:flutter/material.dart';

import '../../models/video_item.dart';
import '../../services/video_api.dart';
import '../../widgets/app_app_bar.dart';
import '../../widgets/app_empty_state.dart';
import 'video_detail_page.dart';

class VideosPage extends StatefulWidget {
  const VideosPage({super.key});

  @override
  State<VideosPage> createState() => _VideosPageState();
}

class _VideosPageState extends State<VideosPage> {
  late Future<List<VideoItem>> _videos;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _videos = VideoApi.list();

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: '视频',
      body: FutureBuilder<List<VideoItem>>(
        future: _videos,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: TextButton(
                onPressed: () => setState(_reload),
                child: const Text('加载失败，点击重试'),
              ),
            );
          }
          final videos = snapshot.data ?? const <VideoItem>[];
          if (videos.isEmpty) {
            return const AppEmptyState(
              message: '暂无视频',
              icon: Icons.video_library_outlined,
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              setState(_reload);
              await _videos;
            },
            child: ListView.builder(
              itemCount: videos.length,
              itemBuilder: (context, index) {
                final video = videos[index];
                return Card(
                  margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => VideoDetailPage(videoId: video.id),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AspectRatio(
                          aspectRatio: 16 / 9,
                          child: Image.network(
                            video.coverUrl.toString(),
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const Center(
                              child: Icon(Icons.broken_image_outlined),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            video.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
