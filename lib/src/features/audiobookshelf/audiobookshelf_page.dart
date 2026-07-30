import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/audiobookshelf_api.dart';
import '../../core/models.dart';
import '../../core/songloft_api.dart';

class AudiobookshelfPage extends StatefulWidget {
  const AudiobookshelfPage({required this.songloftApi, required this.device, required this.onPlayed, super.key});
  final SongloftApi songloftApi;
  final SpeakerDevice? device;
  final void Function(
    AbsBook book,
    String? chapterTitle,
    String? coverUrl,
    Future<void> Function() onNext,
  ) onPlayed;
  @override State<AudiobookshelfPage> createState() => _AudiobookshelfPageState();
}

class _AudiobookshelfPageState extends State<AudiobookshelfPage> {
  final _store = AudiobookshelfConfigStore();
  final _baseUrl = TextEditingController();
  final _apiKey = TextEditingController();
  final _search = TextEditingController();
  AudiobookshelfConfig? _config;
  AudiobookshelfApi? _api;
  List<AbsLibrary> _libraries = const [];
  List<AbsBook> _books = const [];
  AbsLibrary? _library;
  AbsBookDetail? _detail;
  String? _error;
  bool _busy = true;
  bool _continueOnly = false;
  Timer? _progressTimer;
  AbsBookDetail? _playingBook;
  AbsPlayback? _playback;

  @override void initState() { super.initState(); _restore(); }
  @override void dispose() { _progressTimer?.cancel(); _syncProgress(); _baseUrl.dispose(); _apiKey.dispose(); _search.dispose(); super.dispose(); }

  Future<void> _restore() async {
    final config = await _store.load();
    if (!mounted) return;
    if (config == null) { setState(() => _busy = false); return; }
    _baseUrl.text = config.baseUrl;
    _apiKey.text = config.apiKey;
    await _connect(config);
  }

  Future<void> _saveAndConnect() async {
    final config = AudiobookshelfConfig(baseUrl: _baseUrl.text, apiKey: _apiKey.text);
    final uri = Uri.tryParse(config.normalizedBaseUrl);
    if (uri == null || !uri.hasScheme || config.apiKey.trim().isEmpty) { setState(() => _error = '请填写完整的 Audiobookshelf 地址和 API Key'); return; }
    await _store.save(config);
    await _connect(config);
  }

