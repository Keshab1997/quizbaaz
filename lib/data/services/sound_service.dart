import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'hive_service.dart';

/// Central SFX player for the whole app — the single place every tap, ding,
/// buzz and fanfare goes through.
///
/// * Sounds are bundled under `assets/sounds/` and pre-warmed on startup.
/// * Taps play instantly without microtask delay.
/// * The on/off toggle lives in Profile → Settings (`setting_sound` in Hive)
///   and is read live on every [play].
class SoundService {
  SoundService._();

  static final SoundService instance = SoundService._();

  /// Setting key shared with UserProvider (Hive meta box).
  static const String settingKey = 'setting_sound';

  /// Timeout when pre-loading/setting source for an audio file.
  static const Duration _loadTimeout = Duration(milliseconds: 3500);

  /// Every sound the app can play, mapped to its asset file.
  static const Map<String, String> soundFiles = {
    // ---------------- UI (navigation / taps) ----------------
    'ui_click': 'ui_click.wav', // buttons, tabs, quick actions
    'ui_back': 'ui_back.wav', // back / pop / dialog close
    'ui_open': 'ui_open.wav', // dialog or screen open
    'ui_deny': 'ui_deny.wav', // locked / insufficient funds / already owned
    'ui_whoosh': 'ui_whoosh.wav', // screen transition, next question slide

    // ---------------- Quiz (daily + chapter) ----------------
    'quiz_start': 'quiz_start.wav', // quiz begins
    'quiz_correct': 'quiz_correct.wav', // correct answer (pleasant ding)
    'quiz_wrong': 'quiz_wrong.wav', // wrong answer (soft buzz)
    'quiz_timeout': 'quiz_timeout.wav', // timer ran out
    'quiz_tick': 'quiz_tick.wav', // last-5-seconds countdown tick
    'quiz_complete': 'quiz_complete.wav', // quiz finished fanfare
    'quiz_perfect': 'quiz_perfect.wav', // perfect score victory
    'lifeline_5050': 'lifeline_5050.wav', // 50-50 eliminator
    'lifeline_freeze': 'lifeline_freeze.wav', // freeze timer
    'lifeline_skip': 'lifeline_skip.wav', // skip question
    'lifeline_hint': 'lifeline_hint.wav', // hint reveal
    'lifeline_audience': 'lifeline_audience.wav', // audience poll
    'revive': 'revive.wav', // extra life revival
    'boost': 'boost.wav', // double points booster active
    'coin': 'coin.wav', // coins/gems credited

    // ---------------- Battle arena ----------------
    'battle_search': 'battle_search.wav', // radar ping (loops)
    'battle_found': 'battle_found.wav', // opponent found
    'battle_vs': 'battle_vs.wav', // VS slam intro
    'battle_count': 'battle_count.wav', // 3-2-1 countdown tick
    'battle_go': 'battle_go.wav', // GO!
    'battle_win': 'battle_win.wav', // victory fanfare
    'battle_lose': 'battle_lose.wav', // defeat sting

    // ---------------- Rewards / shop / streak ----------------
    'purchase': 'purchase.wav', // shop cha-ching
    'unlock': 'unlock.wav', // chapter unlocked / set cleared
    'fire': 'fire.wav', // streak flame crackle
    'champion': 'champion.wav', // daily winner / podium fanfare
  };

  /// Sound ids that loop until stopped (the battle search radar).
  static const Set<String> loopIds = {'battle_search'};

  final Map<String, AudioPlayer> _players = {};
  final Set<String> _failed = {};
  final Map<String, Future<AudioPlayer?>> _loading = {};
  bool _ready = false;

  /// True when sound effects are enabled (profile setting, defaults ON).
  static bool get enabled => HiveService.getMeta<bool>(settingKey) ?? true;

  /// Marks the service ready and pre-warms lightweight UI sounds in background.
  Future<void> init() async {
    _ready = true;
    unawaited(_preloadEssentialSounds());
  }

