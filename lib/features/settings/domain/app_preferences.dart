enum AppThemePreference { system, light, dark }

class AppPreferences {
  const AppPreferences({
    this.locale = 'ru',
    this.theme = AppThemePreference.dark,
    this.textScale = 1,
    this.animationsEnabled = true,
    this.powerSaving = false,
    this.autoDownloadMedia = true,
    this.cacheMedia = true,
    this.pushEnabled = true,
    this.pushMessagePreview = true,
    this.sendReadReceipts = true,
    this.showTypingStatus = true,
    this.showLastSeen = true,
  });

  final String locale;
  final AppThemePreference theme;
  final double textScale;
  final bool animationsEnabled;
  final bool powerSaving;
  final bool autoDownloadMedia;
  final bool cacheMedia;
  final bool pushEnabled;
  final bool pushMessagePreview;
  final bool sendReadReceipts;
  final bool showTypingStatus;
  final bool showLastSeen;

  bool get reduceMotion => powerSaving || !animationsEnabled;

  factory AppPreferences.fromMap(Map<String, dynamic> map) {
    final extra = _map(map['settings']) ?? map;
    return AppPreferences(
      locale: _locale(map['locale'] ?? extra['locale']),
      theme: _theme(map['theme'] ?? extra['theme']),
      textScale: _scale(extra['text_scale']),
      animationsEnabled: _bool(extra['animations_enabled'], true),
      powerSaving: _bool(extra['power_saving'], false),
      autoDownloadMedia: _bool(
        map['auto_download_media'] ?? extra['auto_download_media'],
        true,
      ),
      cacheMedia: _bool(extra['cache_media'], true),
      pushEnabled: _bool(map['push_enabled'] ?? extra['push_enabled'], true),
      pushMessagePreview: _bool(
        map['push_message_preview'] ?? extra['push_message_preview'],
        true,
      ),
      sendReadReceipts: _bool(
        map['send_read_receipts'] ?? extra['send_read_receipts'],
        true,
      ),
      showTypingStatus: _bool(
        map['show_typing_status'] ?? extra['show_typing_status'],
        true,
      ),
      showLastSeen: _bool(
        map['show_last_seen'] ?? extra['show_last_seen'],
        true,
      ),
    );
  }

  Map<String, dynamic> toMap() => {
    'locale': locale,
    'theme': theme.name,
    'text_scale': textScale,
    'animations_enabled': animationsEnabled,
    'power_saving': powerSaving,
    'auto_download_media': autoDownloadMedia,
    'cache_media': cacheMedia,
    'push_enabled': pushEnabled,
    'push_message_preview': pushMessagePreview,
    'send_read_receipts': sendReadReceipts,
    'show_typing_status': showTypingStatus,
    'show_last_seen': showLastSeen,
  };

  Map<String, dynamic> toBackendMap() => {
    'locale': locale,
    'theme': theme.name,
    'send_read_receipts': sendReadReceipts,
    'show_typing_status': showTypingStatus,
    'show_last_seen': showLastSeen,
    'push_enabled': pushEnabled,
    'push_message_preview': pushMessagePreview,
    'auto_download_media': autoDownloadMedia,
    'settings': {
      'text_scale': textScale,
      'animations_enabled': animationsEnabled,
      'power_saving': powerSaving,
      'cache_media': cacheMedia,
    },
  };

  AppPreferences copyWith({
    String? locale,
    AppThemePreference? theme,
    double? textScale,
    bool? animationsEnabled,
    bool? powerSaving,
    bool? autoDownloadMedia,
    bool? cacheMedia,
    bool? pushEnabled,
    bool? pushMessagePreview,
    bool? sendReadReceipts,
    bool? showTypingStatus,
    bool? showLastSeen,
  }) {
    return AppPreferences(
      locale: locale ?? this.locale,
      theme: theme ?? this.theme,
      textScale: textScale ?? this.textScale,
      animationsEnabled: animationsEnabled ?? this.animationsEnabled,
      powerSaving: powerSaving ?? this.powerSaving,
      autoDownloadMedia: autoDownloadMedia ?? this.autoDownloadMedia,
      cacheMedia: cacheMedia ?? this.cacheMedia,
      pushEnabled: pushEnabled ?? this.pushEnabled,
      pushMessagePreview: pushMessagePreview ?? this.pushMessagePreview,
      sendReadReceipts: sendReadReceipts ?? this.sendReadReceipts,
      showTypingStatus: showTypingStatus ?? this.showTypingStatus,
      showLastSeen: showLastSeen ?? this.showLastSeen,
    );
  }
}

Map<String, dynamic>? _map(Object? value) {
  return value is Map ? Map<String, dynamic>.from(value) : null;
}

String _locale(Object? value) => value == 'en' ? 'en' : 'ru';

AppThemePreference _theme(Object? value) {
  return switch (value) {
    'system' => AppThemePreference.system,
    'light' => AppThemePreference.light,
    _ => AppThemePreference.dark,
  };
}

double _scale(Object? value) {
  final scale = value is num ? value.toDouble() : 1.0;
  return scale.clamp(0.85, 1.35).toDouble();
}

bool _bool(Object? value, bool fallback) => value is bool ? value : fallback;
