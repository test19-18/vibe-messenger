import 'package:flutter/material.dart';

abstract final class AppColors {
  static const background = Color(0xFF080A0D);
  static const surface = Color(0xFF11151A);
  static const surfaceHigh = Color(0xFF191E25);
  static const surfaceHighest = Color(0xFF232A33);
  static const electricBlue = Color(0xFF1677FF);
  static const electricBlueSoft = Color(0xFF133B71);
  static const textPrimary = Color(0xFFF5F7FA);
  static const textSecondary = Color(0xFF929AA6);
  static const divider = Color(0xFF252C35);
  static const success = Color(0xFF30D18B);
  static const warning = Color(0xFFFFB84D);
  static const danger = Color(0xFFFF5D6C);
  static const purple = Color(0xFF916BFF);
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
  static const double sm = 12;
  static const double md = 18;
  static const double lg = 24;
  static const double pill = 999;
}
