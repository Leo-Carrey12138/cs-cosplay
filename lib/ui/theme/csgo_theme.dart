import 'package:flutter/material.dart';

/// CS:GO 战术 HUD 配色。
///
/// 只用少量纯色 + 细边框，避免渐变和发光；红色只留给危险/阵亡/开火。
abstract final class CsColors {
  /// 主背景：深橄榄灰
  static const Color bg = Color(0xFF171A16);

  /// 面板背景：深灰绿
  static const Color panel = Color(0xFF22251F);

  /// 更深一层的面板（输入框、次级说明）
  static const Color panelDeep = Color(0xFF1B1E19);

  /// 抬升面板（弹窗、按钮底）
  static const Color panelRaised = Color(0xFF2A2E26);

  /// 主强调色：沙黄／琥珀
  static const Color accent = Color(0xFFD6B66C);

  /// 弱化的强调色（辅助线、图标）
  static const Color accentDim = Color(0xFF9C8A58);

  /// 次要文字：灰白
  static const Color text = Color(0xFFC7C9C2);

  /// 主要文字：提亮灰白
  static const Color textStrong = Color(0xFFF0F1EA);

  /// 说明文字：低对比灰
  static const Color textMuted = Color(0xFF8C9186);

  /// 低对比灰橄榄边框
  static const Color border = Color(0xFF3B3F35);

  /// 稍强的边框（弹窗、选中态）
  static const Color borderStrong = Color(0xFF55594B);

  /// 危险 / 低血量 / 开火
  static const Color danger = Color(0xFFE5484D);

  /// 危险状态的深色底
  static const Color dangerDeep = Color(0xFF5C1719);

  /// 警告（中等血量、超出射程）
  static const Color warning = Color(0xFFE0A54A);
}

/// 血量颜色：健康 = 沙黄，中等 = 琥珀，低血量 = 红色。
Color csgoHpColor(double ratio, {bool alive = true}) {
  if (!alive) return CsColors.textMuted;
  if (ratio > 0.6) return CsColors.accent;
  if (ratio > 0.3) return CsColors.warning;
  return CsColors.danger;
}

