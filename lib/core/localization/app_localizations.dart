import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

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

  /// Locale name safe to hand to [DateFormat].
  ///
  /// `main()` loads date symbols for every locale, but widget tests build
  /// screens without that bootstrap — asking for an unloaded locale throws, so
  /// fall back to the always-bundled `en_US` data instead.
  static String dateLocale(BuildContext context) {
    final locale = Localizations.localeOf(context).toString();
    if (DateFormat.localeExists(locale)) {
      return locale;
    }
    final language = Localizations.localeOf(context).languageCode;
    return DateFormat.localeExists(language) ? language : 'en_US';
  }
}

extension AppLocalizationContext on BuildContext {
  String tr({required String ru, required String en}) =>
      AppLocalizations.text(this, ru: ru, en: en);

  /// See [AppLocalizations.dateLocale].
  String get dateLocale => AppLocalizations.dateLocale(this);
}
