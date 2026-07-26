import 'package:flutter/material.dart';

/// Raw night-theme palette.
///
/// Prefer `context.tokens` from `vibe_tokens.dart` in widgets — these constants
/// are brightness-blind and only correct on the dark theme. They stay for the
/// places that genuinely need a fixed value (system chrome, splash, overlays
/// that are dark in both themes).
abstract final class AppColors {
  static const background = Color(0xFF0E1621);
  static const surface = Color(0xFF17212B);
  static const surfaceHigh = Color(0xFF202B36);
  static const surfaceHighest = Color(0xFF2B3843);
  static const electricBlue = Color(0xFF4EA4F6);
  static const electricBlueSoft = Color(0xFF1F3B55);
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFF8D9BA8);
  static const divider = Color(0xFF243240);
  static const success = Color(0xFF4DCD5E);
  static const warning = Color(0xFFFFB84D);
  static const danger = Color(0xFFFF5D5D);
  static const purple = Color(0xFF8E7CFF);
  static const cyan = Color(0xFF2BC8D9);
  static const pink = Color(0xFFFF6FAE);
}

abstract final class AppSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

abstract final class AppRadii {
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 18;
  static const double lg = 24;
  static const double pill = 999;

  /// Corner radius of a chat bubble; the tail side reuses [bubbleTail].
  static const double bubble = 16;
  static const double bubbleTail = 6;
}

/// Layout constants shared by the messenger surfaces.
abstract final class AppSizes {
  /// Minimum tappable square — matches the Material accessibility guideline.
  static const double minTapTarget = 48;

  /// Avatar diameter in the chat list.
  static const double chatListAvatar = 54;

  /// Left inset of chat-list separators, aligned with the row title.
  static const double chatListSeparatorInset = 82;

  /// Reading width cap so chats do not stretch across a tablet.
  static const double contentMaxWidth = 720;
}
