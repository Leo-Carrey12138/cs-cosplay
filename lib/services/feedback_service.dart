import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:vibration/vibration.dart';

import '../app_config.dart';

/// 音效 + 震动。所有异常都吞掉：没有马达 / 音频焦点被占 / 素材缺失，
/// 都不能让游戏崩掉。
class FeedbackService {
  FeedbackService();

  final AudioPlayer _firePlayer = AudioPlayer();
  final AudioPlayer _hitPlayer = AudioPlayer();

  bool _soundOn = true;
  bool _vibrationSupported = false;

  bool get soundOn => _soundOn;

  Future<void> init() async {
    try {
      await _firePlayer.setReleaseMode(ReleaseMode.stop);
      await _hitPlayer.setReleaseMode(ReleaseMode.stop);
      await _firePlayer.setVolume(0.9);
      await _hitPlayer.setVolume(1.0);
    } catch (e) {
      debugPrint('音频初始化失败: $e');
    }
    try {
      _vibrationSupported = await Vibration.hasVibrator();
    } catch (_) {
      _vibrationSupported = false;
    }
  }

  void toggleSound() {
    _soundOn = !_soundOn;
  }

  Future<void> _play(AudioPlayer player, String asset) async {
    if (!_soundOn) return;
    try {
      await player.stop();
      await player.play(AssetSource(asset));
    } catch (e) {
      debugPrint('播放 $asset 失败: $e');
    }
  }

  /// 开火 / 换弹夹声（开火方听）
  Future<void> playFire() => _play(_firePlayer, 'audio/reload.wav');

  /// 受击声（被打方听）
  Future<void> playHit() => _play(_hitPlayer, 'audio/hit.wav');

  /// 命中反馈（打人方听），复用受击音效，音量小一点
  Future<void> playHitMarker() => _play(_hitPlayer, 'audio/hit.wav');

  /// 强烈震动 500ms
  Future<void> vibrateDamage() async {
    if (!_vibrationSupported) return;
    try {
      final amplitude = await Vibration.hasAmplitudeControl();
      if (amplitude) {
        // Android 8.0+ 能用振幅，直接拉满，手感更"强烈"
        Vibration.vibrate(
          duration: Cfg.damageVibration.inMilliseconds,
          amplitude: 255,
        );
      } else {
        Vibration.vibrate(duration: Cfg.damageVibration.inMilliseconds);
      }
    } catch (e) {
      debugPrint('震动失败: $e');
    }
  }

  Future<void> dispose() async {
    try {
      await _firePlayer.dispose();
      await _hitPlayer.dispose();
    } catch (_) {}
  }
}