/// 全局主题：深色军事终端 + 沙黄强调色。
///
/// 只改视觉，不参与启动流程；[main] 仍按原顺序初始化 Firebase / 屏幕方向。
ThemeData buildCsgoTheme() {
  final ColorScheme scheme = ColorScheme.fromSeed(
    seedColor: CsColors.accent,
    brightness: Brightness.dark,
  ).copyWith(
    primary: CsColors.accent,
    onPrimary: const Color(0xFF1C1708),
    primaryContainer: const Color(0xFF3A3320),
    onPrimaryContainer: CsColors.textStrong,
    secondary: CsColors.accentDim,
    onSecondary: CsColors.bg,
    surface: CsColors.panel,
    onSurface: CsColors.text,
    surfaceContainerHighest: CsColors.panelRaised,
    onSurfaceVariant: CsColors.textMuted,
    error: CsColors.danger,
    onError: Colors.white,
    outline: CsColors.border,
    outlineVariant: CsColors.border,
  );

  final ThemeData base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: CsColors.bg,
  );

  final TextTheme textTheme = base.textTheme
      .apply(bodyColor: CsColors.text, displayColor: CsColors.textStrong)
      .copyWith(
        headlineMedium: base.textTheme.headlineMedium?.copyWith(
          color: CsColors.textStrong,
          fontWeight: FontWeight.w900,
          letterSpacing: 1,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          color: CsColors.textStrong,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          color: CsColors.textStrong,
          fontWeight: FontWeight.w700,
        ),
        bodySmall: base.textTheme.bodySmall?.copyWith(
          color: CsColors.textMuted,
          height: 1.5,
        ),
        labelSmall: base.textTheme.labelSmall?.copyWith(
          color: CsColors.textMuted,
          fontSize: 10,
          letterSpacing: 1.6,
          fontWeight: FontWeight.w700,
        ),
      );

  const OutlineInputBorder fieldBorder = OutlineInputBorder(
    borderRadius: BorderRadius.all(Radius.circular(2)),
    borderSide: BorderSide(color: CsColors.border),
  );
  const OutlineInputBorder fieldFocusedBorder = OutlineInputBorder(
    borderRadius: BorderRadius.all(Radius.circular(2)),
    borderSide: BorderSide(color: CsColors.accent, width: 1.4),
  );
  const OutlineInputBorder fieldErrorBorder = OutlineInputBorder(
    borderRadius: BorderRadius.all(Radius.circular(2)),
    borderSide: BorderSide(color: CsColors.danger, width: 1.2),
  );

  return base.copyWith(
    canvasColor: CsColors.bg,
    textTheme: textTheme,
    iconTheme: const IconThemeData(color: CsColors.text),
    dividerTheme: const DividerThemeData(
      color: CsColors.border,
      thickness: 1,
      space: 1,
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: CsColors.accent,
      selectionColor: Color(0x44D6B66C),
      selectionHandleColor: CsColors.accent,
    ),
    inputDecorationTheme: const InputDecorationThemeData(
      filled: true,
      fillColor: CsColors.panelDeep,
      isDense: true,
      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      border: fieldBorder,
      enabledBorder: fieldBorder,
      focusedBorder: fieldFocusedBorder,
      errorBorder: fieldErrorBorder,
      focusedErrorBorder: fieldErrorBorder,
      labelStyle: TextStyle(color: CsColors.textMuted, fontSize: 13),
      floatingLabelStyle: TextStyle(
        color: CsColors.accent,
        fontSize: 13,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
      ),
      hintStyle: TextStyle(color: CsColors.textMuted, fontSize: 13),
      helperStyle: TextStyle(color: CsColors.textMuted, fontSize: 11),
      errorStyle: TextStyle(color: CsColors.danger, fontSize: 11),
      counterStyle: TextStyle(color: CsColors.textMuted, fontSize: 10),
      prefixIconColor: CsColors.accentDim,
      suffixIconColor: CsColors.accent,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: CsColors.accent,
        foregroundColor: const Color(0xFF1C1708),
        disabledBackgroundColor: CsColors.panelRaised,
        disabledForegroundColor: CsColors.textMuted,
        elevation: 0,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(2)),
        ),
        textStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: CsColors.accent,
        side: const BorderSide(color: CsColors.borderStrong),
        minimumSize: const Size(0, 42),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(2)),
        ),
        textStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: CsColors.accent,
        minimumSize: const Size(0, 38),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(2)),
        ),
        textStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: CsColors.accent),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: CsColors.panelRaised,
      contentTextStyle: TextStyle(
        color: CsColors.textStrong,
        fontSize: 13,
        height: 1.4,
      ),
      actionTextColor: CsColors.accent,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(2)),
        side: BorderSide(color: CsColors.borderStrong),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: CsColors.accent,
      linearTrackColor: CsColors.border,
      circularTrackColor: CsColors.border,
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: CsColors.panel,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(2)),
        side: BorderSide(color: CsColors.borderStrong),
      ),
      titleTextStyle: TextStyle(
        color: CsColors.textStrong,
        fontSize: 18,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.8,
      ),
      contentTextStyle: TextStyle(
        color: CsColors.text,
        fontSize: 13.5,
        height: 1.6,
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: CsColors.panel,
      modalBackgroundColor: CsColors.panel,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      dragHandleColor: CsColors.borderStrong,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(2)),
        side: BorderSide(color: CsColors.borderStrong),
      ),
    ),
    dividerColor: CsColors.border,
    splashColor: const Color(0x1FD6B66C),
    highlightColor: const Color(0x0FD6B66C),
  );
}

