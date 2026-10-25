import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_config.dart';
import '../state/game_session.dart';
import 'game_screen.dart';
import 'theme/csgo_theme.dart';

/// 进入页：昵称 + 4 位房间号 → 加入（房间不存在会自动创建）
class JoinScreen extends StatefulWidget {
  const JoinScreen({super.key});

  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  final TextEditingController _nameCtrl = TextEditingController(
    text: '玩家${math.Random().nextInt(900) + 100}',
  );
  final TextEditingController _roomCtrl = TextEditingController(
    text: (math.Random().nextInt(9000) + 1000).toString(),
  );
  final FocusNode _roomFocus = FocusNode();
  bool _submitting = false;

  /// 随机房号后的即时反馈（用户一改房号就清掉，避免显示过期信息）
  String? _roomNotice;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _roomCtrl.dispose();
    _roomFocus.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    if (_submitting) return;
    final name = _nameCtrl.text.trim();
    final room = _roomCtrl.text.trim();

    if (name.isEmpty) {
      _showError('请输入昵称');
      return;
    }
    if (room.length != 4 || int.tryParse(room) == null) {
      _showError('房间号必须是 4 位数字');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _submitting = true);
    final session = context.read<GameSession>();
    final ok = await session.join(room: room, name: name);
    if (!mounted) return;
    setState(() => _submitting = false);

