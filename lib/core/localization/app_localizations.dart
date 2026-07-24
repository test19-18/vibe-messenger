import 'package:flutter/widgets.dart';

abstract final class AppLocalizations {
  static bool isRussian(BuildContext context) =>
      Localizations.localeOf(context).languageCode == 'ru';

  static String text(
    BuildContext context, {
    required String ru,
    required String en,
  }) {
    return isRussian(context) ? ru : en;
  }
}

extension AppLocalizationContext on BuildContext {
  String tr({required String ru, required String en}) =>
      AppLocalizations.text(this, ru: ru, en: en);
}
