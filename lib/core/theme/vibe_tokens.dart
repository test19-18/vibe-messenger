import 'package:flutter/material.dart';

/// Semantic design tokens for the Vibe surface language.
///
/// The layout grammar follows the messenger conventions users already know
/// (chat list rows, tailed bubbles, a patterned chat wallpaper), while the
/// accent ramp — electric blue drifting into violet — stays Vibe's own.
///
/// Widgets must read colours from here via [VibeTokensContext.tokens] instead
/// of importing a fixed palette, otherwise the light theme renders dark chrome
/// on a light background.
@immutable
class VibeTokens extends ThemeExtension<VibeTokens> {
  const VibeTokens({
    required this.brightness,
    required this.background,
    required this.surface,
    required this.surfaceElevated,
    required this.surfaceHighest,
    required this.appBar,
    required this.composer,
    required this.navBar,
    required this.divider,
    required this.separator,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.accent,
    required this.accentSoft,
    required this.accentSecondary,
    required this.accentCyan,
    required this.accentPink,
    required this.chatWallpaper,
    required this.chatWallpaperEnd,
    required this.chatPattern,
    required this.bubbleIn,
    required this.bubbleOut,
    required this.bubbleOutEnd,
    required this.onBubbleIn,
    required this.onBubbleOut,
    required this.bubbleInMeta,
    required this.bubbleOutMeta,
    required this.bubbleInAccent,
    required this.bubbleOutAccent,
    required this.servicePill,
    required this.onServicePill,
    required this.badge,
    required this.badgeMuted,
    required this.onBadge,
    required this.online,
    required this.success,
    required this.warning,
    required this.danger,
    required this.selectionOverlay,
    required this.avatarGradients,
  });