    if (ok) {
      // 用 push 而不是 pushReplacement：这样战场上点"离开房间"能 pop 回本页。
      // 如果用 pushReplacement，GameScreen 就是栈底，pop 之后就只剩黑屏了。
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const GameScreen()),
      );
    } else {
      _showError(session.errorMessage ?? '加入失败，检查网络与 Firebase 配置');
    }
  }

  void _randomizeRoom() {
    final room = (math.Random().nextInt(9000) + 1000).toString();
    HapticFeedback.selectionClick();
    setState(() {
      _roomCtrl.text = room;
      _roomNotice = '已生成新房号 · $room';
    });
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: CsColors.dangerDeep,
          content: Row(
            children: <Widget>[
              const Icon(Icons.warning_amber_rounded,
                  size: 18, color: CsColors.danger),
              const SizedBox(width: 8),
              Expanded(child: Text(message)),
            ],
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CsgoBackdrop(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final bool short = constraints.maxHeight < 700;
              return SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(
                  short ? 18 : 24,
                  short ? 16 : 28,
                  short ? 18 : 24,
                  24,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        _buildTopBar(),
                        SizedBox(height: short ? 20 : 30),
                        _buildTitle(),
                        SizedBox(height: short ? 18 : 24),
                        const CsgoDivider(label: 'JOIN A MATCH'),
                        SizedBox(height: short ? 14 : 18),
                        _buildIdentityPanel(),
                        const SizedBox(height: 14),
                        _buildRoomPanel(),
                        const SizedBox(height: 18),
                        _buildDeployButton(),
                        const SizedBox(height: 10),
                        const Text(
                          '进入后把摄像头对准对手，准星落在人形框内再开火。',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: CsColors.textMuted,
                            fontSize: 10.5,
                            height: 1.5,
                          ),
                        ),
                        SizedBox(height: short ? 18 : 24),
                        _buildRulesPanel(),
                        const SizedBox(height: 18),
                        const CsgoDivider(label: 'SYSTEM'),
                        const SizedBox(height: 10),
                        const Text(
                          'ML KIT · FIREBASE REALTIME DB · CAMERA',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: CsColors.textMuted,
                            fontSize: 8.5,
                            letterSpacing: 1.6,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Row(
      children: <Widget>[
        Container(width: 9, height: 9, color: CsColors.accent),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            'CS // TACTICAL OPS',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: CsColors.accent,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 2.2,
            ),
          ),
        ),
        const CsgoTag(label: '单房 ${Cfg.maxPlayers} 人'),
      ],
    );
  }

  Widget _buildTitle() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          '真人 CS',
          style: TextStyle(
            fontSize: 40,
            height: 1.0,
            fontWeight: FontWeight.w900,
            letterSpacing: 3,
            color: CsColors.textStrong,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Container(width: 30, height: 2, color: CsColors.accent),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'TACTICAL COSPLAY ARENA',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: CsColors.accentDim,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2.4,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          '摄像头 + 本地 AI 识别 + 实时房间\n局域网无外设对战',
          style: TextStyle(
            color: CsColors.textMuted,
            fontSize: 12.5,
            height: 1.55,
          ),
        ),
      ],
    );
  }

  Widget _buildIdentityPanel() {
    return CsgoPanel(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const CsgoSectionHeader(
            index: '01',
            title: '作战代号',
            trailing: CsgoTag(label: 'CALLSIGN'),
          ),
          const SizedBox(height: 10),
          TextField(
            key: const Key('nickname_field'),
            controller: _nameCtrl,
            enabled: !_submitting,
            maxLength: 10,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => _roomFocus.requestFocus(),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
            decoration: const InputDecoration(
              hintText: '输入昵称',
              counterText: '',
              prefixIcon: Icon(Icons.badge_outlined, size: 20),
            ),
          ),
          const SizedBox(height: 7),
          const Text(
            '默认会生成代号，战报和血条都用它显示。',
            style: TextStyle(
              color: CsColors.textMuted,
              fontSize: 10.5,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoomPanel() {
    final String notice = _roomNotice ?? '输入 4 位数字，相同房号即可同场对战';
    return CsgoPanel(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const CsgoSectionHeader(
            index: '02',
            title: '加入房间',
            trailing: CsgoTag(label: '4 DIGITS'),
          ),
          const SizedBox(height: 10),
          TextField(
            key: const Key('room_field'),
            controller: _roomCtrl,
            focusNode: _roomFocus,
            enabled: !_submitting,
            keyboardType: TextInputType.number,
            maxLength: 4,
            textAlign: TextAlign.center,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _join(),
            onChanged: (_) {
              if (_roomNotice != null) {
                setState(() => _roomNotice = null);
              }
            },
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
            ],
            style: const TextStyle(
              fontSize: 26,
              height: 1.1,
              fontWeight: FontWeight.w900,
              letterSpacing: 10,
              color: CsColors.accent,
            ),
            decoration: InputDecoration(
              hintText: '0000',
              counterText: '',
              suffixIcon: IconButton(
                key: const Key('random_room_button'),
                tooltip: '随机房号',
                onPressed: _submitting ? null : _randomizeRoom,
                icon: const Icon(Icons.casino_outlined),
              ),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 18,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: Row(
                key: ValueKey<String>(notice),
                children: <Widget>[
                  Icon(
                    _roomNotice != null
                        ? Icons.check_circle_outline
                        : Icons.info_outline,
                    size: 12,
                    color: _roomNotice != null
                        ? CsColors.accent
                        : CsColors.textMuted,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      notice,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _roomNotice != null
                            ? CsColors.accent
                            : CsColors.textMuted,
                        fontSize: 10.5,
                        height: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeployButton() {
    return SizedBox(
      height: 58,
      child: FilledButton(
        key: const Key('join_button'),
        onPressed: _submitting ? null : _join,
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(2)),
          ),
        ),
        child: Row(
          children: <Widget>[
            if (_submitting)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: CsColors.textMuted,
                ),
              )
            else
              const Icon(Icons.play_arrow_rounded, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _submitting ? '正在进入房间…' : '加入战斗',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
            ),
            if (!_submitting)
              const Text(
                'DEPLOY',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.8,
                  color: Color(0x991C1708),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRulesPanel() {
    return CsgoPanel(
      color: CsColors.panelDeep,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const CsgoSectionHeader(
            index: '03',
            title: '交战规则',
            trailing: CsgoTag(label: 'BRIEFING', color: CsColors.textMuted),
          ),
          const SizedBox(height: 10),
          const _RuleRow('01', '摄像头对准对手，准星落在人形框内再开火'),
          const _RuleRow('02', '每次命中 -${Cfg.damagePerHit} HP，开火冷却 1 秒'),
          _RuleRow(
            '03',
            '目标占屏小于 ${(Cfg.minTargetAreaRatio * 100).toStringAsFixed(1)}% 判定为超出射程',
          ),
          const _RuleRow('04', '血量由服务端事务扣减，本地改不了分'),
        ],
      ),
    );
  }
}

class _RuleRow extends StatelessWidget {
  const _RuleRow(this.index, this.text);

  final String index;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 20,
            child: Text(
              index,
              style: const TextStyle(
                color: CsColors.accentDim,
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                height: 1.7,
              ),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: CsColors.text,
                fontSize: 11.5,
                height: 1.55,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
