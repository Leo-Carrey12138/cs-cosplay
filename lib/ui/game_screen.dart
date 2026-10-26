import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_config.dart';
import '../models/detection_frame.dart';
import '../models/player.dart';
import '../services/combat_rules.dart';
import '../services/feedback_service.dart';
import '../services/vision_service.dart';
import '../state/game_session.dart';
import '../util/frame_mapper.dart';
import '../util/camera_work_queue.dart';
import 'widgets/crosshair.dart';
import 'widgets/damage_flash.dart';
import 'widgets/death_overlay.dart';
import 'widgets/detection_overlay.dart';
import 'widgets/fire_button.dart';
import 'widgets/kill_feed.dart';
import 'widgets/player_hp_list.dart';
import 'widgets/target_picker.dart';
import 'widgets/zoom_controls.dart';

/// 战术终端风配色：深色底 + 荧光绿细线。
const Color _kTerminalBg = Color(0xFF0B0F12);
const Color _kTerminalAccent = Color(0xFF00E676);

/// 主战场：相机预览（contain，完整不裁切）+ 准星 + 绿框 + 开火按钮。
class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with WidgetsBindingObserver {
  late final GameSession _session;

  final VisionService _vision = VisionService();
  final FeedbackService _feedback = FeedbackService();

  CameraController? _camera;
  int _cameraGeneration = 0;
  int _detectionGeneration = 0;
  bool _foreground = true;
  final CameraWorkQueue _cameraQueue = CameraWorkQueue();
  Completer<void>? _analysisDone;
  int _streamGeneration = 0;
  double _zoom = 1.0;
  double _maxZoom = 1.0;
  bool _zoomReady = false;
  bool _zoomBusy = false;
  DateTime? _acceptFramesAfter;

  // 序列化初始化、变焦和释放，避免原生相机调用与 dispose 交叉。
  Future<void> _queueCamera(Future<void> Function() action) {
    return _cameraQueue.run(action).catchError((Object e) {
      debugPrint('相机操作失败: $e');
    });
  }

  bool _isCurrent(int generation) =>
      mounted && _foreground && generation == _cameraGeneration;

  void _invalidateDetection() {
    _detectionGeneration++;
    _lastDetection = null;
    _lastAnalyzeAt = null;
    _hitMarker = null;
  }

  int _sensorOrientation = 90;
  String? _cameraError;

  /// 取景 / 识别的相机分辨率。**只在这里定义一次**：
  /// 首次启动、回前台、出错后点"重试"全都走 _initCamera()，没有任何地方
  /// 会用低分辨率把相机重新 open 一遍（全仓库仅此一处 new CameraController）。
  ///
  /// 关于 veryHigh 的实际效果（重要，别被枚举名误导）：
  /// camera_android 的 ResolutionFeature.computeBestPreviewSize() 会把
  /// ordinal > high 的档位**强行降回 high** 再去选预览尺寸，而图像流用的
  /// ImageReader 和 Flutter 预览用的 SurfaceTexture 都取 getPreviewSize()
  /// （见 Camera.java open() / createCaptureSession()）。
  /// 所以 veryHigh 拿到的预览 + 图像流 = 720p（常见 1280×720），比原来的
  /// medium（480p，常见 720×480）像素多约 2.7 倍，画面明显变清晰；
  /// veryHigh 多出来的 1080p 只写进 captureSize（拍照用），本 App 不拍照，
  /// 不会因此多付任何代价。
  static const ResolutionPreset _resolutionPreset = ResolutionPreset.veryHigh;

  // ---- 检测状态 ----
  DetectionFrame? _lastDetection;
  DateTime? _lastAnalyzeAt;
  bool _analyzing = false;

  /// 只打印一次的首帧诊断（确认分辨率/帧格式）
  bool _loggedFirstFrame = false;

  // ---- 布局尺寸（用于坐标映射）----
  Size _viewSize = const Size(360, 720);

  // ---- 开火冷却 ----
  DateTime? _cooldownUntil;
  Timer? _cooldownTicker;

  // ---- 命中提示 ----
  String? _hitMarker;
  Color _hitMarkerColor = Colors.white;
  Timer? _hitMarkerTimer;