  Future<void> _connect(AudiobookshelfConfig config) async {
    setState(() { _busy = true; _error = null; });
    try {
      final api = AudiobookshelfApi(config);
      final libraries = await api.getLibraries();
      final selected = libraries.isEmpty ? null : libraries.firstWhere((item) => item.id == config.libraryId, orElse: () => libraries.first);
      final saved = config.copyWith(libraryId: selected?.id ?? '');
      await _store.save(saved);
      if (!mounted) return;
      setState(() { _config = saved; _api = AudiobookshelfApi(saved); _libraries = libraries; _library = selected; });
      if (selected != null) await _loadBooks();
    } catch (error) { if (mounted) setState(() => _error = error.toString()); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _selectLibrary(AbsLibrary? library) async {
    if (library == null || _config == null) return;
    final config = _config!.copyWith(libraryId: library.id);
    await _store.save(config);
    setState(() { _config = config; _api = AudiobookshelfApi(config); _library = library; _detail = null; });
    await _loadBooks();
  }

  Future<void> _loadBooks() async {
    final api = _api; final library = _library;
    if (api == null || library == null) return;
    setState(() { _busy = true; _error = null; });
    try {
      final books = _continueOnly ? await api.getContinueListening(library.id) : await api.getBooks(library.id, query: _search.text);
      if (mounted) setState(() => _books = books);
    } catch (error) { if (mounted) setState(() => _error = error.toString()); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _openBook(AbsBook book) async {
    setState(() { _busy = true; _error = null; });
    try { final detail = await _api!.getBook(book.id); if (mounted) setState(() => _detail = detail); }
    catch (error) { if (mounted) setState(() => _error = error.toString()); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _play({double? position}) async {
    final device = widget.device; final detail = _detail;
    if (device == null) { _message('请先在设备页面选择音箱'); return; }
    if (detail == null || _api == null) return;
    setState(() { _busy = true; _error = null; });
    try {
      final playback = await _api!.createPlayback(detail, position: position);
      await widget.songloftApi.playUrl(device, playback.url);
      _playingBook = detail; _playback = playback;
      _progressTimer?.cancel();
      _progressTimer = Timer.periodic(const Duration(seconds: 30), (_) => _syncProgress());
      String? chapterTitle;
      final target = position ?? detail.book.progress.currentTime;
      for (final chapter in detail.chapters) {
        if (target >= chapter.start && target < chapter.end) {
          chapterTitle = chapter.title;
          break;
        }
      }
      final coverUrl = '${_config!.normalizedBaseUrl}/api/items/${detail.book.id}/cover?token=${Uri.encodeQueryComponent(_config!.apiKey.trim())}';
      widget.onPlayed(detail.book, chapterTitle, coverUrl, _playNext);
      _message(playback.exactTrack ? '已从所选章节对应音轨开始播放' : '已推送音频；单文件 M4B 可能因音箱不支持跳转而从头播放');
    } catch (error) { if (mounted) setState(() => _error = error.toString()); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _playNext() async {
    final detail = _playingBook;
    final playback = _playback;
    final device = widget.device;
    if (detail == null || playback == null || device == null) return;

    var current = playback.bookPosition;
    try {
      final status = await widget.songloftApi.getStatus(device);
      current += status.position;
    } catch (_) {}

    double? nextPosition;
    final chapters = detail.chapters;
    if (chapters.isNotEmpty) {
      var currentIndex = chapters.lastIndexWhere(
        (chapter) => current >= chapter.start && current < chapter.end,
      );
      if (currentIndex < 0) {
        currentIndex = chapters.lastIndexWhere(
          (chapter) => chapter.start <= current,
        );
      }
      if (currentIndex + 1 < chapters.length) {
        nextPosition = chapters[currentIndex + 1].start;
      }
    }

    if (nextPosition == null) {
      for (final track in detail.tracks) {
        if (track.startOffset > current + 1) {
          nextPosition = track.startOffset;
          break;
        }
      }
    }

    if (nextPosition == null) {
      _message('已经是这本有声书的最后一章');
      return;
    }
    await _syncProgress();
    await _play(position: nextPosition);
  }

  Future<void> _syncProgress() async {
    final api = _api; final detail = _playingBook; final playback = _playback; final device = widget.device;
    if (api == null || detail == null || playback == null || device == null) return;
    try {
      final status = await widget.songloftApi.getStatus(device);
      final current = playback.bookPosition + status.position;
      await api.updateProgress(detail.book.id, currentTime: current.clamp(0, playback.duration), duration: playback.duration, isFinished: playback.duration > 0 && current >= playback.duration - 10);
    } catch (_) {}
  }

  void _message(String message) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message))); }
  String _time(double seconds) { final value = seconds.round().clamp(0, 9999999); final h = value ~/ 3600; final m = (value % 3600) ~/ 60; final s = value % 60; return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}' : '$m:${s.toString().padLeft(2, '0')}'; }

  @override Widget build(BuildContext context) {
    if (_config == null) return _buildSetup();
    if (_detail != null) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) setState(() => _detail = null);
        },
        child: _buildDetail(_detail!),
      );
    }
    return _buildLibrary();
  }

