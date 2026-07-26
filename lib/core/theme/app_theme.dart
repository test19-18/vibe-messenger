import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'vibe_tokens.dart';

abstract final class AppTheme {
  static ThemeData get dark => _build(VibeTokens.dark());

  static ThemeData get light => _build(VibeTokens.light());

  static ThemeData _build(VibeTokens tokens) {
    final isDark = tokens.brightness == Brightness.dark;

    final colorScheme = ColorScheme(
      brightness: tokens.brightness,
      primary: tokens.accent,
      onPrimary: Colors.white,
      primaryContainer: tokens.accentSoft,
      onPrimaryContainer: isDark ? tokens.textPrimary : tokens.accent,
      secondary: tokens.accentSecondary,
      onSecondary: Colors.white,
      secondaryContainer: tokens.surfaceElevated,
      onSecondaryContainer: tokens.textPrimary,
      surface: tokens.surface,
      onSurface: tokens.textPrimary,
      surfaceContainerHighest: tokens.surfaceHighest,
      onSurfaceVariant: tokens.textSecondary,
      outline: tokens.separator,
      outlineVariant: tokens.divider,
      error: tokens.danger,
      onError: Colors.white,
      errorContainer: tokens.danger.withValues(alpha: 0.16),
      onErrorContainer: tokens.danger,
      inverseSurface: tokens.textPrimary,
      onInverseSurface: tokens.surface,
      shadow: Colors.black,
      scrim: Colors.black,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: tokens.brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: tokens.background,
      canvasColor: tokens.surface,
      fontFamily: 'Roboto',
      splashFactory: InkSparkle.splashFactory,
    );

    final textTheme = base.textTheme
        .apply(bodyColor: tokens.textPrimary, displayColor: tokens.textPrimary)
        .copyWith(
          headlineLarge: TextStyle(
            color: tokens.textPrimary,
            fontSize: 32,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.6,
          ),
          headlineSmall: TextStyle(
            color: tokens.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
          // Chat list row title / app bar title.
          titleLarge: TextStyle(
            color: tokens.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
          ),
          titleMedium: TextStyle(
            color: tokens.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
          titleSmall: TextStyle(
            color: tokens.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          bodyLarge: TextStyle(
            color: tokens.textPrimary,
            fontSize: 16,
            height: 1.3,
          ),
          bodyMedium: TextStyle(
            color: tokens.textSecondary,
            fontSize: 15,
            height: 1.3,
          ),
          bodySmall: TextStyle(
            color: tokens.textSecondary,
            fontSize: 13,
            height: 1.25,
          ),
          labelLarge: TextStyle(
            color: tokens.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        );

    final overlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      systemNavigationBarColor: tokens.navBar,
      systemNavigationBarIconBrightness: isDark
          ? Brightness.light
          : Brightness.dark,
    );

    OutlineInputBorder border(Color color, {double width = 1}) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.sm),
          borderSide: BorderSide(color: color, width: width),
        );

    return base.copyWith(
      extensions: <ThemeExtension<dynamic>>[tokens],
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: tokens.appBar,
        surfaceTintColor: Colors.transparent,
        foregroundColor: tokens.textPrimary,
        iconTheme: IconThemeData(color: tokens.accent, size: 24),
        actionsIconTheme: IconThemeData(color: tokens.accent, size: 24),
        systemOverlayStyle: overlayStyle,
        titleTextStyle: TextStyle(
          color: tokens.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
      ),
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: tokens.surfaceElevated,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm + 2,
        ),
        border: border(Colors.transparent),
        enabledBorder: border(tokens.separator),
        focusedBorder: border(tokens.accent, width: 1.6),
        errorBorder: border(tokens.danger),
        focusedErrorBorder: border(tokens.danger, width: 1.6),
        disabledBorder: border(tokens.separator.withValues(alpha: 0.5)),
        hintStyle: TextStyle(color: tokens.textTertiary, fontSize: 16),
        labelStyle: TextStyle(color: tokens.textSecondary),
        floatingLabelStyle: TextStyle(color: tokens.accent),
        prefixIconColor: tokens.textSecondary,
        suffixIconColor: tokens.textSecondary,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          backgroundColor: tokens.accent,
          foregroundColor: Colors.white,
          disabledBackgroundColor: tokens.accent.withValues(alpha: 0.4),
          disabledForegroundColor: Colors.white.withValues(alpha: 0.7),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.sm),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          foregroundColor: tokens.accent,
          side: BorderSide(color: tokens.separator),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.sm),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: tokens.accent,
          minimumSize: const Size(64, AppSizes.minTapTarget),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: tokens.accent,
          minimumSize: const Size.square(AppSizes.minTapTarget),
        ),
      ),
      iconTheme: IconThemeData(color: tokens.textSecondary, size: 24),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: tokens.accent,
        foregroundColor: Colors.white,
        elevation: 4,
        focusElevation: 6,
        highlightElevation: 8,
        shape: const CircleBorder(),
      ),
      dividerTheme: DividerThemeData(
        color: tokens.separator,
        thickness: 0.5,
        space: 0.5,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: tokens.textSecondary,
        textColor: tokens.textPrimary,
        titleTextStyle: textTheme.titleMedium,
        subtitleTextStyle: textTheme.bodySmall,
        minVerticalPadding: 10,
      ),
      cardTheme: CardThemeData(
        color: tokens.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: tokens.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 12,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyLarge?.copyWith(
          color: tokens.textSecondary,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: tokens.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: tokens.surface,
        dragHandleColor: tokens.textTertiary,
        showDragHandle: true,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadii.md),
          ),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: tokens.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.sm),
        ),
        textStyle: textTheme.bodyLarge,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: tokens.surfaceElevated,
        selectedColor: tokens.accentSoft,
        disabledColor: tokens.surfaceElevated,
        side: BorderSide(color: tokens.separator),
        labelStyle: TextStyle(color: tokens.textPrimary, fontSize: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return tokens.textTertiary;
          }
          return states.contains(WidgetState.selected)
              ? Colors.white
              : (isDark ? tokens.textSecondary : Colors.white);
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return tokens.accent;
          }
          return tokens.surfaceHighest;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? Colors.transparent
              : tokens.separator;
        }),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? tokens.accent
              : Colors.transparent;
        }),
        checkColor: const WidgetStatePropertyAll(Colors.white),
        side: BorderSide(color: tokens.textTertiary, width: 1.6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? tokens.accent
              : tokens.textTertiary;
        }),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: tokens.accent,
        unselectedLabelColor: tokens.textSecondary,
        indicatorColor: tokens.accent,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
        labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: tokens.surfaceHighest,
          borderRadius: BorderRadius.circular(AppRadii.xs),
        ),
        textStyle: TextStyle(color: tokens.textPrimary, fontSize: 13),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: tokens.surfaceHighest,
        contentTextStyle: TextStyle(color: tokens.textPrimary, fontSize: 15),
        actionTextColor: tokens.accent,
        behavior: SnackBarBehavior.floating,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.sm),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: tokens.accent,
        linearTrackColor: tokens.surfaceHighest,
        circularTrackColor: Colors.transparent,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: tokens.accent,
        inactiveTrackColor: tokens.surfaceHighest,
        thumbColor: tokens.accent,
        trackHeight: 3,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(
          tokens.textTertiary.withValues(alpha: 0.5),
        ),
        radius: const Radius.circular(4),
      ),
      splashColor: tokens.accent.withValues(alpha: 0.10),
      highlightColor: tokens.accent.withValues(alpha: 0.06),
    );
  }
}