  // ---- 阵亡锁定 ----
  bool _cameraLockedForDeath = false;

  /// 防止连点「离开房间」导致连续 pop
  bool _leavingRoom = false;

  StreamSubscription<int>? _damageSub;
  StreamSubscription<String>? _toastSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _session = context.read<GameSession>();
    _session.addListener(_onSessionChanged);
    _cameraLockedForDeath = _session.iAmDead;

    // 受击：震动 + 音效（红光闪烁由 DamageFlashLayer 自己订阅同一个流）
    _damageSub = _session.onDamaged.listen((_) {
      unawaited(_feedback.vibrateDamage());
      unawaited(_feedback.playHit());
    });
    _toastSub = _session.onToast.listen(_showToast);

    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    await _feedback.init();
    if (!mounted) return;
    try {
      await _vision.init();
    } catch (e) {
      debugPrint('Pose 检测器初始化失败: $e');
    }
    if (mounted && _foreground) await _initCamera();
  }

  // ------------------------------------------------------------------
  // 相机
  // ------------------------------------------------------------------

  Future<void> _initCamera() {
    final generation = ++_cameraGeneration;
    return _queueCamera(() => _openCamera(generation));
  }

  Future<void> _disposeController(CameraController? controller) async {
    if (controller == null) return;
    controller.removeListener(_onCameraValueChanged);
    try {
      if (controller.value.isStreamingImages)
        await controller.stopImageStream();
    } catch (_) {}
    try {
      await controller.dispose();
    } catch (e) {
      debugPrint('释放相机失败: $e');
    }
  }

  Future<void> _openCamera(int generation) async {
    if (!_isCurrent(generation)) return;
    final previous = _camera;
    setState(() {
      _camera = null;
      _zoomReady = false;
      _zoomBusy = false;
      _zoom = 1.0;
      _maxZoom = 1.0;
      _invalidateDetection();
    });
    await _disposeController(previous);
    CameraController? pending;
    try {
      final cameras = await availableCameras();
      if (!_isCurrent(generation)) return;
      if (cameras.isEmpty) {
        if (mounted) setState(() => _cameraError = '没有找到可用的摄像头');
        return;
      }
      final description = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      _sensorOrientation = description.sensorOrientation;

      final controller = CameraController(
        description,
        // 分辨率唯一来源，见 _resolutionPreset 的注释。
        _resolutionPreset,
        enableAudio: false, // 不需要麦克风权限
        // 声明 nv21：插件底层用 YUV_420_888 采集，再在 native 侧转成单 plane
        // 的 NV21 交给 Dart，正好能零拷贝喂给 ML Kit。
        imageFormatGroup: ImageFormatGroup.nv21,
      );
      pending = controller;
      await controller.initialize();
      if (!_isCurrent(generation)) return;
      var maxZoom = 1.0;
      var zoomReady = false;
      try {
        final minimum = await controller.getMinZoomLevel();
        final maximum = await controller.getMaxZoomLevel();
        if (minimum.isFinite &&
            maximum.isFinite &&
            minimum <= 1.0 &&
            maximum >= 1.0) {
          await controller.setZoomLevel(1.0);
          maxZoom = maximum;
          zoomReady = true;
        }
      } catch (e) {
        debugPrint('变焦初始化失败（保留相机预览）: $e');
      }

      // 一次性诊断：确认 CameraX 实际给了多少分辨率（ResolutionPreset 只是"目标"，
      // CameraX 会按设备能力回落到最接近的较低档，所以必须以运行时日志为准）。
      debugPrint(
        '[相机] 预览 previewSize=${controller.value.previewSize} '
        'aspectRatio=${controller.value.aspectRatio.toStringAsFixed(3)} '
        'sensorOrientation=$_sensorOrientation '
        'preset=$_resolutionPreset',
      );

      if (!_isCurrent(generation)) return;
      _loggedFirstFrame = false;
      // 初始化完成前不发布 controller，失效初始化由 finally 独占释放。
      // 后台事件因此不会重复 dispose 这个仍在初始化的实例。
      if (_session.iAmDead) {
        await controller.pausePreview();
      } else {
        await _startImageStream(controller, generation);
      }
      if (!_isCurrent(generation)) return;
      controller.addListener(_onCameraValueChanged);
      setState(() {
        _camera = controller;
        _cameraError = null;
        _zoom = 1.0;
        _maxZoom = maxZoom;
        _zoomReady = zoomReady;
      });
      pending = null;
    } on CameraException catch (e) {
      if (_isCurrent(generation)) {
        setState(
          () =>
              _cameraError = '相机不可用（${e.code}）：${e.description ?? ''}\n请检查相机权限',
        );
      }
    } catch (e) {
      if (_isCurrent(generation)) {
        setState(() => _cameraError = '相机初始化失败：$e');
      }
    } finally {
      if (pending != null) {
        if (identical(_camera, pending)) {
          _camera = null;
          _zoomReady = false;
          if (mounted) setState(() {});
        }
        await _disposeController(pending);
      }
    }
  }

  void _onCameraValueChanged() {
    if (!mounted || _camera == null) return;
    setState(() {
      if (_camera!.value.hasError) {
        _cameraError = '相机不可用：${_camera!.value.errorDescription ?? ''}';
        _zoomReady = false;
        _invalidateDetection();
      }
    });
  }

  bool get _cameraUsable {
    final value = _camera?.value;
    return mounted &&
        _foreground &&
        _cameraError == null &&
        value != null &&
        value.isInitialized &&
        !value.hasError &&
        !value.isPreviewPaused &&
        value.isStreamingImages;
  }

  bool get _canZoom =>
      _cameraUsable && _zoomReady && !_zoomBusy && !_session.iAmDead;

  Future<void> _startImageStream(CameraController controller, int generation) {
    final streamGeneration = ++_streamGeneration;
    return controller.startImageStream((image) {
      if (_isCurrent(generation) && streamGeneration == _streamGeneration) {
        unawaited(_onCameraFrame(image));
      }
    });
  }

  Future<void> _changeZoom(double delta) async {
    if (!_canZoom) return;
    final controller = _camera!;
    final generation = _cameraGeneration;
    final target = (_zoom + delta).clamp(1.0, _maxZoom).toDouble();
    if (target == _zoom) return;
    setState(() {
      _zoomBusy = true;
      _invalidateDetection();
    });
    await _queueCamera(() async {
      try {
        if (!_isCurrent(generation) ||
            _session.iAmDead ||
            !identical(_camera, controller))
          return;
        // 断开旧图像流，旧回调和旧推理不能跨倍率继续参与命中。
        await controller.stopImageStream();
        ++_streamGeneration;
        if (!_isCurrent(generation) || _session.iAmDead) return;
        await controller.setZoomLevel(target);
        if (!_isCurrent(generation)) return;
        setState(() => _zoom = target);
      } catch (e) {
        if (_isCurrent(generation)) _showToast('变焦失败，请重试');
        debugPrint('变焦失败: $e');
      } finally {
        if (_isCurrent(generation)) {
          await _syncCameraLock();
        }
        if (_isCurrent(generation)) {
          setState(() {
            _zoomBusy = false;
            // 丢弃切换前的推理以及管线内可能残留的旧帧。
            _invalidateDetection();
            _acceptFramesAfter = DateTime.now().add(Cfg.detectInterval);
          });
        }
      }
    });
  }

  /// 每帧回调。抽帧：300ms 一帧 + 忙等跳过，保证不卡 UI。
  Future<void> _onCameraFrame(CameraImage image) async {
    // 首帧诊断：确认 ML Kit 实际拿到的分辨率/格式/平面数。
    // 断言一下 toNv21() 走的是哪条路径（1 plane = 直接复用，3 plane = 手工重排）。
    if (!_loggedFirstFrame) {
      _loggedFirstFrame = true;
      final expected = image.width * image.height * 3 ~/ 2;
      debugPrint(
        '[图像流] 首帧 ${image.width}x${image.height} '
        'format=${image.format.group} planes=${image.planes.length} '
        'plane0Bytes=${image.planes.isEmpty ? 0 : image.planes.first.bytes.length} '
        'expectNv21Bytes=$expected',
      );
    }

    if (!_cameraUsable || _zoomBusy || _session.iAmDead) return;
    if (_acceptFramesAfter != null &&
        DateTime.now().isBefore(_acceptFramesAfter!))
      return;
    if (_analyzing) return;
    final generation = _detectionGeneration;
    final now = DateTime.now();
    final last = _lastAnalyzeAt;
    if (last != null && now.difference(last) < Cfg.detectInterval) return;

    _analyzing = true;
    final done = Completer<void>();
    _analysisDone = done;
    _lastAnalyzeAt = now;
    try {
      final frame = await _vision.analyze(image, _sensorOrientation);
      if (!mounted ||
          frame == null ||
          generation != _detectionGeneration ||
          !_foreground ||
          _session.iAmDead)
        return;
      setState(() => _lastDetection = frame);
    } catch (e) {
      debugPrint('本地推理失败: $e');
    } finally {
      _analyzing = false;
      done.complete();
    }
  }

  /// 相机画面在布局里的"逻辑尺寸"（竖屏方向）。
  ///
  /// 只认 controller 自己的 previewSize —— 这是唯一能保证"预览盒子宽高比 ==
  /// 相机真实画面宽高比"的来源，因为 CameraPreview 内部的 AspectRatio 用的
  /// 就是同一个值（1 / controller.value.aspectRatio）。
  ///
  /// 注意不要用 detection.frameSize 来定预览盒子：两者在正常情况下确实相等
  /// （图像流 ImageReader 的尺寸就是 previewSize，旋转 90° 后宽高互换），
  /// 但一旦不相等，SizedBox 给的是**紧约束**，RenderAspectRatio 在紧约束下
  /// 会直接返回 constraints.smallest 而完全忽略 aspectRatio，
  /// 于是画面就被拉伸变形了。检测帧尺寸只用来画绿框，不参与布局。
  Size? _previewSize() {
    final preview = _camera?.value.previewSize;
    if (preview == null || preview.isEmpty) return null;
    // 竖屏：Android CamcorderProfile 给的是横向尺寸，转成竖直方向
    return preview.width > preview.height
        ? Size(preview.height, preview.width)
        : preview;
  }

  // ------------------------------------------------------------------
  // 生命周期（camera 插件不自动处理，必须自己来）
  // ------------------------------------------------------------------

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _foreground = true;
      unawaited(_initCamera());
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _foreground = false;
      ++_cameraGeneration;
      ++_streamGeneration;
      final controller = _camera;
      setState(() {
        _camera = null;
        _zoomReady = false;
        _zoomBusy = false;
        _invalidateDetection();
      });
      unawaited(_queueCamera(() => _disposeController(controller)));
    }
  }

  // ------------------------------------------------------------------
  // 会话状态变化（阵亡 → 锁相机；重开 → 解锁）
  // ------------------------------------------------------------------

  void _onSessionChanged() {
    final dead = _session.iAmDead;
    if (dead == _cameraLockedForDeath) return;
    _cameraLockedForDeath = dead;
    setState(_invalidateDetection);
    // 队列执行时读取最新会话状态，旧的死亡任务不能覆盖复活/重开。
    unawaited(_queueCamera(_syncCameraLock));
  }

  Future<void> _syncCameraLock() async {
    final controller = _camera;
    final generation = _cameraGeneration;
    if (!_isCurrent(generation) ||
        controller == null ||
        !controller.value.isInitialized ||
        controller.value.hasError)
      return;
    try {
      if (_session.iAmDead) {
        ++_streamGeneration;
        if (controller.value.isStreamingImages)
          await controller.stopImageStream();
        if (!_isCurrent(generation)) return;
        if (_session.iAmDead && !controller.value.isPreviewPaused) {
          await controller.pausePreview();
        }
      } else {
        if (controller.value.isPreviewPaused) await controller.resumePreview();
        if (!_isCurrent(generation) || _session.iAmDead) return;
        if (!controller.value.isStreamingImages) {
          await _startImageStream(controller, generation);
        }
      }
    } catch (e) {
      if (_isCurrent(generation)) {
        setState(() {
          _cameraError = '相机恢复失败，请重试：$e';
          _zoomReady = false;
          _invalidateDetection();
        });
      }
    }
  }

  // ------------------------------------------------------------------
  // 开火
  // ------------------------------------------------------------------

  bool get _cooling =>
      _cooldownUntil != null && DateTime.now().isBefore(_cooldownUntil!);

  double get _cooldownProgress {
    final until = _cooldownUntil;
    if (until == null) return 0;
    final remain = until.difference(DateTime.now()).inMilliseconds;
    return (remain / Cfg.fireCooldown.inMilliseconds)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  void _startCooldown() {
    _cooldownTicker?.cancel();
    setState(() => _cooldownUntil = DateTime.now().add(Cfg.fireCooldown));
    _cooldownTicker = Timer.periodic(const Duration(milliseconds: 60), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (!_cooling) {
        timer.cancel();
        setState(() => _cooldownUntil = null);
      } else {
        setState(() {});
      }
    });
  }

  Future<void> _fire() async {
    if (_session.iAmDead || !_cameraUsable || _zoomBusy) return;
    if (_cooling) return;

    _startCooldown();
    unawaited(_feedback.playFire()); // 换弹夹音效

    final detection = _lastDetection;
    if (detection == null) {
      _showHitMarker('还没识别到画面', Colors.amber);
      return;
    }

    // ---- 判定：准星点是否落在某个 person 框内 ----
    final mapper = FrameMapper(
      frameSize: detection.frameSize,
      viewSize: _viewSize,
    );
    final center = mapper.viewCenter;

    TargetBox? bestBox;
    var bestRatio = 0.0;
    for (final box in detection.targetBoxes) {
      final viewRect = mapper.rectToView(box.rect);
      if (!viewRect.contains(center)) continue; // 十字准星不在此框内
      final ratio = mapper.visibleAreaRatio(box.rect);
      if (ratio > bestRatio) {
        bestRatio = ratio;
        bestBox = box;
      }
    }

    if (bestBox == null) {
      _showHitMarker('脱靶', Colors.white);
      return;
    }

    // 距离过滤：太小 = 超出射程
    if (bestRatio < Cfg.minTargetAreaRatio) {
      _showHitMarker(
        '超出射程（${(bestRatio * 100).toStringAsFixed(1)}%）',
        Colors.orange,
      );
      return;
    }

    // ---- hit_success ----
    _showHitMarker(
      '命中！目标占屏 ${(bestRatio * 100).toStringAsFixed(1)}%',
      const Color(0xFF00E676),
    );
    unawaited(_feedback.playHitMarker());

    // 目标列表只展示存活敌人；队友判定仍由服务端事务重新核对。
    final candidates = _session.aliveEnemies.take(5).toList();
    if (candidates.isEmpty) {
      _showHitMarker('当前没有可攻击的敌人', Colors.white70);
      _showToast('当前没有可攻击的敌人');
      return;
    }
    if (!mounted) return;

    final detectionGeneration = _detectionGeneration;
    final target = await showTargetPicker(
      context,
      candidates: candidates,
      hitPercent: bestRatio * 100, // 交给玩家估算距离
      serverNowMs: _session.serverNowMs,
    );
    if (target == null || !mounted) return;
    if (_session.iAmDead ||
        !_cameraUsable ||
        _zoomBusy ||
        detectionGeneration != _detectionGeneration) {
      _showToast('画面已变化，请重新瞄准');
      return;
    }

    final decision = await _session.confirmHit(target.id);
    if (!mounted) return;
    _handleCombatDecision(decision, target);
  }

  void _handleCombatDecision(CombatDecision decision, Player target) {
    switch (decision.outcome) {
      case CombatOutcome.applied:
        _showHitMarker(
          '命中 ${target.name} -${Cfg.damagePerHit} HP（剩 ${decision.hpAfter}）',
          const Color(0xFF00E676),
        );
      case CombatOutcome.killed:
        _showHitMarker('击倒 ${target.name}！', const Color(0xFF00E676));
        unawaited(_feedback.playHitMarker());
      case CombatOutcome.friendlyBlocked:
        _showHitMarker('队友免疫伤害', const Color(0xFFFFC107));
        _showToast('队友免疫伤害');
      case CombatOutcome.invincibleBlocked:
        _showHitMarker('目标处于复活保护', const Color(0xFF40C4FF));
        _showToast('目标处于复活保护');
      case CombatOutcome.targetUnavailable:
        _showHitMarker('目标已阵亡或已离开', Colors.white70);
        _showToast('目标已阵亡或已离开');
      case CombatOutcome.selfBlocked:
        _showToast('不能攻击自己');
      case CombatOutcome.attackerUnavailable:
        _showToast('你已阵亡，无法开火');
      case CombatOutcome.failed:
        _showToast('网络异常，本次伤害未生效');
    }
  }

  // ------------------------------------------------------------------
  // 小提示
  // ------------------------------------------------------------------

  void _showHitMarker(String text, Color color) {
    _hitMarkerTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _hitMarker = text;
      _hitMarkerColor = color;
    });
    _hitMarkerTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted && _hitMarker == text) {
        setState(() => _hitMarker = null);
      }
    });
  }

  void _showToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(milliseconds: 1600),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xE6151B21),
        ),
      );
  }

  Future<void> _confirmReset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('重置游戏？'),
        content: const Text('保留当前队伍，所有玩家满血复活，击杀数清零，立即开始新一局。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('开始新局'),
          ),
        ],
      ),
    );
    if (ok == true) {
      final resetOk = await _session.resetGame();
      if (mounted && resetOk) {
        setState(_invalidateDetection);
        _onSessionChanged();
        _showToast('已重置，新一局开始');
      }
    }
  }

  Future<void> _leaveRoom() async {
    if (_leavingRoom) return;
    _leavingRoom = true;
    await _session.leave();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  // ------------------------------------------------------------------
  // build
  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final session = context.watch<GameSession>();

    return Scaffold(
      backgroundColor: _kTerminalBg,
      // 整体三段式：上终端面板 / 相机区（contain + 黑边）/ 下终端面板。
      // 相机画面独占中间，不被任何 HUD 遮挡。
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Column(
            children: <Widget>[
              _buildTopTerminal(session),
              Expanded(child: _buildCameraStage()),
              _buildBottomTerminal(session),
            ],
          ),

          // 闪光/阵亡/错误这些确实需要盖住整屏的，才放在外层。
          DamageFlashLayer(damageStream: session.onDamaged),

          // 复活保护：非遮挡式提示，不挡准星、不拦截操作
          if (!session.iAmDead) _buildInvincibleShield(session),

          if (session.iAmDead)
            ValueListenableBuilder<int>(
              valueListenable: session.respawnRemainingMs,
              builder: (context, remaining, _) => DeathOverlay(
                remainingMs: remaining,
                totalMs: Cfg.respawnDelay.inMilliseconds,
                onLeave: _leaveRoom,
              ),
            ),

          if (_cameraError != null) _buildCameraError(),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // 三段式布局
  // ------------------------------------------------------------------

  /// 上黑边面板：房间信息 + 全员血条 + 战报。
  Widget _buildTopTerminal(GameSession session) {
    return Container(
      decoration: const BoxDecoration(
        color: _kTerminalBg,
        border: Border(bottom: BorderSide(color: _kTerminalAccent, width: 1.5)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              RoomHeader(
                roomId: session.roomId,
                playerCount: session.players.length,
                isHost: session.isHost,
                onReset: _confirmReset,
                alphaScore: session.alphaScore,
                bravoScore: session.bravoScore,
              ),
              const SizedBox(height: 6),
              PlayerHpList(
                players: session.sortedPlayers,
                myId: session.playerId,
                serverNow: () => session.serverNowMs,
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: KillFeed(items: session.feed),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 相机区：预览用 contain 完整显示，四周黑边即 #0B0F12。
  ///
  /// 这里用 LayoutBuilder 取到的是**预览区**尺寸并写进 _viewSize，
  /// 绿框叠加和开火判定的 FrameMapper 都用它 —— 不能再用整屏尺寸，
  /// 否则黑边偏移会算错。
  Widget _buildCameraStage() {
    return LayoutBuilder(
      builder: (context, constraints) {
        _viewSize = constraints.biggest;
        final frame = _previewSize();

        return ColoredBox(
          color: _kTerminalBg,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              _buildPreview(),

              // 画面边框描边（和预览同一个 contain 算法，严丝合缝）
              if (frame != null) _buildStageFrame(frame),

              DetectionOverlay(frame: _lastDetection),
              const Crosshair(),

              // 命中/脱靶提示始终占位，避免命中时后面的 widget 索引位移
              _buildHitMarker(),
            ],
          ),
        );
      },
    );
  }

  /// 下黑边面板：我的血量 + 变焦控件 + 开火按钮。
  Widget _buildBottomTerminal(GameSession session) {
    return Container(
      decoration: const BoxDecoration(
        color: _kTerminalBg,
        border: Border(top: BorderSide(color: _kTerminalAccent, width: 1.5)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 18, 22),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildMyStatus(session),
                    const SizedBox(height: 4),
                    ZoomControls(
                      zoom: _zoom,
                      maxZoom: _maxZoom,
                      enabled: _canZoom,
                      onDecrease: () => unawaited(_changeZoom(-0.5)),
                      onIncrease: () => unawaited(_changeZoom(0.5)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (!session.iAmDead)
                FireButton(
                  onPressed: _fire,
                  cooling: _cooling,
                  cooldownProgress: _cooldownProgress,
                  enabled: _cameraUsable && !_zoomBusy,
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 复活保护倒计时：非遮挡式小胶囊，放在准星下方，不拦截触摸。
  Widget _buildInvincibleShield(GameSession session) {
    return ValueListenableBuilder<int>(
      valueListenable: session.invincibleRemainingMs,
      builder: (context, remaining, _) {
        if (remaining <= 0) return const SizedBox.shrink();
        final seconds = (remaining / 1000).toStringAsFixed(1);
        return Align(
          alignment: const Alignment(0, 0.58),
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xCC06222E),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF40C4FF), width: 1.2),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(Icons.shield, size: 16, color: Color(0xFF40C4FF)),
                  const SizedBox(width: 6),
                  Text(
                    '复活保护 ${seconds}s',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF40C4FF),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// 命中/脱靶提示（始终占位，null 时是空盒子）
  Widget _buildHitMarker() {
    final text = _hitMarker;
    if (text == null) return const SizedBox.shrink();
    return Align(
      alignment: const Alignment(0, -0.42),
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xB3000000),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _hitMarkerColor, width: 1.5),
          ),
          child: Text(
            text,
            style: TextStyle(
              color: _hitMarkerColor,
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPreview() {
    final controller = _camera;
    final box = _previewSize();
    if (controller == null || !controller.value.isInitialized || box == null) {
      return const ColoredBox(
        color: _kTerminalBg,
        child: Center(
          child: CircularProgressIndicator(color: _kTerminalAccent),
        ),
      );
    }
    // contain（完整显示、不裁切）的三层结构：
    //   1) SizedBox 用相机真实宽高比（_previewSize）给出画面原始比例，
    //      并且和 CameraPreview 内部 AspectRatio 同源 → 不会各说各话；
    //   2) FittedBox(fit: contain) 只做**等比**缩放并居中（等价于 CSS
    //      object-fit: contain），整幅画面都在、两边多出来的就是黑边；
    //   3) ClipRect 把区域剪干净，避免溢出到相邻 HUD 面板上。
    // 这套缩放规则和 FrameMapper 的 scale = min(w/W, h/H) + offset 完全一致，
    // 所以绿框、准星和真实画面始终对得上。
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: box.width,
          height: box.height,
          child: CameraPreview(controller),
        ),
      ),
    );
  }

  /// 画面四周的荧光绿细线描边（战术终端感）。
  /// 复用 FrameMapper 的 contain 几何，所以描边永远贴着画面真实边缘。
  Widget _buildStageFrame(Size frame) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _StageFramePainter(frameSize: frame),
        size: Size.infinite,
      ),
    );
  }

  /// 左下角：我的名字 / 血量 / AI 状态
  Widget _buildMyStatus(GameSession session) {
    final ratio = (session.myHp / Cfg.maxHp).clamp(0.0, 1.0).toDouble();
    final detection = _lastDetection;
    // 姿态检测方案下的三种状态（不再有「全局 person 置信度」这种模糊说法）：
    //   · 还没出结果          → 识别中
    //   · 有结果但没框住准星  → 视野内无目标
    //   · 锁定到姿态          → 已锁定目标（附带姿态得分）
    // 歧义分支目前不可达（ML Kit Pose 单姿态），留着是为了将来换多人检测器。
    final String aiText;
    if (detection == null) {
      aiText = 'AI 识别中…';
    } else if (detection.ambiguous) {
      aiText = 'AI：目标重叠·请手动指认';
    } else if (!detection.hasTarget) {
      aiText = 'AI：视野内无目标';
    } else {
      aiText =
          'AI：已锁定目标 '
          '${(detection.targetConfidence * 100).toStringAsFixed(0)}%';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xB3000000),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  session.nickname,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${session.myHp} HP',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: ratio > 0.6
                      ? const Color(0xFF00E676)
                      : ratio > 0.3
                      ? const Color(0xFFFFC107)
                      : const Color(0xFFFF5252),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation<Color>(
                ratio > 0.6
                    ? const Color(0xFF00E676)
                    : ratio > 0.3
                    ? const Color(0xFFFFC107)
                    : const Color(0xFFFF5252),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            aiText,
            style: const TextStyle(fontSize: 11, color: Colors.white60),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraError() {
    return ColoredBox(
      color: const Color(0xCC000000),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.no_photography_outlined,
                size: 56,
                color: Colors.orange,
              ),
              const SizedBox(height: 14),
              Text(
                _cameraError!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, height: 1.6),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () {
                  setState(() => _cameraError = null);
                  unawaited(_initCamera());
                },
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _session.removeListener(_onSessionChanged);
    _damageSub?.cancel();
    _toastSub?.cancel();
    _cooldownTicker?.cancel();
    _hitMarkerTimer?.cancel();

    _foreground = false;
    ++_cameraGeneration;
    ++_streamGeneration;
    _invalidateDetection();
    final controller = _camera;
    _camera = null;
    unawaited(_queueCamera(() => _disposeController(controller)));
    // 不在 ML Kit 仍处理图像时 close detector。
    final analysisDone = _analysisDone?.future;
    unawaited(() async {
      if (analysisDone != null) await analysisDone;
      await _vision.dispose();
    }());
    unawaited(_feedback.dispose());
    // 离开房间：立即从数据库移除自己（掉线则由 onDisconnect 兜底）
    unawaited(_session.leave());

    super.dispose();
  }
}

/// 画面四周的荧光绿细线描边 + 四角短线，做出"战术终端取景框"的味道。
///
/// 边框位置由 FrameMapper（contain 几何）算出来，和 FittedBox(contain)
/// 摆放画面的规则完全一致，所以描边永远正好压在画面边缘上。
class _StageFramePainter extends CustomPainter {
  _StageFramePainter({required this.frameSize});

  final Size frameSize;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final mapper = FrameMapper(frameSize: frameSize, viewSize: size);
    if (!mapper.isValid) return;

    final rect = mapper.imageRect;

    // 主体一圈细线
    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = _kTerminalAccent.withValues(alpha: 0.75),
    );

    // 四角加粗短线，强调取景框
    final cornerLen = (rect.shortestSide * 0.08).clamp(10.0, 28.0).toDouble();
    final corner = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.square
      ..color = _kTerminalAccent;

    // 左上
    canvas.drawLine(rect.topLeft, rect.topLeft + Offset(cornerLen, 0), corner);
    canvas.drawLine(rect.topLeft, rect.topLeft + Offset(0, cornerLen), corner);
    // 右上
    canvas.drawLine(
      rect.topRight,
      rect.topRight + Offset(-cornerLen, 0),
      corner,
    );
    canvas.drawLine(
      rect.topRight,
      rect.topRight + Offset(0, cornerLen),
      corner,
    );
    // 左下
    canvas.drawLine(
      rect.bottomLeft,
      rect.bottomLeft + Offset(cornerLen, 0),
      corner,
    );
    canvas.drawLine(
      rect.bottomLeft,
      rect.bottomLeft + Offset(0, -cornerLen),
      corner,
    );
    // 右下
    canvas.drawLine(
      rect.bottomRight,
      rect.bottomRight + Offset(-cornerLen, 0),
      corner,
    );
    canvas.drawLine(
      rect.bottomRight,
      rect.bottomRight + Offset(0, -cornerLen),
      corner,
    );
  }

  @override
  bool shouldRepaint(covariant _StageFramePainter old) =>
      old.frameSize != frameSize;
}
