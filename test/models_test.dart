import 'package:flutter_test/flutter_test.dart';
import 'package:sonichub/src/core/models.dart';
import 'package:sonichub/src/core/audiobookshelf_api.dart';
import 'package:sonichub/src/core/playback_controller.dart';
import 'package:sonichub/src/core/playback_context.dart';
import 'package:sonichub/src/core/server_config.dart';

void main() {
  test('local playback device is identified without a Songloft account', () {
    expect(SpeakerDevice.local.isLocal, isTrue);
    expect(SpeakerDevice.local.name, '本机播放');
  });

  test('parses MIoT device using upstream field names', () {
    final device = SpeakerDevice.fromJson(
      {
        'deviceID': 'speaker-1',
        'name': '客厅音箱',
        'model': 'LX06',
      },
      'account-1',
    );

    expect(device.accountId, 'account-1');
    expect(device.id, 'speaker-1');
    expect(device.name, '客厅音箱');
    expect(device.model, 'LX06');
  });

  test('parses nullable device status and current song safely', () {
    final status = DeviceStatus.fromJson({
      'state': 'playing',
      'volume': null,
      'position': 12.5,
      'duration': 240,
      'current_index': 2,
      'playlist_id': 8,
      'playlist_name': '收藏',
      'current_song': {
        'id': 10,
        'title': '测试歌曲',
        'artist': '测试歌手',
        'album': '测试专辑',
      },
    });

    expect(status.state, 'playing');
    expect(status.volume, isNull);
    expect(status.position, 12.5);
    expect(status.duration, 240);
    expect(status.currentIndex, 2);
    expect(status.currentSong?.title, '测试歌曲');
  });

  test('parses playlist and media items', () {
    final playlist = PlaylistSummary.fromJson({
      'id': 3,
      'name': '我的歌单',
      'song_count': 12,
    });
    final song = MediaItem.fromJson({
      'id': 5,
      'title': '歌曲',
      'artist': '歌手',
      'album': '专辑',
      'duration': 180,
      'url': '/api/v1/songs/5/play',
    });

    expect(playlist.songCount, 12);
    expect(song.subtitle, '歌手 · 专辑');
  });

  test('normalizes whitespace and trailing slashes in server URL', () {
    expect(
      ServerConfig.normalizeBaseUrl('  http:// 192.168.1.1:58092///  '),
      'http://192.168.1.1:58092',
    );
    expect(
      ServerConfig.normalizeBaseUrl('https://songloft.example.com/'),
      'https://songloft.example.com',
    );
  });

  test('audiobook playback context remains distinct from Songloft music', () {
    final context = PlaybackContext(
      source: PlaybackSource.audiobookshelf,
      title: '测试有声书',
      subtitle: '第一章 · 作者',
      mediaId: 'book-1',
      duration: 3600,
    );

    expect(context.isAudiobook, isTrue);
    expect(context.sourceLabel, 'Audiobookshelf');
  });

  test('Audiobookshelf audio requests carry bearer authentication', () {
    const config = AudiobookshelfConfig(
      baseUrl: 'https://books.example.com/',
      apiKey: ' secret-token ',
    );

    expect(config.audioHeaders, {
      'Authorization': 'Bearer secret-token',
    });
  });

  test('playback capabilities expose supported controls independently', () {
    const capabilities = PlaybackCapabilities(
      canToggle: true,
      canStop: true,
      canPrevious: false,
      canNext: true,
      canSeek: false,
    );

    expect(capabilities.canToggle, isTrue);
    expect(capabilities.canPrevious, isFalse);
    expect(capabilities.canNext, isTrue);
    expect(capabilities.canSeek, isFalse);
  });
}
