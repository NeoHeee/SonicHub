class SpeakerDevice {
  const SpeakerDevice({
    required this.accountId,
    required this.id,
    required this.name,
    this.model,
  });

  final String accountId;
  final String id;
  final String name;
  final String? model;

  factory SpeakerDevice.fromJson(Map<String, dynamic> json, String accountId) {
    return SpeakerDevice(
      accountId: accountId,
      id: '${json['deviceID'] ?? json['device_id'] ?? json['id'] ?? ''}',
      name: '${json['name'] ?? json['alias'] ?? '未命名音箱'}',
      model: json['model']?.toString(),
    );
  }
}

class MediaItem {
  const MediaItem({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    required this.playUrl,
    required this.coverUrl,
  });

  final int id;
  final String title;
  final String artist;
  final String album;
  final double duration;
  final String playUrl;
  final String coverUrl;

  factory MediaItem.fromJson(Map<String, dynamic> json) {
    return MediaItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: '${json['title'] ?? '未知歌曲'}',
      artist: '${json['artist'] ?? ''}',
      album: '${json['album'] ?? ''}',
      duration: (json['duration'] as num?)?.toDouble() ?? 0,
      playUrl: '${json['url'] ?? ''}',
      coverUrl: '${json['cover_url'] ?? ''}',
    );
  }

  String get subtitle => [
        if (artist.trim().isNotEmpty) artist.trim(),
        if (album.trim().isNotEmpty) album.trim(),
      ].join(' · ');
}

class PlaylistSummary {
  const PlaylistSummary({
    required this.id,
    required this.name,
    required this.songCount,
  });

  final int id;
  final String name;
  final int songCount;

  factory PlaylistSummary.fromJson(Map<String, dynamic> json) {
    return PlaylistSummary(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: '${json['name'] ?? '未命名歌单'}',
      songCount: (json['song_count'] as num?)?.toInt() ?? 0,
    );
  }
}

class DeviceStatus {
  const DeviceStatus({
    required this.state,
    required this.volume,
    required this.position,
    required this.duration,
    required this.currentIndex,
    required this.playlistId,
    required this.playlistName,
    required this.currentSong,
  });

  final String state;
  final int? volume;
  final double position;
  final double duration;
  final int currentIndex;
  final int playlistId;
  final String playlistName;
  final MediaItem? currentSong;

  factory DeviceStatus.fromJson(Map<String, dynamic> json) {
    final rawSong = json['current_song'];
    return DeviceStatus(
      state: '${json['state'] ?? 'unknown'}',
      volume: (json['volume'] as num?)?.toInt(),
      position: (json['position'] as num?)?.toDouble() ?? 0,
      duration: (json['duration'] as num?)?.toDouble() ?? 0,
      currentIndex: (json['current_index'] as num?)?.toInt() ?? -1,
      playlistId: (json['playlist_id'] as num?)?.toInt() ?? 0,
      playlistName: '${json['playlist_name'] ?? ''}',
      currentSong: rawSong is Map
          ? MediaItem.fromJson(rawSong.cast<String, dynamic>())
          : null,
    );
  }
}
