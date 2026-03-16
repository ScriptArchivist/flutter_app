class VideoListItem {
  final int id;
  final String title;
  final String? description;
  final String status;
  final String? thumbnailUrl;
  final double? duration;
  final bool hlsReady;
  final String? hlsUrl;

  VideoListItem({
    required this.id,
    required this.title,
    this.description,
    required this.status,
    this.thumbnailUrl,
    this.duration,
    required this.hlsReady,
    this.hlsUrl,
  });

  factory VideoListItem.fromJson(Map<String, dynamic> json) {
    return VideoListItem(
      id: json["id"],
      title: json["title"],
      description: json["description"],
      status: json["status"],
      thumbnailUrl: json["thumbnail_url"],
      duration: json["duration"]?.toDouble(),
      hlsReady: json["hls_ready"],
      hlsUrl: json["hls_url"],
    );
  }
}