  /// Night theme: deep desaturated blue chrome, blue-violet outgoing bubbles.
  factory VibeTokens.dark() => const VibeTokens(
    brightness: Brightness.dark,
    background: Color(0xFF0E1621),
    surface: Color(0xFF17212B),
    surfaceElevated: Color(0xFF202B36),
    surfaceHighest: Color(0xFF2B3843),
    appBar: Color(0xFF17212B),
    composer: Color(0xFF17212B),
    navBar: Color(0xFF17212B),
    divider: Color(0xFF101921),
    separator: Color(0xFF243240),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFF8D9BA8),
    textTertiary: Color(0xFF6B7A88),
    accent: Color(0xFF4EA4F6),
    accentSoft: Color(0xFF1F3B55),
    accentSecondary: Color(0xFF8E7CFF),
    accentCyan: Color(0xFF2BC8D9),
    accentPink: Color(0xFFFF6FAE),
    chatWallpaper: Color(0xFF0E1621),
    chatWallpaperEnd: Color(0xFF141F2C),
    chatPattern: Color(0x14FFFFFF),
    bubbleIn: Color(0xFF182533),
    bubbleOut: Color(0xFF2B5278),
    bubbleOutEnd: Color(0xFF3B4B85),
    onBubbleIn: Color(0xFFFFFFFF),
    onBubbleOut: Color(0xFFFFFFFF),
    bubbleInMeta: Color(0xFF7F91A4),
    bubbleOutMeta: Color(0xCCE3EEFB),
    bubbleInAccent: Color(0xFF6BB3F7),
    bubbleOutAccent: Color(0xFFB6C9F5),
    servicePill: Color(0x66101B26),
    onServicePill: Color(0xFFE6EDF4),
    badge: Color(0xFF4EA4F6),
    badgeMuted: Color(0xFF4A5A68),
    onBadge: Color(0xFFFFFFFF),
    online: Color(0xFF4DCD5E),
    success: Color(0xFF4DCD5E),
    warning: Color(0xFFFFB84D),
    danger: Color(0xFFFF5D5D),
    selectionOverlay: Color(0x334EA4F6),
    avatarGradients: _avatarGradients,
  );

  /// Day theme: white chrome, patterned blue wallpaper, soft-green outgoing
  /// bubbles — the arrangement people read as "a messenger" at a glance.
  factory VibeTokens.light() => const VibeTokens(
    brightness: Brightness.light,
    background: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF),
    surfaceElevated: Color(0xFFF4F5F7),
    surfaceHighest: Color(0xFFE9EBEF),
    appBar: Color(0xFFFFFFFF),
    composer: Color(0xFFFFFFFF),
    navBar: Color(0xFFFFFFFF),
    divider: Color(0xFFE4E8EB),
    separator: Color(0xFFE4E8EB),
    textPrimary: Color(0xFF0F1419),
    textSecondary: Color(0xFF707579),
    textTertiary: Color(0xFF9AA0A6),
    accent: Color(0xFF3390EC),
    accentSoft: Color(0xFFE6F1FD),
    accentSecondary: Color(0xFF7B61FF),
    accentCyan: Color(0xFF0E9BAA),
    accentPink: Color(0xFFDD4C8B),
    chatWallpaper: Color(0xFFDCE9F5),
    chatWallpaperEnd: Color(0xFFC9DDF0),
    chatPattern: Color(0x14203A52),
    bubbleIn: Color(0xFFFFFFFF),
    bubbleOut: Color(0xFFEFFDDE),
    bubbleOutEnd: Color(0xFFE4F7D2),
    onBubbleIn: Color(0xFF0F1419),
    onBubbleOut: Color(0xFF0F1419),
    bubbleInMeta: Color(0xFF8D9198),
    bubbleOutMeta: Color(0xFF5BAE58),
    bubbleInAccent: Color(0xFF3390EC),
    bubbleOutAccent: Color(0xFF4FAE4E),
    servicePill: Color(0x40536A7F),
    onServicePill: Color(0xFFFFFFFF),
    badge: Color(0xFF3390EC),
    badgeMuted: Color(0xFFC4C9CC),
    onBadge: Color(0xFFFFFFFF),
    online: Color(0xFF0AC630),
    success: Color(0xFF1DAB4B),
    warning: Color(0xFFE08A1E),
    danger: Color(0xFFE53935),
    selectionOverlay: Color(0x333390EC),
    avatarGradients: _avatarGradients,
  );

  final Brightness brightness;

  /// Scaffold background behind non-chat screens.
  final Color background;

  /// Cards, list backgrounds and sheets.
  final Color surface;
  final Color surfaceElevated;
  final Color surfaceHighest;
  final Color appBar;
  final Color composer;
  final Color navBar;

  /// Hairline under the app bar / nav bar — deliberately darker than
  /// [separator], which is the inset rule between list rows.
  final Color divider;
  final Color separator;

  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;

  final Color accent;
  final Color accentSoft;
  final Color accentSecondary;

  /// Decorative accents used to colour-code settings and contact rows.
  final Color accentCyan;
  final Color accentPink;

  final Color chatWallpaper;
  final Color chatWallpaperEnd;
  final Color chatPattern;

  final Color bubbleIn;
  final Color bubbleOut;
  final Color bubbleOutEnd;
  final Color onBubbleIn;
  final Color onBubbleOut;

  /// Timestamp / status colour inside a bubble.
  final Color bubbleInMeta;
  final Color bubbleOutMeta;

  /// Reply stripes, links and sender names inside a bubble.
  final Color bubbleInAccent;
  final Color bubbleOutAccent;

  /// Floating date separators and system events on the wallpaper.
  final Color servicePill;
  final Color onServicePill;

  final Color badge;
  final Color badgeMuted;
  final Color onBadge;

  final Color online;
  final Color success;
  final Color warning;
  final Color danger;

  final Color selectionOverlay;

  /// Deterministic two-stop gradients for letter avatars.
  final List<List<Color>> avatarGradients;

  static const List<List<Color>> _avatarGradients = [
    [Color(0xFFFF885E), Color(0xFFFF516A)],
    [Color(0xFFFFCD6A), Color(0xFFFFA85C)],
    [Color(0xFFA0DE7E), Color(0xFF54CB68)],
    [Color(0xFF82B1FF), Color(0xFF665FFF)],
    [Color(0xFF72D5FD), Color(0xFF2A9EF1)],
    [Color(0xFFE0A2F3), Color(0xFFD669ED)],
    [Color(0xFFFFA3B3), Color(0xFFFF5C8A)],
  ];

  /// Stable gradient pick so a chat keeps the same avatar colours everywhere.
  List<Color> avatarGradientFor(String seed) {
    if (avatarGradients.isEmpty) {
      return const [Color(0xFF4EA4F6), Color(0xFF8E7CFF)];
    }
    var hash = 0;
    for (final unit in seed.codeUnits) {
      hash = (hash * 31 + unit) & 0x7FFFFFFF;
    }
    return avatarGradients[hash % avatarGradients.length];
  }

  Color bubbleForeground({required bool isMine}) =>
      isMine ? onBubbleOut : onBubbleIn;

  Color bubbleMeta({required bool isMine}) =>
      isMine ? bubbleOutMeta : bubbleInMeta;

  Color bubbleAccent({required bool isMine}) =>
      isMine ? bubbleOutAccent : bubbleInAccent;

  @override
  VibeTokens copyWith({
    Brightness? brightness,
    Color? background,
    Color? surface,
    Color? surfaceElevated,
    Color? surfaceHighest,
    Color? appBar,
    Color? composer,
    Color? navBar,
    Color? divider,
    Color? separator,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? accent,
    Color? accentSoft,
    Color? accentSecondary,
    Color? accentCyan,
    Color? accentPink,
    Color? chatWallpaper,
    Color? chatWallpaperEnd,
    Color? chatPattern,
    Color? bubbleIn,
    Color? bubbleOut,
    Color? bubbleOutEnd,
    Color? onBubbleIn,
    Color? onBubbleOut,
    Color? bubbleInMeta,
    Color? bubbleOutMeta,
    Color? bubbleInAccent,
    Color? bubbleOutAccent,
    Color? servicePill,
    Color? onServicePill,
    Color? badge,
    Color? badgeMuted,
    Color? onBadge,
    Color? online,
    Color? success,
    Color? warning,
    Color? danger,
    Color? selectionOverlay,
    List<List<Color>>? avatarGradients,
  }) {
    return VibeTokens(
      brightness: brightness ?? this.brightness,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      surfaceHighest: surfaceHighest ?? this.surfaceHighest,
      appBar: appBar ?? this.appBar,
      composer: composer ?? this.composer,
      navBar: navBar ?? this.navBar,
      divider: divider ?? this.divider,
      separator: separator ?? this.separator,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      accent: accent ?? this.accent,
      accentSoft: accentSoft ?? this.accentSoft,
      accentSecondary: accentSecondary ?? this.accentSecondary,
      accentCyan: accentCyan ?? this.accentCyan,
      accentPink: accentPink ?? this.accentPink,
      chatWallpaper: chatWallpaper ?? this.chatWallpaper,
      chatWallpaperEnd: chatWallpaperEnd ?? this.chatWallpaperEnd,
      chatPattern: chatPattern ?? this.chatPattern,
      bubbleIn: bubbleIn ?? this.bubbleIn,
      bubbleOut: bubbleOut ?? this.bubbleOut,
      bubbleOutEnd: bubbleOutEnd ?? this.bubbleOutEnd,
      onBubbleIn: onBubbleIn ?? this.onBubbleIn,
      onBubbleOut: onBubbleOut ?? this.onBubbleOut,
      bubbleInMeta: bubbleInMeta ?? this.bubbleInMeta,
      bubbleOutMeta: bubbleOutMeta ?? this.bubbleOutMeta,
      bubbleInAccent: bubbleInAccent ?? this.bubbleInAccent,
      bubbleOutAccent: bubbleOutAccent ?? this.bubbleOutAccent,
      servicePill: servicePill ?? this.servicePill,
      onServicePill: onServicePill ?? this.onServicePill,
      badge: badge ?? this.badge,
      badgeMuted: badgeMuted ?? this.badgeMuted,
      onBadge: onBadge ?? this.onBadge,
      online: online ?? this.online,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      selectionOverlay: selectionOverlay ?? this.selectionOverlay,
      avatarGradients: avatarGradients ?? this.avatarGradients,
    );
  }

  @override
  VibeTokens lerp(ThemeExtension<VibeTokens>? other, double t) {
    if (other is! VibeTokens) {
      return this;
    }
    Color mix(Color a, Color b) => Color.lerp(a, b, t) ?? a;
    return VibeTokens(
      brightness: t < 0.5 ? brightness : other.brightness,
      background: mix(background, other.background),
      surface: mix(surface, other.surface),
      surfaceElevated: mix(surfaceElevated, other.surfaceElevated),
      surfaceHighest: mix(surfaceHighest, other.surfaceHighest),
      appBar: mix(appBar, other.appBar),
      composer: mix(composer, other.composer),
      navBar: mix(navBar, other.navBar),
      divider: mix(divider, other.divider),
      separator: mix(separator, other.separator),
      textPrimary: mix(textPrimary, other.textPrimary),
      textSecondary: mix(textSecondary, other.textSecondary),
      textTertiary: mix(textTertiary, other.textTertiary),
      accent: mix(accent, other.accent),
      accentSoft: mix(accentSoft, other.accentSoft),
      accentSecondary: mix(accentSecondary, other.accentSecondary),
      accentCyan: mix(accentCyan, other.accentCyan),
      accentPink: mix(accentPink, other.accentPink),
      chatWallpaper: mix(chatWallpaper, other.chatWallpaper),
      chatWallpaperEnd: mix(chatWallpaperEnd, other.chatWallpaperEnd),
      chatPattern: mix(chatPattern, other.chatPattern),
      bubbleIn: mix(bubbleIn, other.bubbleIn),
      bubbleOut: mix(bubbleOut, other.bubbleOut),
      bubbleOutEnd: mix(bubbleOutEnd, other.bubbleOutEnd),
      onBubbleIn: mix(onBubbleIn, other.onBubbleIn),
      onBubbleOut: mix(onBubbleOut, other.onBubbleOut),
      bubbleInMeta: mix(bubbleInMeta, other.bubbleInMeta),
      bubbleOutMeta: mix(bubbleOutMeta, other.bubbleOutMeta),
      bubbleInAccent: mix(bubbleInAccent, other.bubbleInAccent),
      bubbleOutAccent: mix(bubbleOutAccent, other.bubbleOutAccent),
      servicePill: mix(servicePill, other.servicePill),
      onServicePill: mix(onServicePill, other.onServicePill),
      badge: mix(badge, other.badge),
      badgeMuted: mix(badgeMuted, other.badgeMuted),
      onBadge: mix(onBadge, other.onBadge),
      online: mix(online, other.online),
      success: mix(success, other.success),
      warning: mix(warning, other.warning),
      danger: mix(danger, other.danger),
      selectionOverlay: mix(selectionOverlay, other.selectionOverlay),
      avatarGradients: t < 0.5 ? avatarGradients : other.avatarGradients,
    );
  }
}

extension VibeTokensContext on BuildContext {
  /// Tokens for the theme currently in scope.
  ///
  /// Falls back to the night palette so widgets built outside a themed subtree
  /// (golden tests, isolated previews) still render.
  VibeTokens get tokens =>
      Theme.of(this).extension<VibeTokens>() ?? VibeTokens.dark();
}