  Widget _buildSetup() => Scaffold(
    appBar: AppBar(title: const Text('Audiobookshelf')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      Text('连接 Audiobookshelf', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 8), const Text('API Key 仅加密保存在本机。音箱需要能够访问此服务器地址。'), const SizedBox(height: 16),
      TextField(controller: _baseUrl, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: '服务器地址', hintText: 'http://192.168.1.1:13378', prefixIcon: Icon(Icons.dns))),
      const SizedBox(height: 12),
      TextField(controller: _apiKey, obscureText: true, decoration: const InputDecoration(labelText: 'API Key', prefixIcon: Icon(Icons.key))),
      const SizedBox(height: 16),
      FilledButton.icon(onPressed: _busy ? null : _saveAndConnect, icon: const Icon(Icons.link), label: const Text('保存并连接')),
      if (_busy) const LinearProgressIndicator(),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
    ]),
  );

  Widget _buildLibrary() => Scaffold(
    appBar: AppBar(title: const Text('有声书'), actions: [IconButton(tooltip: '重新配置', onPressed: () => setState(() => _config = null), icon: const Icon(Icons.settings_outlined))]),
    body: Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 4), child: DropdownButtonFormField<AbsLibrary>(key: ValueKey(_library?.id), initialValue: _library, decoration: const InputDecoration(labelText: '有声书书库', prefixIcon: Icon(Icons.library_books)), items: [for (final item in _libraries) DropdownMenuItem(value: item, child: Text(item.name))], onChanged: _busy ? null : _selectLibrary)),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), child: SearchBar(controller: _search, hintText: '搜索书名、作者或演播者', leading: const Icon(Icons.search), onSubmitted: (_) => _loadBooks(), trailing: [IconButton(onPressed: _loadBooks, icon: const Icon(Icons.arrow_forward))])),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: SegmentedButton<bool>(segments: const [ButtonSegment(value: false, label: Text('全部书籍')), ButtonSegment(value: true, label: Text('继续收听'), icon: Icon(Icons.history))], selected: {_continueOnly}, onSelectionChanged: (values) { setState(() => _continueOnly = values.first); _loadBooks(); })),
      if (_busy) const LinearProgressIndicator(),
      if (_error != null) Padding(padding: const EdgeInsets.all(8), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      Expanded(child: RefreshIndicator(onRefresh: _loadBooks, child: _books.isEmpty && !_busy ? ListView(children: const [SizedBox(height: 120), Center(child: Text('没有找到有声书'))]) : ListView.builder(padding: const EdgeInsets.all(8), itemCount: _books.length, itemBuilder: (_, index) {
        final book = _books[index];
        return Card(child: ListTile(leading: const CircleAvatar(child: Icon(Icons.auto_stories)), title: Text(book.title), subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [if (book.subtitle.isNotEmpty) Text(book.subtitle), if (book.progress.currentTime > 0) ...[const SizedBox(height: 4), LinearProgressIndicator(value: book.progress.ratio), Text('${_time(book.progress.currentTime)} / ${_time(book.duration)}')]]), trailing: const Icon(Icons.chevron_right), onTap: () => _openBook(book)));
      }))),
    ]),
  );

  Widget _buildDetail(AbsBookDetail detail) => Scaffold(
    appBar: AppBar(title: Text(detail.book.title), leading: IconButton(onPressed: () => setState(() => _detail = null), icon: const Icon(Icons.arrow_back))),
    body: Column(children: [
      Card(margin: const EdgeInsets.all(12), child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
        ListTile(contentPadding: EdgeInsets.zero, leading: const CircleAvatar(child: Icon(Icons.auto_stories)), title: Text(detail.book.title), subtitle: Text(detail.book.subtitle)),
        if (detail.book.progress.currentTime > 0) ...[LinearProgressIndicator(value: detail.book.progress.ratio), const SizedBox(height: 6), Text('已听 ${_time(detail.book.progress.currentTime)} / ${_time(detail.book.duration)}')],
        const SizedBox(height: 8), FilledButton.icon(onPressed: _busy ? null : () => _play(position: detail.book.progress.currentTime), icon: const Icon(Icons.play_arrow), label: Text(detail.book.progress.currentTime > 0 ? '继续收听' : '从头播放')),
        const SizedBox(height: 6), const Text('多文件有声书可定位到对应音轨；单文件 M4B 是否能从章节起点播放取决于音箱的远程跳转能力。', textAlign: TextAlign.center),
      ]))),
      if (_busy) const LinearProgressIndicator(),
      if (_error != null) Padding(padding: const EdgeInsets.all(8), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      Expanded(child: detail.chapters.isEmpty ? const Center(child: Text('此书没有章节信息')) : ListView.builder(itemCount: detail.chapters.length, itemBuilder: (_, index) {
        final chapter = detail.chapters[index]; final active = detail.book.progress.currentTime >= chapter.start && detail.book.progress.currentTime < chapter.end;
        return ListTile(leading: CircleAvatar(child: Text('${index + 1}')), title: Text(chapter.title), subtitle: Text('${_time(chapter.start)} - ${_time(chapter.end)}'), selected: active, trailing: const Icon(Icons.play_arrow), onTap: _busy ? null : () => _play(position: chapter.start));
      })),
    ]),
  );
}
