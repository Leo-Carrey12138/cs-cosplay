import 'package:cs_cosplay/ui/theme/csgo_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('全局主题使用深橄榄背景 + 沙黄强调色', () {
    final ThemeData theme = buildCsgoTheme();

    expect(theme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, CsColors.bg);
    expect(theme.colorScheme.primary, CsColors.accent);
    expect(theme.colorScheme.surface, CsColors.panel);
    expect(theme.colorScheme.error, CsColors.danger);

    expect(
      theme.filledButtonTheme.style?.backgroundColor?.resolve(<WidgetState>{}),
      CsColors.accent,
    );
    expect(
      theme.textTheme.bodyMedium?.color,
      CsColors.text,
    );
  });

  test('输入框焦点态使用沙黄边框', () {
    final InputBorder? focused =
        buildCsgoTheme().inputDecorationTheme.focusedBorder;

    expect(focused, isA<OutlineInputBorder>());
    expect(
      (focused! as OutlineInputBorder).borderSide.color,
      CsColors.accent,
    );
  });

  test('血量颜色分级：沙黄 / 琥珀 / 红色', () {
    expect(csgoHpColor(1.0), CsColors.accent);
    expect(csgoHpColor(0.5), CsColors.warning);
    expect(csgoHpColor(0.2), CsColors.danger);
    expect(csgoHpColor(1.0, alive: false), CsColors.textMuted);
  });
}