  /// Pre-warms essential UI sound players so tap response is instant.
  Future<void> _preloadEssentialSounds() async {
    if (!enabled) return;
    const essential = [
      'ui_click',
      'ui_back',
      'ui_open',
      'ui_deny',
      'ui_whoosh',
      'quiz_correct',
      'quiz_wrong',
      'coin',
    ];
    for (final id in essential) {
      if (_failed.contains(id) || _players.containsKey(id)) continue;
      try {
        await _ensurePlayer(id);
      } catch (_) {}
    }
  }

  Future<AudioPlayer?> _ensurePlayer(String id) {
    if (_failed.contains(id)) return Future<AudioPlayer?>.value(null);
    final existing = _players[id];
    if (existing != null) return Future<AudioPlayer?>.value(existing);
    return _loading.putIfAbsent(id, () => _load(id));
  }

  Future<AudioPlayer?> _load(String id) async {
    final file = soundFiles[id];
    if (file == null) {
      _failed.add(id);
      _loading.remove(id);
      return null;
    }
    AudioPlayer? player;
    try {
      player = AudioPlayer();
      await player.setReleaseMode(
        loopIds.contains(id) ? ReleaseMode.loop : ReleaseMode.stop,
      );
      // AssetSource paths are relative to the assets/ folder.
      await player
          .setSource(AssetSource('sounds/$file'))
          .timeout(_loadTimeout);
      _players[id] = player;
      return player;
    } catch (e) {
      debugPrint('SoundService: could not load "$file" – $e');
      _failed.add(id);
      try {
        await player?.dispose();
      } catch (_) {}
      return null;
    } finally {
      _loading.remove(id);
    }
  }

  /// Plays [id] once immediately. Non-blocking & synchronous for pre-loaded players.
  void play(String id, {double volume = 1.0}) {
    if (!enabled) return;
    if (!_ready) _ready = true;

    final existing = _players[id];
    if (existing != null) {
      _firePlay(existing, id, volume);
      return;
    }

    _ensurePlayer(id).then((player) {
      if (player != null) {
        _firePlay(player, id, volume);
      }
    });
  }

  void _firePlay(AudioPlayer player, String id, double volume) {
    try {
      player.setVolume(volume);
      player.seek(Duration.zero).then((_) {
        player.resume();
      }).catchError((_) {
        player.resume();
      });
    } catch (e) {
      try {
        final file = soundFiles[id];
        if (file != null) {
          player.play(AssetSource('sounds/$file'), volume: volume);
        }
      } catch (_) {}
    }
  }

  /// Starts looping [id] (e.g. the battle search radar).
  Future<void> loop(String id) async {
    if (!enabled) return;
    if (!_ready) _ready = true;
    final player = await _ensurePlayer(id);
    if (player == null) return;
    try {
      await player.stop();
      await player.seek(Duration.zero);
      await player.resume();
    } catch (e) {
      debugPrint('SoundService: loop "$id" failed – $e');
    }
  }

  /// Stops a looping sound.
  Future<void> stop(String id) async {
    final player = _players[id];
    if (player == null) return;
    try {
      await player.stop();
    } catch (e) {
      debugPrint('SoundService: stop "$id" failed – $e');
    }
  }

  /// Convenience UI sound triggers
  void playClick() => play('ui_click');
  void playBack() => play('ui_back');
  void playOpen() => play('ui_open');
  void playDeny() => play('ui_deny');
  void playWhoosh() => play('ui_whoosh');
  void playCorrect() => play('quiz_correct');
  void playWrong() => play('quiz_wrong');
  void playCoin() => play('coin');

  /// Releases every player (app shutdown).
  Future<void> dispose() async {
    for (final player in _players.values) {
      try {
        await player.dispose();
      } catch (_) {}
    }
    _players.clear();
    _failed.clear();
    _loading.clear();
    _ready = false;
  }
}