/// 带切角 + 细边框的战术面板。
///
/// 切角只切左上、右下两个角，配合直角边框营造 HUD 感；
/// [accentBar] 打开时左侧会多一条强调色竖线。
class CsgoPanel extends StatelessWidget {
  const CsgoPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.color = CsColors.panel,
    this.borderColor = CsColors.border,
    this.accentBar = false,
    this.cut = 9,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final Color borderColor;
  final bool accentBar;
  final double cut;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _CsgoBorderPainter(color: borderColor, cut: cut),
      child: ClipPath(
        clipper: _CsgoPanelClipper(cut: cut),
        child: Container(
          color: color,
          child: Stack(
            fit: StackFit.passthrough,
            children: <Widget>[
              Padding(padding: padding, child: child),
              if (accentBar)
                const Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: SizedBox(
                    width: 2,
                    child: ColoredBox(color: CsColors.accent),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 带编号的小节标题，例如 `[01] 作战代号`。
class CsgoSectionHeader extends StatelessWidget {
  const CsgoSectionHeader({
    super.key,
    required this.index,
    required this.title,
    this.trailing,
  });

  final String index;
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(width: 3, height: 13, color: CsColors.accent),
        const SizedBox(width: 8),
        Text(
          index,
          style: const TextStyle(
            color: CsColors.accent,
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
            height: 1,
          ),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: CsColors.textStrong,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              height: 1,
            ),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// 细线小标签（4 DIGITS / MAX 6 之类的纯装饰性提示）。
class CsgoTag extends StatelessWidget {
  const CsgoTag({
    super.key,
    required this.label,
    this.color = CsColors.accentDim,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.55)),
        borderRadius: BorderRadius.circular(1),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          height: 1,
        ),
      ),
    );
  }
}

/// 带文字的低对比分隔线。
class CsgoDivider extends StatelessWidget {
  const CsgoDivider({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    final label = this.label;
    return Row(
      children: <Widget>[
        const Expanded(child: Divider(color: CsColors.border, height: 1)),
        if (label != null) ...<Widget>[
          const SizedBox(width: 10),
          Text(
            label,
            style: const TextStyle(
              color: CsColors.textMuted,
              fontSize: 9,
              letterSpacing: 2,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(child: Divider(color: CsColors.border, height: 1)),
        ],
      ],
    );
  }
}

/// 极淡的网格 + 四角短线背景，避免大片纯色显得空。
class CsgoBackdrop extends StatelessWidget {
  const CsgoBackdrop({super.key, this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _CsgoGridPainter(), child: child);
  }
}

class _CsgoGridPainter extends CustomPainter {
  static const double _step = 32;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final Paint grid = Paint()
      ..color = CsColors.border.withValues(alpha: 0.28)
      ..strokeWidth = 0.6;
    for (double x = _step; x < size.width; x += _step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (double y = _step; y < size.height; y += _step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    // 四角取景框短线
    final Paint corner = Paint()
      ..color = CsColors.accent.withValues(alpha: 0.5)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.square;
    const double len = 18;
    const double inset = 14;
    final double right = size.width - inset;
    final double bottom = size.height - inset;

    // 左上
    canvas.drawLine(
        const Offset(inset, inset), const Offset(inset + len, inset), corner);
    canvas.drawLine(
        const Offset(inset, inset), const Offset(inset, inset + len), corner);
    // 右上
    canvas.drawLine(Offset(right, inset), Offset(right - len, inset), corner);
    canvas.drawLine(Offset(right, inset), Offset(right, inset + len), corner);
    // 左下
    canvas.drawLine(Offset(inset, bottom), Offset(inset + len, bottom), corner);
    canvas.drawLine(Offset(inset, bottom), Offset(inset, bottom - len), corner);
    // 右下
    canvas.drawLine(Offset(right, bottom), Offset(right - len, bottom), corner);
    canvas.drawLine(Offset(right, bottom), Offset(right, bottom - len), corner);
  }

  @override
  bool shouldRepaint(covariant _CsgoGridPainter oldDelegate) => false;
}

Path _csgoPanelPath(Size size, double cut) {
  final double c = cut.clamp(0, size.shortestSide / 2).toDouble();
  return Path()
    ..moveTo(c, 0)
    ..lineTo(size.width, 0)
    ..lineTo(size.width, size.height - c)
    ..lineTo(size.width - c, size.height)
    ..lineTo(0, size.height)
    ..lineTo(0, c)
    ..close();
}

class _CsgoPanelClipper extends CustomClipper<Path> {
  const _CsgoPanelClipper({required this.cut});

  final double cut;

  @override
  Path getClip(Size size) => _csgoPanelPath(size, cut);

  @override
  bool shouldReclip(covariant _CsgoPanelClipper oldClipper) =>
      oldClipper.cut != cut;
}

class _CsgoBorderPainter extends CustomPainter {
  const _CsgoBorderPainter({required this.color, required this.cut});

  final Color color;
  final double cut;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.drawPath(
      _csgoPanelPath(size, cut),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _CsgoBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.cut != cut;
}
