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

  /// Locale name safe to hand to [DateFormat], or null when its symbols are
  /// not loaded.
  ///
  /// `main()` loads date symbols for every locale, but widget tests build
  /// screens without that bootstrap. Naming *any* locale then throws
  /// `LocaleDataException` — including `en_US` — so the fallback has to be no
  /// locale at all, which is the constructor's own default.
  static String? dateLocale(BuildContext context) {
    final locale = Localizations.localeOf(context);
    final full = locale.toString();
    if (DateFormat.localeExists(full)) {
      return full;
    }
    return DateFormat.localeExists(locale.languageCode)
        ? locale.languageCode
        : null;
  }
}

extension AppLocalizationContext on BuildContext {
  String tr({required String ru, required String en}) =>
      AppLocalizations.text(this, ru: ru, en: en);

  /// See [AppLocalizations.dateLocale].
  String? get dateLocale => AppLocalizations.dateLocale(this);
}
