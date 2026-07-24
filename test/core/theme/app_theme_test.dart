import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibe_messenger/core/theme/app_colors.dart';
import 'package:vibe_messenger/core/theme/app_theme.dart';

void main() {
  test('Vibe theme uses dark graphite palette and electric blue accent', () {
    final theme = AppTheme.dark;

    expect(theme.brightness, Brightness.dark);
    expect(theme.useMaterial3, isTrue);
    expect(theme.scaffoldBackgroundColor, AppColors.background);
    expect(theme.colorScheme.primary, AppColors.electricBlue);
    expect(theme.colorScheme.surface, AppColors.surface);
  });
}
