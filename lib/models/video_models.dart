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

class ActiveLiveListItem {
  final int? id;
  final String streamKey;
  final String title;
  final String? description;
  final String status;
  final String? hlsUrl;
  final bool hlsReady;
  final String? ownerName;
  final DateTime? startedAt;
  final String? thumbnailUrl;

  ActiveLiveListItem({
    this.id,
    required this.streamKey,
    required this.title,
    this.description,
    required this.status,
    this.hlsUrl,
    required this.hlsReady,
    this.ownerName,
    this.startedAt,
    this.thumbnailUrl,
  });

  factory ActiveLiveListItem.fromJson(Map<String, dynamic> json) {
    final rawStreamKey = json['stream_key']?.toString().trim() ?? '';
    final rawTitle = json['title']?.toString().trim() ?? '';

    return ActiveLiveListItem(
      id: _tryParseInt(json['id']),
      streamKey: rawStreamKey,
      title: rawTitle.isNotEmpty
          ? rawTitle
          : (rawStreamKey.isNotEmpty ? 'Live $rawStreamKey' : 'Live'),
      description: json['description']?.toString(),
      status: (json['status']?.toString().trim().isNotEmpty ?? false)
          ? json['status'].toString().trim()
          : 'live',
      hlsUrl: json['hls_url']?.toString(),
      hlsReady: _parseBool(json['hls_ready']) ||
          _parseBool(json['is_hls_ready']) ||
          _parseBool(json['ready']),
      ownerName: json['owner_name']?.toString() ??
          json['username']?.toString() ??
          json['author']?.toString(),
      startedAt: _tryParseDateTime(
        json['started_at'] ?? json['created_at'] ?? json['published_at'],
      ),
      thumbnailUrl: json['thumbnail_url']?.toString(),
    );
  }

  static int? _tryParseInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }

  static bool _parseBool(dynamic value) {
    if (value is bool) return value;

    final raw = value?.toString().trim().toLowerCase();
    return raw == 'true' || raw == '1' || raw == 'yes';
  }

  static DateTime? _tryParseDateTime(dynamic value) {
    final raw = value?.toString().trim();
    if (raw == null || raw.isEmpty) {
      return null;
    }

    return DateTime.tryParse(raw);
  }
}