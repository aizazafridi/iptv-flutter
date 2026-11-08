import 'package:flutter/foundation.dart';
import '../data/subtitle_preferences.dart';
import '../domain/models.dart';
import '../playback/playback_engine.dart';
import '../playback/subtitle_customization.dart';

/// Channel-discovered text captions; never synthesizes a track for an unsupported channel.
class LiveCaptions extends ChangeNotifier {
  final PlaybackEngine engine;
  final SubtitlePreferences preferences;
  final String profile;
  LiveCaptions({
    required this.engine,
    required this.preferences,
    required this.profile,
  });
  List<SubtitleOption> tracks = [];
  String selected = 'no';
  bool _closed = false, _ready = false, _live = false;
  int _generation = 0, _choiceVersion = 0;
  Map<String, dynamic> _choice = const {'mode': 'off'};
  Future<void> _lane = Future.value();
  String get key => 'live-cc:$profile';
  bool get available => tracks.isNotEmpty;
  bool get enabled => available && selected != 'no';
  static String language(String? code) => switch (code
      ?.trim()
      .toLowerCase()
      .replaceAll('_', '-')
      .split('-')
      .first) {
    'eng' => 'en',
    'fra' || 'fre' => 'fr',
    'spa' => 'es',
    'deu' || 'ger' => 'de',
    'ara' => 'ar',
    'hin' => 'hi',
    'urd' => 'ur',
    'por' => 'pt',
    'zho' || 'chi' => 'zh',
    final String value => value,
    _ => '',
  };
  static bool supported(SubtitleOption track) =>
      ![
        'dvd_subtitle',
        'dvb_subtitle',
        'hdmv_pgs_subtitle',
        'xsub',
      ].contains(track.codec?.toLowerCase()) &&
      track.id != 'no' &&
      track.id != 'auto';

  Future<void> beginStream(bool live) async {
    _generation++;
    _live = live;
    _ready = false;
    tracks = [];
    selected = 'no';
    if (!_closed) notifyListeners();
    await _lane;
    if (!_closed && live) {
      try {
        await engine.selectSubtitle('no');
      } catch (_) {
        /* Captions must not prevent channel playback. */
      }
    }
  }

  Future<void> restore() async {
    if (!_live || _closed) return;
    final generation = _generation;
    final choiceVersion = _choiceVersion;
    final choice = await preferences.loadChoice(key);
    final appearance = await preferences.loadAppearance();
    if (_closed || generation != _generation) return;
    if (engine is SubtitleCustomizationEngine) {
      (engine as SubtitleCustomizationEngine).setSubtitleAppearance(appearance);
    }
    if (choiceVersion == _choiceVersion) {
      _choice = choice ?? const {'mode': 'off'};
    }
    _ready = true;
    await _apply(force: true);
  }

  void updateTracks(List<SubtitleOption> value) {
    if (!_live || _closed) return;
    tracks = value.where(supported).toList();
    notifyListeners();
    if (_ready) _apply().catchError((Object _) {});
  }

  String target() {
    if (_choice['mode'] == 'off' || tracks.isEmpty) return 'no';
    if (_choice['mode'] == 'auto') return 'auto';
    final exact = tracks.where((t) => t.label == _choice['label']).firstOrNull;
    if (exact != null) return exact.id;
    final wanted = language(_choice['language'] as String?);
    if (wanted.isEmpty) return 'no';
    return tracks
            .where((t) => language(t.language) == wanted)
            .firstOrNull
            ?.id ??
        'no';
  }

  Future<void> _apply({bool force = false}) {
    final generation = _generation;
    final operation = _lane.then((_) async {
      if (_closed || !_ready || generation != _generation) return;
      final id = target();
      if (!force && selected == id) return;
      await engine.selectSubtitle(id);
      if (_closed || generation != _generation) return;
      selected = id;
      notifyListeners();
    });
    _lane = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> choose(String id) async {
    if (_closed || !_live) return;
    final track = tracks.where((t) => t.id == id).firstOrNull;
    if (id != 'no' && id != 'auto' && track == null) {
      throw StateError('Caption track unavailable');
    }
    final choice = id == 'no'
        ? <String, dynamic>{'mode': 'off'}
        : id == 'auto'
        ? <String, dynamic>{'mode': 'auto'}
        : <String, dynamic>{
            'mode': 'language',
            'language': track!.language,
            'label': track.label,
          };
    final previous = _choice;
    _choiceVersion++;
    _ready = true;
    _choice = choice;
    try {
      await _apply(force: true);
      await preferences.saveChoice(key, choice);
    } catch (_) {
      _choice = previous;
      try {
        await _apply(force: true);
      } catch (_) {
        selected = 'no';
        if (!_closed) notifyListeners();
      }
      rethrow;
    }
  }

  @override
  void dispose() {
    _closed = true;
    _generation++;
    super.dispose();
  }
}
